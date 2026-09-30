extends GutTest

## Found by fuzzing the real autogrind console with pad input: Y opened the overworld menu ON TOP of the console. The console
## uses Y only for Resume and leaves the press unhandled when there is no saved session, so it reached GameLoop's overworld
## toggle, which (unlike the battle_toggle_auto and ui_menu branches beside it) never asked whether the console was open.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

var _ag: Dictionary
var _prof: Dictionary
var _prior_snapshot: Variant = null
var _gl: Node


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	_prof = ABProfiles.snapshot(AutobattleSystem)
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	if FileAccess.file_exists(AutogrindSystem.SNAPSHOT_PATH):
		_prior_snapshot = FileAccess.get_file_as_string(AutogrindSystem.SNAPSHOT_PATH)
		DirAccess.remove_absolute(AutogrindSystem.SNAPSHOT_PATH)
	_gl = load("res://src/GameLoop.gd").new()
	add_child_autofree(_gl)
	var explore := Node.new()
	add_child_autofree(explore)
	_gl._exploration_scene = explore
	_gl._current_map_id = "overworld"
	_gl.current_state = _gl.LoopState.EXPLORATION
	_gl._create_party()
	InputLockManager.pop_all()


func after_each() -> void:
	if _gl._overworld_menu and is_instance_valid(_gl._overworld_menu):
		_gl._overworld_menu.queue_free()
		_gl._overworld_menu = null
	InputLockManager.pop_all()
	if _prior_snapshot != null:
		var f := FileAccess.open(AutogrindSystem.SNAPSHOT_PATH, FileAccess.WRITE)
		f.store_string(_prior_snapshot)
		f.close()
	_prior_snapshot = null
	AutogrindState.restore(_ag)
	ABProfiles.restore(AutobattleSystem, _prof)
	SoundManager.stop_music()


func _press_y() -> void:
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_Y
	b.pressed = true
	get_viewport().push_input(b)
	var up := b.duplicate()
	up.pressed = false
	get_viewport().push_input(up)
	await wait_frames(2)


func test_y_in_the_console_does_not_open_the_overworld_menu() -> void:
	_gl._open_autogrind_ui()
	await wait_frames(3)
	assert_true(_gl._autogrind_ui_open(), "CONTROL: the console must be open")
	assert_false(AutogrindSystem.is_snapshot_loadable(), "CONTROL: nothing to resume, so the console leaves Y unhandled")
	await _press_y()
	assert_true(_gl._overworld_menu == null or not is_instance_valid(_gl._overworld_menu),
		"Y opened the overworld menu on top of the autogrind console")
	assert_true(_gl._autogrind_ui_open(), "and the console must still be the screen in front")


func test_y_on_the_map_still_opens_the_overworld_menu() -> void:
	await _press_y()
	assert_true(_gl._overworld_menu != null and is_instance_valid(_gl._overworld_menu),
		"CONTROL: with no console open, Y must still open the overworld menu, or the arm above proves nothing")
