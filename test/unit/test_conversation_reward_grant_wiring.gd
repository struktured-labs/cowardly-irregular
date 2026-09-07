## Wiring guard for ConversationRewards.grant_if_earned — the payout half.
##
## test_conversation_rewards_cannot_be_farmed.gd covers evaluate(); this covers
## what happens AFTER eligibility: that a grant lands, that it records the claim,
## and — the load-bearing one — that a payout which grants NOTHING does not burn
## the NPC's single claim for the quest phase.
##
## Gold amounts are deliberately NOT asserted. They are tunable table values, so
## pinning one fails a correct retune and passes a wrong one; these assert the
## relationship (gold rose, summary non-empty) instead.
extends GutTest


class FakeGameState:
	extends Node
	var game_constants: Dictionary = {}
	var battles_won: int = 0
	var gold: int = 0
	func add_gold(amount: int) -> void:
		gold += amount


var _gs: FakeGameState = null


func before_each() -> void:
	_gs = FakeGameState.new()
	add_child_autofree(_gs)
	# Far past the battle backstop so eligibility turns on the claim ledger alone.
	_gs.battles_won = 999
	ConversationRewards.reset_table_cache()


func test_resolve_npc_id_prefers_the_authored_id() -> void:
	assert_eq(ConversationRewards.resolve_npc_id("scholar_milo", "Scholar Milo"), "scholar_milo",
		"an authored npc_id must win over the display name")


func test_resolve_npc_id_slugs_the_name_when_no_id_authored() -> void:
	assert_eq(ConversationRewards.resolve_npc_id("", "Elder Theron"), "elder_theron",
		"wanderers author no npc_id — the name slug is the reward identity")


func test_eligible_conversation_grants_gold_and_returns_a_summary() -> void:
	var before: int = _gs.gold
	var line: String = ConversationRewards.grant_if_earned(_gs, "elder_theron", "phase_a", 4)
	assert_gt(_gs.gold, before, "an eligible conversation must actually move the player's gold")
	assert_ne(line, "", "a granted reward must return a player-facing summary")


func test_a_granted_reward_records_the_claim() -> void:
	ConversationRewards.grant_if_earned(_gs, "elder_theron", "phase_a", 4)
	var ledger: Dictionary = _gs.game_constants.get(ConversationRewards.LEDGER_KEY, {})
	assert_true(ledger.has("elder_theron@phase_a"),
		"the claim ledger must record npc@phase so the NPC cannot pay out twice")


func test_second_conversation_in_the_same_phase_pays_nothing() -> void:
	ConversationRewards.grant_if_earned(_gs, "elder_theron", "phase_a", 4)
	_gs.battles_won += 999  # clear the backstop so ONLY the claim gate can refuse
	var gold_after_first: int = _gs.gold
	var line: String = ConversationRewards.grant_if_earned(_gs, "elder_theron", "phase_a", 4)
	assert_eq(line, "", "re-talking in the same quest phase must pay nothing")
	assert_eq(_gs.gold, gold_after_first, "and must not move gold")


func test_advancing_the_quest_phase_reopens_the_npc() -> void:
	ConversationRewards.grant_if_earned(_gs, "elder_theron", "phase_a", 4)
	_gs.battles_won += 999
	var before: int = _gs.gold
	var line: String = ConversationRewards.grant_if_earned(_gs, "elder_theron", "phase_b", 4)
	assert_ne(line, "", "a new quest phase must re-open the NPC exactly once")
	assert_gt(_gs.gold, before, "and must actually pay")


func test_a_short_conversation_pays_nothing_and_leaves_the_claim_open() -> void:
	var line: String = ConversationRewards.grant_if_earned(_gs, "elder_theron", "phase_a", 1)
	assert_eq(line, "", "one exchange is not a conversation")
	var ledger: Dictionary = _gs.game_constants.get(ConversationRewards.LEDGER_KEY, {})
	assert_false(ledger.has("elder_theron@phase_a"),
		"a refused conversation must NOT consume the claim — otherwise a drive-by hello burns the reward")


func test_an_unknown_npc_still_pays_from_the_default_entry() -> void:
	var before: int = _gs.gold
	var line: String = ConversationRewards.grant_if_earned(_gs, "nobody_in_the_table", "phase_a", 4)
	assert_ne(line, "", "an NPC with no table entry must fall back to the default, not to silence")
	assert_gt(_gs.gold, before, "the default entry must be a real payout")


func test_empty_npc_id_is_refused() -> void:
	var line: String = ConversationRewards.grant_if_earned(_gs, "", "phase_a", 4)
	assert_eq(line, "", "an unnamed NPC has no stable claim identity and must never pay")


func test_reward_table_parses_and_every_item_id_resolves() -> void:
	var text: String = FileAccess.get_file_as_string(ConversationRewards.TABLE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "conversation_rewards.json must parse to a Dictionary")
	var table: Dictionary = parsed as Dictionary
	assert_true(int(table.get("default", {}).get("gold", 0)) > 0,
		"the default entry must pay something — an all-zero default silently never rewards")
	var entries: Array = [table.get("default", {})]
	for key in (table.get("by_npc", {}) as Dictionary):
		entries.append(table["by_npc"][key])
	var item_system: Node = get_tree().root.get_node_or_null("ItemSystem")
	assert_not_null(item_system, "ItemSystem autoload must be up for this check to mean anything")
	var checked: int = 0
	for entry in entries:
		for spec in (entry.get("items", []) as Array):
			var iid: String = str(spec.get("item_id", ""))
			assert_false(item_system.get_item(iid).is_empty(),
				"reward item '%s' must resolve in items.json — add_item on an unresolvable id makes a dead inventory entry" % iid)
			checked += 1
	assert_gt(checked, 0, "control: the table must actually contain item rewards, or this test proves nothing")
