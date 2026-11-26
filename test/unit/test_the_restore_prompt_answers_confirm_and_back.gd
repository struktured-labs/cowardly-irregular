extends GutTest

## The grind editor's "Restore the shipped autogrind profiles?" prompt answered only the raw Enter and Escape keys and
## said so in a literal hint. The keyboard's Confirm/Back are X/Z (emulator layout), so X and Z did nothing on the one
## screen that asks a yes/no question. It now answers ui_accept / ui_cancel, keeps Enter/Esc, and derives its hint.
## Arms: CONTROL (navigation leaves the prompt up) · X restores · Z cancels · Enter still restores · a pad's Confirm
## restores · the hint names the keys that answer it.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const ED := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const PLANTED := "zz_planted_profile"

var _ed: Control = null
var _ag_state = null
var _saved_persist := false


func before_each() -> void:
	_saved_persist = AutogrindSystem._test_disable_persistence
	AutogrindSystem._test_disable_persistence = true
	_ag_state = AutogrindState.snapshot()


func after_each() -> void:
	if _ed and is_instance_valid(_ed):
		_ed.queue_free()
	_ed = null
	AutogrindState.restore(_ag_state)
	AutogrindSystem._test_disable_persistence = _saved_persist


## A fresh editor on its own viewport with the prompt open, and the active profile renamed so a restore is visible.
func _open() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	_ed = load(ED).new()
	_ed.size = Vector2(1280, 720)
	vp.add_child(_ed)
	await get_tree().process_frame
	_ed.setup([])
	await get_tree().process_frame
	var profiles: Array = AutogrindSystem.autogrind_profiles.get("profiles", [])
	var active: int = int(AutogrindSystem.autogrind_profiles.get("active", 0))
	assert_lt(active, profiles.size(), "PRECONDITION: there is an active profile to rename")
	profiles[active]["name"] = PLANTED
	assert_eq(AutogrindSystem.get_active_autogrind_profile_name(), PLANTED, "CONTROL: the plant is what the system reads")
	_ed._show_reset_confirmation()
	assert_not_null(_ed._reset_confirm, "PRECONDITION: the prompt is open")


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _pad(button: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	return e


func _restored() -> bool:
	return AutogrindSystem.get_active_autogrind_profile_name() != PLANTED


func test_navigation_leaves_the_prompt_up() -> void:
	await _open()
	var down := InputEventAction.new()
	down.action = "ui_down"
	down.pressed = true
	_ed._input(down)
	assert_not_null(_ed._reset_confirm, "CONTROL: a press that is neither Confirm nor Back leaves the question asked")
	assert_false(_restored(), "CONTROL: and restores nothing")


func test_keyboard_confirm_restores() -> void:
	await _open()
	assert_true(_key(KEY_X).is_action("ui_accept"), "CONTROL: X is the keyboard's Confirm")
	_ed._input(_key(KEY_X))
	assert_true(_restored(), "X (Confirm) did not restore the shipped profiles")
	assert_null(_ed._reset_confirm, "and the prompt closes")


func test_keyboard_back_cancels() -> void:
	await _open()
	assert_true(_key(KEY_Z).is_action("ui_cancel"), "CONTROL: Z is the keyboard's Back")
	_ed._input(_key(KEY_Z))
	assert_null(_ed._reset_confirm, "Z (Back) did not close the prompt")
	assert_false(_restored(), "and Back must restore nothing")


func test_enter_still_restores() -> void:
	await _open()
	_ed._input(_key(KEY_ENTER))
	assert_true(_restored(), "Enter stopped restoring")
	assert_null(_ed._reset_confirm, "and the prompt closes")


func test_a_pad_confirm_restores() -> void:
	await _open()
	assert_true(_pad(JOY_BUTTON_B).is_action("ui_accept"), "CONTROL: the east face is the pad's Confirm")
	_ed._input(_pad(JOY_BUTTON_B))
	assert_true(_restored(), "the pad's Confirm did not restore the shipped profiles")


func test_the_hint_names_the_keys_that_answer_it() -> void:
	await _open()
	var hint := ""
	for ch in _ed._reset_confirm.get_children():
		if ch is Label and (ch as Label).text.contains(": restore"):
			hint = (ch as Label).text
	assert_ne(hint, "", "PRECONDITION: the prompt has its hint")
	var ok: String = InputProfileManager.hint_for_action("ui_accept")
	var back: String = InputProfileManager.hint_for_action("ui_cancel")
	assert_ne(ok, "", "CONTROL: Confirm has a name on this device")
	assert_true(hint.contains("%s: restore" % ok), "the hint must name Confirm (%s): %s" % [ok, hint])
	assert_true(hint.contains("%s: cancel" % back), "the hint must name Back (%s): %s" % [back, hint])
