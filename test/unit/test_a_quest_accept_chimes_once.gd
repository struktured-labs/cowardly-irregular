extends GutTest

## struktured via cowir-main 21087: "when u accept a quest a pleasant noise should play". The quest cues are one family —
## accept, a quiet progress chime, a bigger completion — and each moment plays exactly one of them.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func test_each_quest_moment_has_its_own_cue() -> void:
	assert_eq(QuestTracker.quest_cue_for("active", 99999), "quest_accept", "accepting a quest plays the accept chime")
	assert_eq(QuestTracker.quest_cue_for("complete", 99999), "quest_complete", "completing plays the completion jingle")
	assert_eq(QuestTracker.quest_cue_for(1, 99999), "quest_progress", "an objective advancing plays the quiet chime")
	assert_eq(QuestTracker.quest_cue_for("some_future_state", 99999), "", "an unknown state stays silent rather than guessing")


func test_the_cues_exist_and_completion_is_the_biggest() -> void:
	var m: Dictionary = SoundManager._sfx_manifest
	for k in ["quest_accept", "quest_progress", "quest_complete"]:
		assert_true(m.has(k) and FileAccess.file_exists(str(m[k].get("file", ""))), "%s must be in the manifest with its file" % k)
	var acc = load(str(m["quest_accept"]["file"]))
	var done = load(str(m["quest_complete"]["file"]))
	var prog = load(str(m["quest_progress"]["file"]))
	assert_true(acc != null and done != null and prog != null, "PREMISE: all three cues load")
	if acc and done and prog:
		assert_lt(prog.get_length(), acc.get_length(), "progress is the small one")
		assert_lt(acc.get_length(), done.get_length(), "completion is the bigger cue, accept a step smaller")


func test_a_talk_to_giver_step_does_not_chime_a_second_time() -> void:
	assert_eq(QuestTracker.quest_cue_for(1, 10), "", "the objective that completes in the accept's own frame is swallowed")
	assert_eq(QuestTracker.quest_cue_for(1, QuestTracker.ACCEPT_SWALLOWS_PROGRESS_MS), "quest_progress", "CONTROL: a later step chimes")


## Every handler connected to a QuestSystem signal: only QuestTracker's may make a sound, or one accept plays two cues.
func test_only_one_listener_sounds_the_quest_family() -> void:
	var dir := "res://src"
	var sounding: Array = []
	var connected := 0
	var stack: Array = [dir]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(d):
			stack.append(d + "/" + sub)
		for f in DirAccess.get_files_at(d):
			if not f.ends_with(".gd"):
				continue
			var path := d + "/" + f
			var code := GdSource.code_of(path)
			var re := RegEx.create_from_string("(quest_state_changed|objective_advanced)\\.connect\\((\\w+)")
			for hit in re.search_all(code):
				connected += 1
				var handler := hit.get_string(2)
				var start := code.find("func %s(" % handler)
				if start < 0:
					continue
				var nxt := code.find("\nfunc ", start + 1)
				var body := code.substr(start, (nxt - start) if nxt > start else -1)
				if body.contains("SoundManager.play") and not path.ends_with("QuestTracker.gd"):
					sounding.append("%s %s" % [path, handler])
	assert_gt(connected, 3, "PREMISE: the walk must find QuestSystem's listeners (tracker, NPC markers, masterites), found %d" % connected)
	assert_eq(sounding, [], "a second listener plays a sound on a quest signal, so accept would chime twice: %s" % [sounding])
