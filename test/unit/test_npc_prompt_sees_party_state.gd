extends GutTest

## An NPC that cannot see a downed party member is not in the world.
## build_npc_opening and build_combined_reply both receive live party state:
## per-member condition, gold, and carried supplies.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const DC_PATH: String = "res://src/llm/DynamicConversation.gd"


func _state() -> Dictionary:
	return {
		"members": [
			{"name": "Fighter", "job": "fighter", "condition": DP.describe_condition(2159, 2159, true)},
			{"name": "Cleric", "job": "cleric", "condition": DP.describe_condition(0, 900, false)},
		],
		"gold": 5482,
		"notable_items": ["hi potion x8", "elixir"],
	}


# ── describe_condition: the HP bands an onlooker would name

func test_downed_wins_over_every_hp_band() -> void:
	assert_true(DP.describe_condition(0, 900, false).contains("DOWNED"), "dead reads as DOWNED")
	assert_true(DP.describe_condition(500, 900, false).contains("DOWNED"),
		"is_alive=false must win even with HP on the clock — a revived-but-flagged-dead PC is still down")


func test_hp_bands_are_ordered_and_distinct() -> void:
	assert_true(DP.describe_condition(10, 1000, true).contains("barely"), "<15% is barely standing")
	assert_true(DP.describe_condition(250, 1000, true).contains("badly"), "<35% is badly hurt")
	assert_true(DP.describe_condition(500, 1000, true).contains("wounded"), "<70% is wounded")
	assert_eq(DP.describe_condition(900, 1000, true), "unhurt", ">=70% is unhurt")


func test_zero_max_hp_does_not_divide_by_zero() -> void:
	assert_eq(DP.describe_condition(0, 0, true), "unhurt", "a malformed entry must degrade, not crash")


# ── the block itself

func test_empty_state_emits_nothing() -> void:
	assert_eq(DP._format_party_state({}), "", "no state means no block — backward compat for every existing caller")


func test_block_names_members_gold_and_supplies() -> void:
	var b: String = DP._format_party_state(_state())
	assert_true(b.contains("Fighter"), "member name present")
	assert_true(b.contains("DOWNED"), "the downed cleric must be visible to the NPC")
	assert_true(b.contains("5482"), "gold present")
	assert_true(b.contains("hi potion x8"), "carried supplies present")
	assert_true(b.contains("Do not recite it"), "the block must tell the LLM to notice, not inventory-dump")


# ── both prompt paths, which is the defect class this guards

func test_opening_and_reply_paths_both_carry_the_party_block() -> void:
	# The Milo defect was a builder that took the context and one that did not.
	# Assert both emit the SAME shared block rather than checking each alone.
	var st: Dictionary = _state()
	var block: String = DP._format_party_state(st)
	assert_false(block.is_empty(), "shared formatter must produce a block — else both asserts below are vacuous")
	var opening: String = DP.build_npc_opening("Milo", "scholar", "Harmonia", [], [], "", st)
	var reply: String = DP.build_combined_reply(
		"Milo", "scholar", "Harmonia", [], "prior", "player said", 4, [], st)
	assert_true(opening.find(block) != -1, "opening path must carry the party block")
	assert_true(reply.find(block) != -1, "reply path must carry the SAME party block")


func test_omitting_party_state_leaves_both_prompts_unchanged() -> void:
	var opening: String = DP.build_npc_opening("Milo", "scholar", "Harmonia", [])
	var reply: String = DP.build_combined_reply("Milo", "scholar", "Harmonia", [], "a", "b", 4)
	assert_true(opening.find("standing in front of you") == -1, "no party state means no block (opening)")
	assert_true(reply.find("standing in front of you") == -1, "no party state means no block (reply)")


# ── the resolver and the dynamic cap

func test_resolver_and_cap_are_wired_in_the_conversation() -> void:
	var f = FileAccess.open(DC_PATH, FileAccess.READ)
	assert_not_null(f, "DynamicConversation must exist")
	var src: String = f.get_as_text()
	f.close()
	assert_true(src.find("_party_state = _resolve_party_state()") != -1,
		"party state must be resolved when a conversation starts")
	assert_true(src.find("_exchange_count >= MAX_EXCHANGES:") == -1,
		"the fixed cap must be gone — a dynamic conversation cannot hard-stop at a constant")
	assert_true(src.find("_exchange_cap()") != -1, "the dynamic cap must be consulted instead")


func test_hp_zero_with_real_max_still_reads_downed() -> void:
	assert_true(DP.describe_condition(0, 900, true).contains("DOWNED"),
		"0 HP against a real max is genuinely down, even if is_alive was not updated yet")
