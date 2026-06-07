extends GutTest

## Regression: cutscene completion must mirror its flag into story_flags
## under the bare name so QuestLog (which reads via get_story_flag → the
## story_flags dict) sees the matching chapter objective as complete.
##
## Pre-fix (2026-06-04): GameLoop._play_story_cutscene wrote
## `game_constants["cutscene_flag_prologue_complete"] = true` on
## prologue end, but QuestLog declares its objective gated on
## `prologue_complete` (no prefix) and reads from `story_flags`.
## Two different dicts, different keys → no objective ever turned
## green. User reported: "spoke w/ elder theron but story did not
## advance — 'Speak with' is yellow, not green checked."
##
## Source-pin test (cheap, fast). Doesn't run a cutscene end-to-end
## because that needs the full autoload+UI graph; instead reads the
## source and asserts the mirror block is in place.


const GAMELOOP_PATH := "res://src/GameLoop.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_cutscene_completion_mirrors_to_story_flags() -> void:
	# Pin: the cutscene_finished handler must strip the cutscene_flag_
	# prefix and call GameState.set_story_flag(bare) so the QuestLog can
	# see the chapter-complete bit.
	var text = _read(GAMELOOP_PATH)
	# The block lives inside the cutscene_finished lambda right after the
	# game_constants write. Search anywhere in the file for the pattern.
	assert_true(text.find("completion_flag.begins_with(\"cutscene_flag_\")") > -1,
		"completion handler must check for the cutscene_flag_ prefix to derive the bare story flag")
	assert_true(text.find("completion_flag.substr(\"cutscene_flag_\".length())") > -1,
		"completion handler must strip the cutscene_flag_ prefix to derive the bare flag")
	assert_true(text.find("GameState.set_story_flag(bare)") > -1,
		"completion handler must call GameState.set_story_flag(bare) so QuestLog sees the objective complete")
