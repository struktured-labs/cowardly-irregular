extends GutTest

## The HUD tracker's side-quest line pinned active[0] — FILE-LOAD
## order, not player intent. Accept Milo's quest, then Orrery's, and
## the tracker showed Milo until his quest completed. It now follows
## QuestSystem.last_progressed_quest_id (set on accept + every
## objective completion), falling back to active[0].

const TrackerScript = preload("res://src/exploration/QuestTracker.gd")

var _saved_quests: Dictionary
var _saved_flags: Dictionary
var _saved_lp: String


func before_each() -> void:
	_saved_quests = GameState.quests.duplicate(true)
	# accept() cascades flag_on_complete mirrors into story_flags —
	# snapshot the whole dict so the cascade can't leak between tests.
	_saved_flags = GameState.story_flags.duplicate(true)
	_saved_lp = QuestSystem.last_progressed_quest_id


func after_each() -> void:
	GameState.quests = _saved_quests
	GameState.story_flags = _saved_flags
	QuestSystem.last_progressed_quest_id = _saved_lp


func test_picker_prefers_last_progressed() -> void:
	assert_eq(TrackerScript._pick_tracked_quest(["a", "b", "c"], "b"), "b")


func test_picker_falls_back_to_first_when_unset_or_gone() -> void:
	assert_eq(TrackerScript._pick_tracked_quest(["a", "b"], ""), "a")
	assert_eq(TrackerScript._pick_tracked_quest(["a", "b"], "completed_one"), "a",
		"a completed (no-longer-active) quest must not be tracked")


func test_accept_marks_quest_as_last_progressed() -> void:
	var qid := "world1_fools_spread"
	GameState.quests.erase(qid)
	var prereq: String = str(QuestSystem.get_quest(qid).get("prereq_flag", ""))
	var saved: Variant = GameState.story_flags.get(prereq, null) if prereq != "" else null
	if prereq != "":
		GameState.story_flags[prereq] = true
	QuestSystem.accept(qid)
	assert_eq(QuestSystem.last_progressed_quest_id, qid,
		"accepting a quest must move the tracker to it")
	if prereq != "":
		if saved == null:
			GameState.story_flags.erase(prereq)
		else:
			GameState.story_flags[prereq] = saved


func test_tracker_reacts_to_quest_signals() -> void:
	# Signal-driven feedback: the tracker must connect to QuestSystem
	# and refresh instantly (the 2s poll was the only consumer before —
	# mid-quest progress was silent and laggy).
	var host := Node.new()
	add_child_autofree(host)
	var tracker: Node = TrackerScript.new()
	host.add_child(tracker)
	tracker.setup(host)
	assert_true(QuestSystem.objective_advanced.is_connected(tracker._on_quest_progress),
		"tracker must listen to objective_advanced")
	assert_true(QuestSystem.quest_state_changed.is_connected(tracker._on_quest_progress),
		"tracker must listen to quest_state_changed")
	GameState.quests["world1_chapter_three"] = {"state": "active", "objective_index": 3}
	QuestSystem.objective_advanced.emit("world1_chapter_three", 3)
	assert_true(tracker._side_label.visible,
		"signal must drive an instant refresh (no poll wait)")
	# Pulse started: modulate deviates from plain white right after.
	assert_ne(tracker._side_label.modulate, Color.WHITE,
		"progress pulse must fire on the side line")
	tracker.queue_free()


func test_objective_completion_marks_quest() -> void:
	QuestSystem.last_progressed_quest_id = ""
	GameState.quests["world1_chapter_three"] = {"state": "active", "objective_index": 0}
	QuestSystem._complete_objective("world1_chapter_three", 0)
	assert_eq(QuestSystem.last_progressed_quest_id, "world1_chapter_three",
		"progressing an objective must move the tracker to that quest")
