extends GutTest
## 2026-11-28 (cowir-story): after the turn-in a giver has no quest business, so it fell back to its constructor lines, and the five
## W1 dragon-village givers kept describing their problem as still open (Kes: "There's a man on the road east in gold armor. He won't
## move." after you moved him). A quest may author dialogue.idle_after_complete, which the scripted path speaks once it is complete.

const NPCScript := preload("res://src/exploration/OverworldNPC.gd")
const W1_GIVERS := {
	"w1_eldertree_rangers_empty_house": "elder_vesper",
	"w1_frosthold_meltwater_clock": "clockkeeper_yara",
	"w1_grimhollow_foremans_ledger": "miner_trude",
	"w1_ironhaven_flame_speaks_wrong": "temple_keeper_sella",
	"w1_sandrift_water_on_the_road": "caravan_master_kes",
}
## Harmonia's givers whose own lines describe the job as open (Bram: "One came BACK.", Rowan's unsent letter). 2026-11-28.
const HARMONIA_GIVERS := {
	"world1_one_chicken_problem": "farmer_aldwick",
	"world1_untested_edge": "bram_smith",
	"world1_word_from_capital": "rowan_harmonia",
}
## Maple Heights givers whose own lines argue the problem (Gerald: "That flower is NOT a violation.", Casper: "the wrong blue"). 2026-11-28.
const W2_GIVERS := {
	"world2_acceptable_variance": "gerald_w2",
	"world2_wrong_blue": "casper_kid",
}
const OPEN_LINE := "There's a man on the road east in gold armor. He won't move."

var _saved_quests: Dictionary


func before_each() -> void:
	_saved_quests = GameState.quests.duplicate(true)


func after_each() -> void:
	GameState.quests = _saved_quests


func _giver(npc_id: String) -> Node:
	var npc: Node = NPCScript.new()
	npc.npc_name = "Giver"
	npc.npc_id = npc_id
	npc.dialogue_lines = [OPEN_LINE]
	add_child_autofree(npc)
	return npc


func _set_state(qid: String, state: String) -> void:
	if state == "":
		GameState.quests.erase(qid)
	else:
		GameState.quests[qid] = {"state": state, "objective_index": 0}


func _authored(qid: String) -> Array:
	return (QuestSystem.get_quest(qid).get("dialogue", {}) as Dictionary).get("idle_after_complete", [])


func test_a_finished_giver_speaks_its_after_lines() -> void:
	var qid := "w1_sandrift_water_on_the_road"
	assert_false(_authored(qid).is_empty(), "CONTROL: the quest authors after-lines")
	var kes: Node = _giver(W1_GIVERS[qid])
	_set_state(qid, "complete")
	assert_eq(kes._static_source_lines(QuestSystem), _authored(qid), "a completed quest's giver speaks idle_after_complete")
	assert_false(kes._static_source_lines(QuestSystem).has(OPEN_LINE), "and no longer the line that says the road is blocked")


func test_an_unfinished_quest_keeps_the_givers_own_lines() -> void:
	var qid := "w1_sandrift_water_on_the_road"
	var kes: Node = _giver(W1_GIVERS[qid])
	for state in ["", "active"]:
		_set_state(qid, state)
		assert_eq(kes._static_source_lines(QuestSystem), [OPEN_LINE], "state '%s' keeps the constructor lines" % state)


func test_a_quest_without_after_lines_changes_nothing() -> void:
	var qid := "world1_fools_spread"
	assert_true(_authored(qid).is_empty(), "CONTROL: this quest authors none")
	var orrery: Node = _giver("madame_orrery_w1")
	_set_state(qid, "complete")
	assert_eq(orrery._static_source_lines(QuestSystem), [OPEN_LINE], "no idle_after_complete means the giver's own lines")


func test_every_w1_giver_with_an_open_problem_has_after_lines() -> void:
	var gaps: Array = []
	var givers: Dictionary = W1_GIVERS.merged(HARMONIA_GIVERS).merged(W2_GIVERS)
	for qid in givers:
		var q: Dictionary = QuestSystem.get_quest(qid)
		assert_eq(str(q.get("giver", {}).get("npc_id", "")), givers[qid], "CONTROL: %s is given by %s" % [qid, givers[qid]])
		var lines: Array = _authored(qid)
		if lines.size() < 2:
			gaps.append(qid)
		for l in lines:
			assert_true(l is String and not (l as String).strip_edges().is_empty(), "%s: a blank or non-string after-line" % qid)
	assert_eq(gaps, [], "W1 givers whose problem still reads as open after the turn-in")
