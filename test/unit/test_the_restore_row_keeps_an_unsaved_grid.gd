extends GutTest

## The console's "Restore Shipped Profiles" row (.837) opened the rules editor without saving the console's grid. The
## editor reads the SAVED profile, and on close the console adopts whatever is saved, so answering the restore prompt
## with Back silently erased every unsaved edit made in the console. The row now saves the grid first; a grid the
## validator refuses keeps the editor shut and stays on screen.
## Arms: Back keeps the unsaved grid, on screen and in its profile · Confirm still restores · a refused grid opens nothing.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const UI := "res://src/ui/autogrind/AutogrindUI.gd"
const PLANTED_RULE := {"enabled": true, "conditions": [{"type": "battles_done", "op": ">=", "value": 7}], "actions": [{"type": "stop_grinding"}]}

var _ag: Dictionary
var _vp: SubViewport
var _ui: Control


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ui = load(UI).new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(_ui)
	await get_tree().process_frame
	_ui._is_grinding = false


func after_each() -> void:
	var ed = _ui._rules_editor_open if _ui and is_instance_valid(_ui) else null
	if ed and is_instance_valid(ed):
		ed.queue_free()
	if _ui and is_instance_valid(_ui):
		_ui.queue_free()
	AutogrindState.restore(_ag)


func _pad(button: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	return e


## Plants an unsaved grid, chooses the row, and returns the editor it opened (null if none).
func _choose_row_over(grid: Array) -> Control:
	_ui.rules = grid.duplicate(true)
	assert_ne(AutogrindSystem.get_autogrind_rules(), _ui.rules, "CONTROL: the console's grid is not yet saved")
	_ui._commit_autogrind_option("restore_defaults")
	return _ui._rules_editor_open


func test_back_keeps_the_unsaved_grid() -> void:
	var ed := _choose_row_over([PLANTED_RULE])
	assert_not_null(ed, "PRECONDITION: the row opened the rules editor")
	if ed == null:
		return
	ed._input(_pad(JOY_BUTTON_A))
	assert_null(ed._reset_confirm, "PRECONDITION: Back closed the prompt")
	ed.closed.emit()
	assert_eq(_ui.rules, [PLANTED_RULE], "answering the restore prompt with Back erased the console's unsaved grid")
	assert_eq(AutogrindSystem.get_autogrind_rules(), [PLANTED_RULE], "and the grid is in its profile, not only on screen")


func test_confirm_still_restores() -> void:
	var ed := _choose_row_over([PLANTED_RULE])
	assert_not_null(ed, "PRECONDITION: the row opened the rules editor")
	if ed == null:
		return
	ed._input(_pad(JOY_BUTTON_B))
	ed.closed.emit()
	assert_ne(_ui.rules, [PLANTED_RULE], "Confirm must still replace the grid with the shipped rules")
	assert_eq(_ui.rules, AutogrindSystem.get_autogrind_rules(), "and the console shows what was restored")


func test_a_refused_grid_opens_nothing_and_stays() -> void:
	var junk: Array = ["not a rule"]
	var ed := _choose_row_over(junk)
	assert_null(ed, "a grid the validator refuses must not open an editor that would replace it on close")
	assert_eq(_ui.rules, junk, "and the refused grid stays on screen")
