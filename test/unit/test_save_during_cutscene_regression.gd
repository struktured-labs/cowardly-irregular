extends GutTest

## Regression: saving is BLOCKED while GameLoop.current_state ==
## LoopState.CUTSCENE. Prompted by cowir-main msg 1964 (Spotlight Duels
## spec, 2026-06-30): the cutscene now embeds a battle step via the
## new `battle` cutscene step type (tick 471), so mid-cutscene means
## mid-narration OR mid-duel — neither is a clean save point. Saving
## mid-cutscene would capture ambiguous state (intro dialogue partially
## played, battle step not entered, spotlight PC bench state
## inconsistent).
##
## Defense in depth:
##   1. SaveSystem.can_quick_save() adds an _is_cutscene_active() gate.
##      Covers ALL entry points that route through can_quick_save
##      (F2 quick save, F3 quick load, auto_save on area transition,
##      SaveSystem.save_game with the shared gate).
##   2. GameLoop._input's F2/F3 handler ALSO short-circuits when
##      current_state == LoopState.CUTSCENE — fail-fast at the input
##      layer so the toast doesn't try to flash mid-cutscene even if
##      SaveSystem's gate somehow reports permissive.

const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"
const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_can_quick_save_gates_on_cutscene_state() -> void:
	# Source pin: can_quick_save must call _is_cutscene_active. Catches
	# anyone removing the gate in a future refactor (would silently
	# re-open the mid-cutscene save class of bug).
	var text = _read(SAVE_SYSTEM_PATH)
	var fn_idx = text.find("func can_quick_save()")
	assert_true(fn_idx > -1, "can_quick_save must exist")
	# Widen window to the next `func ` — the docstring inside
	# can_quick_save contains \n\n breaks and the tighter cut misses the
	# real function body.
	var fn_end = text.find("\nfunc ", fn_idx + 1)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx, 2000)
	assert_true(body.find("_is_cutscene_active()") > -1,
		"can_quick_save must call _is_cutscene_active() so mid-cutscene saves are blocked")


func test_is_cutscene_active_helper_exists() -> void:
	var text = _read(SAVE_SYSTEM_PATH)
	assert_true(text.find("func _is_cutscene_active()") > -1,
		"SaveSystem must expose _is_cutscene_active helper")
	# Helper must query GameLoop.current_state (mirrors the shape of
	# _is_player_inside_interior which reaches into current_scene).
	var fn_idx = text.find("func _is_cutscene_active()")
	var fn_end = text.find("\n\n\nfunc ", fn_idx)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx, 1000)
	assert_true(body.find("current_state") > -1,
		"_is_cutscene_active must query GameLoop.current_state")


func test_save_block_reason_reports_cutscene() -> void:
	# The blocker-reason message must include a cutscene-specific line so
	# the surfaced toast tells the player WHY the save was refused
	# (mirrors the pattern for battle / interior blockers).
	var text = _read(SAVE_SYSTEM_PATH)
	var fn_idx = text.find("func _save_block_reason()")
	assert_true(fn_idx > -1, "_save_block_reason must exist")
	var fn_end = text.find("\n\n\nfunc ", fn_idx)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx, 1000)
	assert_true(body.find("_is_cutscene_active()") > -1,
		"_save_block_reason must include a cutscene-branch check so the reason mirrors can_quick_save")
	# Must produce a distinct message (not the generic battle/interior
	# ones) so the player knows to wait for the cutscene rather than
	# leaving a room.
	assert_true(body.find("cutscene") > -1,
		"_save_block_reason must return a cutscene-specific message when the cutscene gate fires")


func test_f2_input_handler_blocks_cutscene() -> void:
	# Source pin: the F2 quick-save keycode handler must also short-
	# circuit on LoopState.CUTSCENE. Belt to SaveSystem's suspenders.
	var text = _read(GAME_LOOP_PATH)
	var f2_idx = text.find("event.keycode == KEY_F2")
	assert_true(f2_idx > -1, "GameLoop._input must handle KEY_F2 for quick save")
	# The if-line must contain the LoopState.CUTSCENE gate.
	var line_start = text.rfind("\n", f2_idx)
	var line_end = text.find("\n", f2_idx)
	var line = text.substr(line_start, line_end - line_start)
	assert_true(line.find("LoopState.CUTSCENE") > -1,
		"F2 handler must gate on current_state != LoopState.CUTSCENE: got line: %s" % line.strip_edges())


func test_f3_input_handler_blocks_cutscene() -> void:
	# Same guard for F3 quick load — reloading a save mid-cutscene would
	# also produce inconsistent state (cutscene director is mid-execute
	# on the old save's step_index; loading a different save would
	# leave the director in a broken state).
	var text = _read(GAME_LOOP_PATH)
	var f3_idx = text.find("event.keycode == KEY_F3")
	assert_true(f3_idx > -1, "GameLoop._input must handle KEY_F3 for quick load")
	var line_start = text.rfind("\n", f3_idx)
	var line_end = text.find("\n", f3_idx)
	var line = text.substr(line_start, line_end - line_start)
	assert_true(line.find("LoopState.CUTSCENE") > -1,
		"F3 handler must gate on current_state != LoopState.CUTSCENE: got line: %s" % line.strip_edges())


func test_is_cutscene_active_defensive_on_missing_gameloop() -> void:
	# Behavioral: SaveSystem is an autoload; unit tests boot without a
	# GameLoop scene in the tree. _is_cutscene_active must return false
	# gracefully in that case (matches _is_player_inside_interior's
	# fallback shape) so tests running in isolation don't crash on a
	# missing GameLoop reference.
	if not SaveSystem:
		pending("SaveSystem autoload not available")
		return
	# In this test context there's no GameLoop scene root; the helper
	# should return false permissively.
	var result: bool = SaveSystem._is_cutscene_active()
	assert_false(result,
		"_is_cutscene_active must return false when GameLoop isn't reachable (defensive for unit tests)")
