extends GutTest

## Regression: BDFFHD-style active-PC step-out tween fires on
## selection_turn_started and reverses on selection_turn_ended.
##
## Per cowir-battle's design lock 2026-06-04: the active PC's sprite
## slides toward the enemies (-X offset, since the party is anchored on
## the right) at the start of their selection turn, and slides back into
## formation when the turn ends. Gives the player an unmistakable
## who's-up cue without needing a portrait highlight or arrow.
##
## Source-pin test (cheap). Doesn't instantiate BattleScene because that
## requires the full autoload graph; instead reads the source and
## asserts the step-out plumbing is in place.


const BATTLE_SCENE_PATH := "res://src/battle/BattleScene.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_step_out_constants_present() -> void:
	var text = _read(BATTLE_SCENE_PATH)
	assert_true(text.find("ACTIVE_PC_STEP_OUT_OFFSET") > -1,
		"BattleScene must declare ACTIVE_PC_STEP_OUT_OFFSET so the step-out distance is tunable")
	# Offset must be negative — party is anchored on the right, enemies are
	# on the left, so toward-enemies = -X.
	var idx = text.find("ACTIVE_PC_STEP_OUT_OFFSET: float =")
	assert_gt(idx, -1, "ACTIVE_PC_STEP_OUT_OFFSET constant declaration must exist")
	var line_end = text.find("\n", idx)
	var line = text.substr(idx, line_end - idx)
	assert_true(line.find("-") > -1,
		"ACTIVE_PC_STEP_OUT_OFFSET must be negative (party anchored right, enemies left); got: %s" % line)


func test_step_active_pc_helper_exists() -> void:
	var text = _read(BATTLE_SCENE_PATH)
	assert_true(text.find("func _step_active_pc(") > -1,
		"BattleScene must expose _step_active_pc helper")


func test_turn_start_calls_step_out_for_player() -> void:
	# _on_selection_turn_started must call _step_active_pc(combatant, true)
	# only when is_player is true — enemies don't get the step-out treatment.
	var text = _read(BATTLE_SCENE_PATH)
	var fn_idx = text.find("func _on_selection_turn_started")
	assert_gt(fn_idx, -1, "_on_selection_turn_started must exist")
	var fn_end = text.find("\n\nfunc ", fn_idx + 1)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx)
	assert_true(body.find("_step_active_pc(combatant, true)") > -1,
		"_on_selection_turn_started must call _step_active_pc(combatant, true) so the player PC slides out")


func test_turn_end_calls_step_in_to_return_to_formation() -> void:
	var text = _read(BATTLE_SCENE_PATH)
	var fn_idx = text.find("func _on_selection_turn_ended")
	assert_gt(fn_idx, -1, "_on_selection_turn_ended must exist")
	var fn_end = text.find("\n\nfunc ", fn_idx + 1)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx)
	assert_true(body.find("_step_active_pc(combatant, false)") > -1,
		"_on_selection_turn_ended must call _step_active_pc(combatant, false) so the PC returns to formation")
