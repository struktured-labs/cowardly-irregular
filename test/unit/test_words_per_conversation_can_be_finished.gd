extends GutTest

## world4_words_per_conversation was startable and unfinishable: both custom objectives had no emitter.

const QUEST := "world4_words_per_conversation"
const QUEST_PATH := "res://data/quests/world4_words_per_conversation.json"
const QUEST_SYSTEM := "res://src/quests/QuestSystem.gd"
const VILLAGE := "res://src/maps/villages/RivetRowVillage.gd"

## Which emitter satisfies which objective index. Derived flags are checked against the JSON.
const DIALOGUE_OBJ := 1
const EXAMINE_OBJ := 2


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _quest() -> Dictionary:
	var raw: Variant = JSON.parse_string(_read(QUEST_PATH))
	return raw if raw is Dictionary else {}


func _required_flag(idx: int) -> String:
	var objs: Array = _quest().get("objectives", [])
	if idx >= objs.size():
		return ""
	return str((objs[idx] as Dictionary).get("required_flag", ""))


func test_the_quest_still_has_the_shape_this_file_assumes() -> void:
	var objs: Array = _quest().get("objectives", [])
	assert_eq(objs.size(), 4, "CONTROL: the quest is talk/custom/custom/talk; found %d objectives" % objs.size())
	assert_eq(str((objs[DIALOGUE_OBJ] as Dictionary).get("type", "")), "custom", "objective %d must be custom" % DIALOGUE_OBJ)
	assert_eq(str((objs[EXAMINE_OBJ] as Dictionary).get("type", "")), "custom", "objective %d must be custom" % EXAMINE_OBJ)
	assert_ne(_required_flag(DIALOGUE_OBJ), "", "CONTROL: objective %d must name a required_flag" % DIALOGUE_OBJ)


func test_the_compression_puzzle_has_a_dialogue_emitter() -> void:
	var want := _required_flag(DIALOGUE_OBJ)
	var src := _read(QUEST_SYSTEM)
	assert_true(src.contains("\"union_rep_w4\""),
		"QuestSystem.DIALOGUE_EMITTERS lost its union_rep_w4 entry. Objective %d of %s has no other emitter, so the quest stalls one step after accept. Restore the entry naming %s." % [DIALOGUE_OBJ, QUEST, want])
	assert_true(src.contains(want),
		"the union_rep_w4 emitter no longer names %s, which is what objective %d requires. Point the entry at the flag the quest reads, not at a renamed one." % [want, DIALOGUE_OBJ])


func test_the_filing_window_exists_and_is_actually_built() -> void:
	var want := _required_flag(EXAMINE_OBJ)
	var src := _read(VILLAGE)
	assert_true(src.contains("QuestExaminePoint.gd"),
		"RivetRowVillage lost its QuestExaminePoint load. Objective %d of %s needs the Form 99-Theta filing window; without it the quest stalls at step 3. Restore _setup_quest_points." % [EXAMINE_OBJ, QUEST])
	assert_true(src.contains(want),
		"the filing window no longer names %s. Point window.flag at the flag objective %d requires." % [want, EXAMINE_OBJ])
	assert_true(src.contains("\t_setup_quest_points()"),
		"_setup_quest_points is DEFINED BUT NEVER CALLED — BaseVillage's sequence is fixed (buildings/treasures/npcs) and has no quest-point hook, so the call must stay at the end of RivetRowVillage._setup_npcs. A defined-and-uncalled builder is the exact shape this file exists to catch.")
	var defined := src.find("func _setup_quest_points")
	var called := src.find("\t_setup_quest_points()")
	assert_true(called > -1 and defined > -1 and called < defined,
		"the call to _setup_quest_points must run inside _setup_npcs (before _validate_placements relocates anything), not after its own definition")


func test_the_two_flags_are_different_and_both_reach_an_emitter() -> void:
	var a := _required_flag(DIALOGUE_OBJ)
	var b := _required_flag(EXAMINE_OBJ)
	assert_ne(a, b, "the two custom objectives must require DIFFERENT flags, or one emitter satisfies both and the quest skips a step")
	assert_true(_read(QUEST_SYSTEM).contains(a), "objective %d flag %s must reach the dialogue emitter" % [DIALOGUE_OBJ, a])
	assert_true(_read(VILLAGE).contains(b), "objective %d flag %s must reach the filing window" % [EXAMINE_OBJ, b])
