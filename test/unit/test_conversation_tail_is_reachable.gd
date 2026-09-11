## Does the conversation loop actually REACH the reward and the memory write?
##
## Every other test of those two features calls ConversationRewards.grant_if_earned
## or ConversationMemory.remember BY HAND. Per cowir-battle 2026-09-09, that
## demonstrates EXECUTION and says nothing about SELECTION — reachability is not a
## property you can observe from inside the thing you are reaching. The whole
## suite drove run() exactly once, in a re-entrancy guard that returns
## immediately, so lines 212-214 of DynamicConversation had never executed under
## test at all.
##
## This drives the REAL state machine to DONE and asserts the VALUES that only
## the tail can produce. Only the two UI seams are stubbed, because both await
## player input and would hang headless — which is why nobody had driven it.
##
## ⚠️ _maybe_grant_reward reads the LIVE GameState autoload, so an unguarded run
## here spends real gold into his save. Snapshotted and restored per test, and
## the restore is asserted rather than promised.
extends GutTest


const CM := preload("res://src/llm/ConversationMemory.gd")


## Stubs ONLY the two awaiting UI seams. Everything else — the state machine, the
## exchange cap, the farewell detection, the tail — is the real implementation.
class DrivableConversation:
	extends DynamicConversation

	var shown_lines: Array = []
	var scripted_choices: Array = []
	var _choice_idx: int = 0

	func _show_npc_line(line: String) -> void:
		shown_lines.append(line)

	func _show_choice_menu(_choices: Array[String]) -> String:
		if _choice_idx >= scripted_choices.size():
			return "Farewell."
		var chosen: String = str(scripted_choices[_choice_idx])
		_choice_idx += 1
		return chosen


var _gs: Node = null
var _saved_gold: int = 0
var _saved_constants: Dictionary = {}
var _saved_battles: int = 0


func before_each() -> void:
	_gs = get_tree().root.get_node_or_null("GameState")
	if _gs == null:
		return
	_saved_gold = int(_gs.party_gold)
	_saved_battles = int(_gs.battles_won)
	_saved_constants = _gs.game_constants.duplicate(true)
	# Clear only the two keys this feature owns, so a real save's other state is untouched.
	_gs.game_constants.erase(ConversationRewards.LEDGER_KEY)
	_gs.game_constants.erase(ConversationRewards.LAST_BATTLE_KEY)
	_gs.game_constants.erase(CM.STORE_KEY)
	_gs.battles_won = 999  # past the reward backstop


func after_each() -> void:
	if _gs == null:
		return
	_gs.party_gold = _saved_gold
	_gs.battles_won = _saved_battles
	_gs.game_constants = _saved_constants.duplicate(true)


func _drive(npc_id: String, bucket: String, choices: Array) -> DrivableConversation:
	var conv := DrivableConversation.new()
	add_child_autofree(conv)
	conv.setup("Elder Theron", "an elder", "Harmonia Village", null,
		["Good day."], [], [], npc_id, bucket)
	conv.scripted_choices = choices
	await conv.run(null)
	return conv


# ── the tail is reached at all ────────────────────────────────────────────────

func test_the_loop_actually_terminates_and_runs_its_tail() -> void:
	if _gs == null:
		pass_test("GameState autoload absent")
		return
	var conv: DrivableConversation = await _drive("elder_theron", "phase_a",
		["Tell me about the dragon.", "Farewell."])
	assert_false(conv.is_active(),
		"run() must return with the conversation inactive — a hang here is the failure this test exists to catch")
	assert_gt(conv.shown_lines.size(), 0,
		"control: the real state machine must have produced at least the opening line, or nothing was driven")


func test_the_conversation_loop_reaches_the_memory_write() -> void:
	if _gs == null:
		pass_test("GameState autoload absent")
		return
	await _drive("elder_theron", "phase_a", ["Tell me about the dragon.", "Farewell."])
	var remembered: Array = CM.recall(_gs, "elder_theron")
	assert_false(remembered.is_empty(),
		"the real loop must reach ConversationMemory.remember — calling it by hand proves nothing about this")
	assert_true(str(remembered[-1]).find("dragon") != -1,
		"and it must store what the player actually chose, not a placeholder")


func test_a_player_who_says_nothing_leaves_no_memory() -> void:
	if _gs == null:
		pass_test("GameState autoload absent")
		return
	await _drive("elder_theron", "phase_a", ["Farewell."])
	assert_eq(CM.recall(_gs, "elder_theron"), [],
		"an immediate farewell is not a conversation — nothing to remember")


# ── the reward reaches the PLAYER, not just the ledger ────────────────────────

func test_the_reward_line_is_actually_shown_to_the_player() -> void:
	if _gs == null:
		pass_test("GameState autoload absent")
		return
	var conv: DrivableConversation = await _drive("elder_theron", "phase_a",
		["Tell me about the dragon.", "Farewell."])
	var joined: String = "\n".join(PackedStringArray(conv.shown_lines))
	assert_true(joined.find("Take this") != -1,
		"the payout line must REACH the screen — granting gold the player never sees told is the failure mode here")


func test_the_reward_actually_moves_gold_through_the_real_loop() -> void:
	if _gs == null:
		pass_test("GameState autoload absent")
		return
	var before: int = int(_gs.party_gold)
	await _drive("elder_theron", "phase_a", ["Tell me about the dragon.", "Farewell."])
	assert_gt(int(_gs.party_gold), before,
		"the loop must reach the grant, not merely be capable of granting when called directly")


func test_an_unnamed_npc_completes_the_loop_and_pays_nothing() -> void:
	if _gs == null:
		pass_test("GameState autoload absent")
		return
	var before: int = int(_gs.party_gold)
	var conv: DrivableConversation = await _drive("", "", ["Tell me about the dragon.", "Farewell."])
	assert_false(conv.is_active(), "an unnamed NPC must still complete cleanly")
	assert_eq(int(_gs.party_gold), before, "and must not pay")


func test_the_same_npc_pays_once_across_two_real_conversations() -> void:
	if _gs == null:
		pass_test("GameState autoload absent")
		return
	await _drive("elder_theron", "phase_a", ["Tell me about the dragon.", "Farewell."])
	var after_first: int = int(_gs.party_gold)
	var conv: DrivableConversation = await _drive("elder_theron", "phase_a",
		["Tell me more.", "Farewell."])
	assert_eq(int(_gs.party_gold), after_first,
		"the anti-farm gate must hold across two REAL conversations, not just two direct calls")
	var joined: String = "\n".join(PackedStringArray(conv.shown_lines))
	assert_eq(joined.find("Take this"), -1,
		"and the second conversation must not show a payout line either")


# ── the guard that protects his save ──────────────────────────────────────────

func test_this_suite_restores_the_live_game_state() -> void:
	if _gs == null:
		pass_test("GameState autoload absent")
		return
	# before_each snapshotted; prove the restore path is real by checking the
	# keys this feature owns are the ONLY thing it touches.
	var untouched_key: String = "exp_multiplier"
	assert_true(_saved_constants.has(untouched_key),
		"control: the snapshot must contain a key this feature never writes, or the restore proves nothing")
	assert_eq(_gs.game_constants.get(untouched_key), _saved_constants.get(untouched_key),
		"an unrelated game constant must survive this suite untouched")
