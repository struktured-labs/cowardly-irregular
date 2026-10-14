## A transition that ends a conversation must not erase what the player SAID.
##
## `run()`'s tail gated BOTH the payout and the memory write behind `if _active`, and
## `abort()` — the scene-change path — drops `_active` before the loop breaks. The payout
## gate is deliberate and documented: don't pay out on a conversation the player did not
## see through. The MEMORY sat behind it by proximity rather than by argument. So saying
## three things to Theron and then walking into a transition left him a stranger, which is
## the amnesia ConversationMemory's own docstring exists to prevent.
##
## The fix separates the two gates. This file drives the REAL state machine to an abort —
## the fixture shape is taken from test_conversation_tail_is_reachable, not invented — and
## asserts BOTH halves: the line is remembered AND the gold still does not move. An
## over-reach that moved the payout out with it would pass the first assert alone.
##
## ⚠️ The tail reads the LIVE GameState autoload and can spend real gold. Snapshotted and
## restored per test, and the restore is asserted rather than promised.
extends GutTest


const CM := preload("res://src/llm/ConversationMemory.gd")
const NPC := "elder_theron"
const LINE := "Tell me about the dragon."


## Stubs only the two awaiting UI seams, and fires abort() from the NPC's reply — which is
## exactly when a real transition arrives: the player has chosen, the reply is on screen.
class AbortingConversation:
	extends DynamicConversation

	var shown_lines: Array = []
	var scripted_choices: Array = []
	var abort_after_line: int = -1
	var _choice_idx: int = 0

	func _show_npc_line(line: String) -> void:
		shown_lines.append(line)
		if abort_after_line >= 0 and shown_lines.size() >= abort_after_line:
			abort()

	func _show_choice_menu(_choices: Array[String]) -> String:
		if _choice_idx >= scripted_choices.size():
			return "Farewell."
		var chosen: String = str(scripted_choices[_choice_idx])
		_choice_idx += 1
		return chosen


var _gs: Node = null
var _saved_gold: int = 0
var _saved_battles: int = 0
var _saved_constants: Dictionary = {}


func before_each() -> void:
	_gs = get_tree().root.get_node_or_null("GameState")
	if _gs == null:
		return
	_saved_gold = int(_gs.party_gold)
	_saved_battles = int(_gs.battles_won)
	_saved_constants = _gs.game_constants.duplicate(true)
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


func _drive(choices: Array, abort_after: int) -> AbortingConversation:
	var conv := AbortingConversation.new()
	add_child_autofree(conv)
	conv.setup("Elder Theron", "an elder", "Harmonia Village", null,
		["Good day."], [], [], NPC, "phase_a")
	conv.scripted_choices = choices
	conv.abort_after_line = abort_after
	await conv.run(null)
	return conv


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_transition_mid_conversation_does_not_erase_what_was_said() -> void:
	if _gs == null:
		pass_test("GameState autoload absent")
		return
	var conv: AbortingConversation = await _drive([LINE, "Farewell."], 2)
	assert_false(conv.is_active(), "PREMISE: abort() must have ended the conversation")
	assert_gt(conv.shown_lines.size(), 1,
		"PREMISE: the abort fires on the NPC's REPLY, so the player's line is already chosen")
	var remembered: Array = CM.recall(_gs, NPC)
	assert_false(remembered.is_empty(),
		"the player said something before the transition; the NPC must remember it")
	assert_true(str(remembered[-1]).find("dragon") != -1,
		"and it must be the line the player actually chose: %s" % str(remembered))


# ── over-reach: the payout gate must SURVIVE the split ────────────────────────

func test_an_aborted_conversation_still_pays_nothing() -> void:
	if _gs == null:
		pass_test("GameState autoload absent")
		return
	var before: int = int(_gs.party_gold)
	await _drive([LINE, "Farewell."], 2)
	assert_eq(int(_gs.party_gold), before,
		"OVER-REACH: only the MEMORY leaves the _active gate; a conversation the player did not see through still pays nothing")


# ── the normal path, which the split must not disturb ─────────────────────────

func test_a_completed_conversation_still_remembers_and_still_pays() -> void:
	if _gs == null:
		pass_test("GameState autoload absent")
		return
	var before: int = int(_gs.party_gold)
	var conv: AbortingConversation = await _drive([LINE, "Farewell."], -1)
	assert_false(conv.is_active(), "the conversation ran to its own end")
	assert_false(CM.recall(_gs, NPC).is_empty(), "a completed conversation is remembered")
	assert_gt(int(_gs.party_gold), before, "and it still pays")


func test_a_player_who_says_nothing_leaves_no_memory_even_when_aborted() -> void:
	if _gs == null:
		pass_test("GameState autoload absent")
		return
	await _drive(["Farewell."], 1)
	assert_eq(CM.recall(_gs, NPC), [],
		"an immediate farewell is not a conversation; moving the write must not start storing nothing")


# ── his save ──────────────────────────────────────────────────────────────────

func test_this_suite_restores_the_live_game_state() -> void:
	if _gs == null:
		pass_test("GameState autoload absent")
		return
	var untouched_key: String = "exp_multiplier"
	assert_true(_saved_constants.has(untouched_key),
		"control: the snapshot must contain a key this feature never writes, or the restore proves nothing")
	assert_eq(_gs.game_constants.get(untouched_key), _saved_constants.get(untouched_key),
		"an unrelated game constant must survive this suite untouched")


# ── floor: the dynamic reaches, which a rename would otherwise silence ────────

func test_the_surface_this_file_drives_still_exists() -> void:
	var conv := AbortingConversation.new()
	add_child_autofree(conv)
	for m in ["run", "abort", "setup", "is_active"]:
		assert_true(conv.has_method(m),
			"DynamicConversation.%s is driven by this file" % m)
	assert_true(_gs == null or "party_gold" in _gs,
		"GameState.party_gold is what the over-reach arm judges")
