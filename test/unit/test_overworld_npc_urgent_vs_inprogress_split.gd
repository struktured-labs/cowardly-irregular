extends GutTest

## Regression + design test for the urgent-vs-in-progress routing split.
##
## Bug (msg 2164, huddle 2124/2126, Milo v2 blocker): OverworldNPC's
## routing ladder (quest > dynamic > scripted) called run_giver_dialogue
## whenever has_giver_business(npc_id) was true — including the
## in_progress-flavor case where the NPC is the giver of an ACTIVE quest
## but the current objective is not a talk targeting them. That path
## always played the giver's "in_progress" flavor line and NEVER let
## dynamic-LLM chat fire while the quest was active. For LLM-opt-in
## NPCs like Milo (chapter_three is playable on main), this shadowed
## quest-aware idle chat that the LLM sampler is meant to produce.
##
## Fix: OverworldNPC._quest_should_yield_to_llm(quest_sys, has_giver)
## consults QuestSystem.giver_business_kind() and yields ONLY when
##   1) has_giver is true (the NPC is a giver of an offerable/active quest)
##   2) the NPC is LLM-opt-in (dynamic AND persona != "")
##   3) kind is NOT "offer" and NOT "talk" (in_progress flavor only)
##
## Invariants preserved (cowir-main msg 2591):
##   - Non-LLM NPCs (dynamic=false) run every giver interaction through
##     run_giver_dialogue as before — the ladder is unchanged for them.
##   - Story cutscenes still preempt dynamic-LLM via the story_pending
##     check on the LLM branch (not tested here — covered elsewhere).


const NPC_SCRIPT_PATH: String = "res://src/exploration/OverworldNPC.gd"


## Nested stub: mimics QuestSystem's surface used by the split.
class StubQuestSystem:
	extends Node
	var _has_giver: bool = false
	var _kind: String = ""
	var last_npc_id: String = ""

	func has_giver_business(id: String) -> bool:
		last_npc_id = id
		return _has_giver

	func giver_business_kind(id: String) -> String:
		last_npc_id = id
		return _kind


## Nested stub without giver_business_kind — proves the defensive
## has_method guard prevents crashes when QuestSystem is an older
## build that never learned the kind primitive.
class StubQuestSystemNoKind:
	extends Node
	var _has_giver: bool = false

	func has_giver_business(id: String) -> bool:
		return _has_giver


func _make_npc(is_dynamic: bool, persona_str: String, id: String) -> Node:
	var NPC: Script = load(NPC_SCRIPT_PATH)
	var npc = NPC.new()
	npc.dynamic = is_dynamic
	npc.persona = persona_str
	npc.npc_id = id
	npc.npc_name = id
	add_child_autofree(npc)
	return npc


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


# ── Behavior tests: exercise the routing decision directly.

func test_non_llm_npc_never_yields_even_on_in_progress() -> void:
	var npc = _make_npc(false, "", "generic_villager")
	var stub = StubQuestSystem.new()
	stub._has_giver = true
	stub._kind = ""
	add_child_autofree(stub)
	assert_false(npc._quest_should_yield_to_llm(stub, true),
		"non-LLM NPC must ALWAYS run giver dialogue — the split only opens for LLM-opt-in NPCs")


func test_llm_opt_in_no_giver_never_yields() -> void:
	var npc = _make_npc(true, "milo", "milo")
	var stub = StubQuestSystem.new()
	stub._has_giver = false
	stub._kind = ""
	add_child_autofree(stub)
	assert_false(npc._quest_should_yield_to_llm(stub, false),
		"has_giver=false means notify_talk branch will run; yield gate must not fire here")


func test_llm_opt_in_offer_preempts_dynamic() -> void:
	var npc = _make_npc(true, "milo", "milo")
	var stub = StubQuestSystem.new()
	stub._has_giver = true
	stub._kind = "offer"
	add_child_autofree(stub)
	assert_false(npc._quest_should_yield_to_llm(stub, true),
		"URGENT: pending quest offer must preempt dynamic chat — cannot be shadowed by idle LLM lines")


func test_llm_opt_in_talk_completion_preempts_dynamic() -> void:
	var npc = _make_npc(true, "milo", "milo")
	var stub = StubQuestSystem.new()
	stub._has_giver = true
	stub._kind = "talk"
	add_child_autofree(stub)
	assert_false(npc._quest_should_yield_to_llm(stub, true),
		"URGENT: pending talk-completion (turn-in / talk-objective ready) must preempt dynamic chat")


func test_llm_opt_in_in_progress_flavor_yields() -> void:
	var npc = _make_npc(true, "milo", "milo")
	var stub = StubQuestSystem.new()
	stub._has_giver = true
	stub._kind = ""
	add_child_autofree(stub)
	assert_true(npc._quest_should_yield_to_llm(stub, true),
		"THE FIX: LLM-opt-in NPC + active giver + no urgent business → yield to dynamic-LLM path")


func test_missing_giver_business_kind_method_is_defensive() -> void:
	var npc = _make_npc(true, "milo", "milo")
	var stub = StubQuestSystemNoKind.new()
	stub._has_giver = true
	add_child_autofree(stub)
	assert_false(npc._quest_should_yield_to_llm(stub, true),
		"QuestSystem without giver_business_kind must NOT crash — fall back to old behavior (run_giver_dialogue)")


func test_empty_persona_string_does_not_yield_even_if_dynamic_true() -> void:
	var npc = _make_npc(true, "", "unnamed_dyn")
	var stub = StubQuestSystem.new()
	stub._has_giver = true
	stub._kind = ""
	add_child_autofree(stub)
	assert_false(npc._quest_should_yield_to_llm(stub, true),
		"dynamic=true but persona empty is not a full LLM-opt-in — no persona means nothing for the LLM to sample")


# ── Source-inspection regressions: pin the wiring so future refactors
# ── don't silently regress the split back into the always-preempt shape.

func test_source_uses_yield_to_llm_gate_in_routing_block() -> void:
	var src = _read(NPC_SCRIPT_PATH)
	assert_true(src.find("_quest_should_yield_to_llm(") != -1,
		"OverworldNPC must consult _quest_should_yield_to_llm in the routing block (regression: silent revert to always-preempt)")
	assert_true(src.find("if has_giver and not yield_to_llm:") != -1,
		"routing must gate run_giver_dialogue on 'has_giver AND NOT yield_to_llm' — the fix hinge")


func test_source_preserves_routing_priority_invariant_comment() -> void:
	var src = _read(NPC_SCRIPT_PATH)
	assert_true(src.find("quest > dynamic > static") != -1 or src.find("quest > dynamic > scripted") != -1,
		"routing ladder invariant reference (quest > dynamic > scripted) must stay pinned in a comment near the routing block")


func test_helper_reads_giver_business_kind_from_quest_system() -> void:
	var src = _read(NPC_SCRIPT_PATH)
	assert_true(src.find("giver_business_kind") != -1,
		"helper must consume QuestSystem.giver_business_kind() — it's the primitive that distinguishes offer/talk from in_progress-flavor")
