extends GutTest

## Regression test for the story cutscene completion flag bug
## (2026-05-20).
##
## Bug: GameLoop._play_story_cutscene played the cutscene but never set
## any completion flag. So _get_pending_story_cutscene's check pattern
## (`talked_to_theron AND not chapter1_complete`) stayed true forever,
## and the Elder Theron cutscene replayed on every map re-entry. Quest
## log also stayed showing "talk to Elder Theron" because it reads the
## same flag.
##
## Fix: added _CUTSCENE_COMPLETION_FLAGS const mapping cutscene_id →
## flag name. _play_story_cutscene now sets the flag when the cutscene
## finishes, breaking the loop.
##
## Tested structurally because instantiating CutsceneDirector + running
## a real cutscene end-to-end is fragile under GUT.


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_play_story_cutscene_sets_completion_flag() -> void:
	"""GameLoop._play_story_cutscene must set the completion flag when
	the cutscene finishes. Without this, the trigger condition stays
	true and the cutscene loops every time the player re-enters the
	triggering area."""
	var text = _read("res://src/GameLoop.gd")
	var idx = text.find("func _play_story_cutscene")
	assert_gt(idx, -1, "_play_story_cutscene must exist")
	var next_func = text.find("\nfunc ", idx + 1)
	if next_func == -1:
		next_func = text.length()
	var body = text.substr(idx, next_func - idx)
	# Must reference the completion-flag map AND set a flag in game_constants.
	assert_true(body.find("_CUTSCENE_COMPLETION_FLAGS") != -1,
		"_play_story_cutscene must reference _CUTSCENE_COMPLETION_FLAGS (regression: flag-set logic missing, cutscene loops)")
	assert_true(body.find("GameState.game_constants[") != -1,
		"_play_story_cutscene must write to GameState.game_constants on completion")


func test_completion_flag_map_covers_world1_critical_cutscenes() -> void:
	"""The W1 cutscenes that trigger via story flags (prologue, chapter1,
	chapter3, chapter4) MUST have entries in the completion-flag map.
	If chapter1 is removed, Elder Theron's loop bug reappears."""
	var text = _read("res://src/GameLoop.gd")
	# Find the const map definition
	var map_idx = text.find("_CUTSCENE_COMPLETION_FLAGS")
	assert_gt(map_idx, -1, "_CUTSCENE_COMPLETION_FLAGS const must exist")
	# Body between the const decl and the next "}" close
	var close_idx = text.find("}", map_idx)
	var map_body = text.substr(map_idx, close_idx - map_idx)
	# Each W1 cutscene id must have an entry mapping to its flag.
	for pair in [
		["world1_prologue",  "cutscene_flag_prologue_complete"],
		["world1_chapter1",  "cutscene_flag_chapter1_complete"],
		["world1_chapter3",  "cutscene_flag_chapter3_complete"],
		["world1_chapter4",  "cutscene_flag_chapter4_complete"],
	]:
		var cutscene_id = pair[0]
		var flag_name = pair[1]
		assert_true(map_body.find(cutscene_id) != -1,
			"completion map must include '%s' (regression: Elder Theron loop class)" % cutscene_id)
		assert_true(map_body.find(flag_name) != -1,
			"completion map must declare flag '%s'" % flag_name)


func test_get_pending_story_cutscene_still_checks_chapter1_flag() -> void:
	"""Sanity guard: the trigger that the fix breaks must still exist.
	If the trigger gets removed or restructured, this test fails to
	remind us to re-verify the completion-flag wiring."""
	var text = _read("res://src/GameLoop.gd")
	var idx = text.find("func _get_pending_story_cutscene")
	assert_gt(idx, -1, "_get_pending_story_cutscene must exist")
	var next_func = text.find("\nfunc ", idx + 1)
	if next_func == -1:
		next_func = text.length()
	var body = text.substr(idx, next_func - idx)
	# Confirm the chapter1 trigger pair (talked_to_theron + chapter1_complete)
	# is intact — those are the conditions the bug ran through.
	assert_true(body.find("talked_to_theron") != -1,
		"chapter1 trigger must still check talked_to_theron")
	assert_true(body.find("cutscene_flag_chapter1_complete") != -1,
		"chapter1 trigger must still check cutscene_flag_chapter1_complete")
