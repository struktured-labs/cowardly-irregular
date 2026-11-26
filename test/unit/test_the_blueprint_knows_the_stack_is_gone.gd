extends GutTest

## 2026-11-26 (cowir-story): world5_long_way_around's _wiring_notes want the attendant to file the blueprint elsewhere when
## world5_termination_condition already resolved the overflow. Its scene (world5_orrery) now branches on that quest's step-3
## flag. A cutscene flag branch read only game_constants["cutscene_flag_<flag>"], so no quest flag (story_flags) could ever
## steer one: the branch now reads every namespace through GameState.is_story_flag_set.

const SCENE := "res://data/cutscenes/world5_orrery.json"
const QUEST := "res://data/quests/world5_termination_condition.json"
const FLAG := "quest_world5_termination_condition_signal_sent"

var _saved_constants: Dictionary = {}
var _saved_story: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)
	_saved_story = GameState.story_flags.duplicate(true)
	GameState.game_constants = GameState.DEFAULT_GAME_CONSTANTS.duplicate(true)
	GameState.story_flags = {}


func after_each() -> void:
	GameState.game_constants = _saved_constants
	GameState.story_flags = _saved_story


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _branch() -> Dictionary:
	for s in _json(SCENE).get("steps", []):
		if s is Dictionary and str(s.get("type", "")) == "branch" and str(s.get("flag", "")) == FLAG:
			return s
	return {}


func _says(steps: Array, needle: String) -> bool:
	for s in steps:
		for l in (s as Dictionary).get("lines", []):
			if str((l as Dictionary).get("text", "")).contains(needle):
				return true
	return false


func test_the_scene_branches_on_a_flag_the_quest_really_writes() -> void:
	var written := false
	for o in _json(QUEST).get("objectives", []):
		if str((o as Dictionary).get("flag_on_complete", "")) == FLAG:
			written = true
	assert_true(written, "CONTROL: %s is the termination quest's own step flag" % FLAG)
	var b := _branch()
	assert_false(b.is_empty(), "world5_orrery branches on whether the overflow was resolved")
	assert_true(_says(b.get("if_false", []), "behind the stack overflow"), "unresolved: filed behind the overflow, as authored")
	assert_true(_says(b.get("if_true", []), "seventeen processes used to shelter"), "resolved: filed in their vacated shelter")


func test_a_flag_branch_sees_a_quest_flag() -> void:
	assert_false(CutsceneDirector.branch_flag_is_set(FLAG), "CONTROL: unset reads false")
	GameState.set_story_flag(FLAG)
	assert_true(CutsceneDirector.branch_flag_is_set(FLAG), "a story flag (where QuestSystem writes) steers a branch")


func test_a_cutscene_flag_still_steers_its_branch() -> void:
	## The six theron_spar_* branches are written as cutscene_flag_* by the choice step; that path must not move.
	assert_false(CutsceneDirector.branch_flag_is_set("theron_spar_pick_bard"), "CONTROL: unset reads false")
	GameState.game_constants["cutscene_flag_theron_spar_pick_bard"] = true
	assert_true(CutsceneDirector.branch_flag_is_set("theron_spar_pick_bard"), "a cutscene_flag_ still reads true")


## The real branch step, with only the sub-step runner recorded, so the arm measures which line the scene actually plays (main 27923).
class RecordingDirector extends "res://src/cutscene/CutsceneDirector.gd":
	var played: Array = []

	func _execute_step(step: Dictionary) -> void:
		played.append(step)


func _played_by_the_branch() -> Array:
	var d := RecordingDirector.new()
	autofree(d)
	await d._step_branch(_branch())
	return d.played


func test_the_scene_plays_the_line_its_flag_picks() -> void:
	assert_false(_branch().is_empty(), "CONTROL: the branch step was found")
	var before: Array = await _played_by_the_branch()
	assert_true(_says(before, "behind the stack overflow"), "CONTROL: overflow unresolved, the authored line plays")
	GameState.set_story_flag(FLAG)
	var after: Array = await _played_by_the_branch()
	assert_true(_says(after, "seventeen processes used to shelter"), "overflow resolved: the scene plays the vacated-shelter line")
	assert_false(_says(after, "behind the stack overflow"), "and not the old filing line")
