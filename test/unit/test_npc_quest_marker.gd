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


func test_offer_shows_exclamation() -> void:
	GameState.quests.erase(QID)
	if _prereq_flag != "":
		GameState.story_flags[_prereq_flag] = true
	var npc := _make_milo()
	assert_eq(npc._quest_marker.text, "!",
		"a NEW quest at this giver reads '!'")


func test_active_talk_objective_shows_question_mark() -> void:
	# c3 step 1 (index 0) is a talk targeting Milo — an active quest
	# wanting a conversation here must read "?" not "!".
	GameState.quests[QID] = {"state": "active", "objective_index": 0}
	var npc := _make_milo()
	assert_true(npc._quest_marker.visible)
	assert_eq(npc._quest_marker.text, "?",
		"active talk objective at this NPC reads '?'")


func test_gated_talk_step_shows_nothing() -> void:
	# c3 step 3 (index 2) is a talk at Milo REQUIRING the autobattle
	# exercise flag — before the exercise is done, a "?" would lie.
	GameState.quests[QID] = {"state": "active", "objective_index": 2}
	GameState.story_flags.erase("quest_world1_chapter_three_autobattle_run")
	var npc := _make_milo()
	assert_false(npc._quest_marker.visible,
		"required_flag-gated talk steps must not mark until the flag is earned")


func test_markerless_quest_never_marks_its_giver() -> void:
	# word_from_capital is "deliberately markerless" (authoring notes:
	# Rowan only opens up on direct interact). The marker feature
	# violated that the day it shipped — quests now opt out via
	# "markerless": true, which giver_business_kind honors for BOTH
	# offer and talk affordances. Dialogue routing stays untouched.
	var q: Dictionary = QuestSystem.get_quest("world1_word_from_capital")
	assert_true(bool(q.get("markerless", false)),
		"word_from_capital must stay markerless — it's authored that way")
	GameState.quests.erase("world1_word_from_capital")
	var rowan: Node = NPCScript.new()
	rowan.npc_name = "Rowan"
	rowan.npc_id = str(q["giver"]["npc_id"])
	add_child_autofree(rowan)
	assert_false(rowan._quest_marker.visible,
		"markerless giver must carry no '!' even while offerable")
	# ...but interact routing still owns the dialogue:
	assert_true(QuestSystem.has_giver_business(rowan.get_npc_id()) or not QuestSystem.is_offerable("world1_word_from_capital"),
		"markerless must not break dialogue ownership when offerable")


func test_non_giver_talk_target_gets_question_mark() -> void:
	# fools_spread step 2 (index 1) targets Phil the Lost — NOT the
	# giver. The '?' must follow the conversation, not the giver.
	# Step 2 is gated on the reading-received flag (set by step 1) —
	# earn it so the "?" is truthful, exactly as in real play.
	var gate: String = str(QuestSystem.get_quest("world1_fools_spread")["objectives"][1].get("required_flag", ""))
	var saved: Variant = GameState.story_flags.get(gate, null) if gate != "" else null
	if gate != "":
		GameState.story_flags[gate] = true
	GameState.quests["world1_fools_spread"] = {"state": "active", "objective_index": 1}
	var phil: Node = NPCScript.new()
	phil.npc_name = "Phil the Lost"
	add_child_autofree(phil)
	assert_true(phil._quest_marker.visible, "talk target must be marked")
	assert_eq(phil._quest_marker.text, "?")
	GameState.quests.erase("world1_fools_spread")
	if gate != "":
		if saved == null:
			GameState.story_flags.erase(gate)
		else:
			GameState.story_flags[gate] = saved
