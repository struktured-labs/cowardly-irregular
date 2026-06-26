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
##
## Ported from commit 03983fe (test_cutscene_completion_story_flag_mirror).


const GAMELOOP_PATH := "res://src/GameLoop.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_cutscene_completion_mirrors_to_story_flags() -> void:
	# Tick 220 extracted the prefix-strip + set_story_flag mirror into
	# the shared _set_cutscene_flag_and_mirror helper. The original
	# invariant (cutscene_finished → set_story_flag for cutscene_flag_*)
	# still holds — pinned via the helper now.
	var text = _read(GAMELOOP_PATH)
	# Pin the helper exists with the right shape (the original mirror
	# semantics moved inside it).
	assert_true(text.find("flag.begins_with(\"cutscene_flag_\")") > -1,
		"_set_cutscene_flag_and_mirror must check the cutscene_flag_ prefix")
	assert_true(text.find("flag.substr(\"cutscene_flag_\".length())") > -1,
		"_set_cutscene_flag_and_mirror must strip the cutscene_flag_ prefix")
	assert_true(text.find("GameState.set_story_flag(bare)") > -1,
		"_set_cutscene_flag_and_mirror must call set_story_flag so QuestLog sees the objective complete")
	# Pin the cutscene_finished handler routes through the helper.
	assert_true(text.find("_set_cutscene_flag_and_mirror(completion_flag)") > -1,
		"cutscene_finished handler must route completion_flag through _set_cutscene_flag_and_mirror")
