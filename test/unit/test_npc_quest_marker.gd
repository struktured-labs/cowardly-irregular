extends GutTest

## Quest "!" marker over giver NPCs (2026-07-02). QuestSystem v1
## shipped giver plumbing with zero visual affordance — the W1 givers
## were only discoverable by talking to every NPC. OverworldNPC now
## shows a gold "!" whenever QuestSystem.has_giver_business(npc_id)
## is true, refreshed on quest_state_changed / objective_advanced.

const NPCScript = preload("res://src/exploration/OverworldNPC.gd")
const QID := "world1_chapter_three"

var _saved_quests: Dictionary
var _saved_prereq: Variant
var _prereq_flag: String = ""


func before_each() -> void:
	_saved_quests = GameState.quests.duplicate(true)
	_prereq_flag = str(QuestSystem.get_quest(QID).get("prereq_flag", ""))
	_saved_prereq = GameState.story_flags.get(_prereq_flag, null) if _prereq_flag != "" else null


func after_each() -> void:
	GameState.quests = _saved_quests
	if _prereq_flag != "":
		if _saved_prereq == null:
			GameState.story_flags.erase(_prereq_flag)
		else:
			GameState.story_flags[_prereq_flag] = _saved_prereq


func _make_milo() -> Node:
	var npc: Node = NPCScript.new()
	npc.npc_name = "Scholar Milo"
	npc.npc_id = "scholar_milo"
	add_child_autofree(npc)
	return npc


func test_marker_hidden_without_quest_business() -> void:
	GameState.quests[QID] = {"state": "complete", "objective_index": 6}
	var npc := _make_milo()
	assert_not_null(npc._quest_marker, "marker node must be built")
	assert_false(npc._quest_marker.visible,
		"no offerable/active business → no marker")


func test_marker_shown_when_quest_offerable() -> void:
	GameState.quests.erase(QID)
	if _prereq_flag != "":
		GameState.story_flags[_prereq_flag] = true
	var npc := _make_milo()
	assert_true(npc._quest_marker.visible,
		"offerable quest at this giver must show the '!' marker")


func test_marker_refreshes_on_state_change() -> void:
	GameState.quests.erase(QID)
	if _prereq_flag != "":
		GameState.story_flags[_prereq_flag] = true
	var npc := _make_milo()
	assert_true(npc._quest_marker.visible)
	# Completing the quest ends the business — signal must hide it.
	GameState.quests[QID] = {"state": "complete", "objective_index": 6}
	QuestSystem.quest_state_changed.emit(QID, "complete")
	assert_false(npc._quest_marker.visible,
		"quest_state_changed must re-evaluate the marker")


func test_non_giver_npc_never_marks() -> void:
	GameState.quests.erase(QID)
	if _prereq_flag != "":
		GameState.story_flags[_prereq_flag] = true
	var npc: Node = NPCScript.new()
	npc.npc_name = "Random Villager"
	add_child_autofree(npc)
	assert_false(npc._quest_marker.visible,
		"NPCs with no quests must never show the marker")
