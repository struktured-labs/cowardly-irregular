extends GutTest

## Settings → Controls → Test Buttons told the player to close with Cancel, then closed on
## raw button 0. That index is Cancel only while Nintendo mode is on. Turn the face convention
## off (Xbox / PlayStation: Confirm on the south face) or rebind Cancel, and the named button
## stays on the tester while Confirm dismisses it before its mapping can be read.

const CONTROLS_MENU := "res://src/ui/ControlsMenu.gd"
const _CFG := "user://input/controls.json"

var _cfg_existed: bool = false
var _cfg_text: String = ""
var _cfg_profile: String = ""
var _cfg_custom: Dictionary = {}
var _cfg_nintendo: bool = true
var _cfg_chosen: bool = false


func _save_input_config() -> void:
	_cfg_profile = InputProfileManager.active_profile
	_cfg_custom = InputProfileManager.custom_bindings.duplicate(true)
	_cfg_nintendo = InputProfileManager.nintendo_mode
	_cfg_chosen = InputProfileManager.profile_chosen_by_user
	_cfg_existed = FileAccess.file_exists(_CFG)
	_cfg_text = FileAccess.get_file_as_string(_CFG) if _cfg_existed else ""


func _restore_input_config() -> void:
	InputProfileManager.custom_bindings = _cfg_custom.duplicate(true)
	InputProfileManager.nintendo_mode = _cfg_nintendo
	InputProfileManager.profile_chosen_by_user = _cfg_chosen
	InputProfileManager.active_profile = _cfg_profile
	InputProfileManager.apply_profile(_cfg_profile)
	if _cfg_existed and _cfg_text != "":
		if FileAccess.get_file_as_string(_CFG) != _cfg_text:
			DirAccess.make_dir_recursive_absolute("user://input")
			var f := FileAccess.open(_CFG, FileAccess.WRITE)
			if f:
				f.store_string(_cfg_text)
				f.close()
	elif FileAccess.file_exists(_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_CFG))


func before_each() -> void:
	_save_input_config()
	InputProfileManager.nintendo_mode = true
	InputProfileManager.apply_profile("Standard")


func after_each() -> void:
	_restore_input_config()


func _menu() -> Node:
	var cm = load(CONTROLS_MENU).new()
	add_child_autofree(cm)
	return cm


func _press(cm: Node, button: int) -> void:
	cm._testing = true
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = true
	cm._handle_test_input(ev)


func _press_key(cm: Node, keycode: Key) -> void:
	cm._testing = true
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	cm._handle_test_input(ev)


func _only(action: String) -> int:
	var indices: Array = InputProfileManager.get_current_button_indices(action)
	assert_eq(indices.size(), 1, "%s must have exactly one pad button, got %s" % [action, str(indices)])
	return int(indices[0])


## Stock layout: Cancel closes, Confirm is reported and the tester stays open.
func test_stock_cancel_closes_and_confirm_stays_on_screen() -> void:
	var cancel := _only("ui_cancel")
	var accept := _only("ui_accept")
	assert_ne(cancel, accept, "precondition: Confirm and Cancel are different buttons")
	var cm := _menu()

	_press(cm, accept)
	assert_true(cm._testing, "CONTROL: Confirm must leave the tester open so its mapping can be read")
	var raw: Label = cm._test_overlay.get_node_or_null("TestBox/TestRaw")
	assert_not_null(raw, "the mapping line must exist")
	assert_string_contains(str(raw.text), "Confirm",
		"CONTROL: pressing Confirm must report that mapping, got '%s'" % str(raw.text))

	_press(cm, cancel)
	assert_false(cm._testing, "CONTROL: the stock Cancel button must close the tester")

	_press_key(cm, KEY_ESCAPE)
	assert_false(cm._testing, "CONTROL: Escape must still close the tester")
	_press_key(cm, KEY_X)
	assert_false(cm._testing, "CONTROL: X must still close the tester")


## Rebind Cancel off the south face. The tester must follow the action, not index 0.
func test_a_rebound_cancel_closes_the_tester_and_the_old_button_does_not() -> void:
	var old_cancel := _only("ui_cancel")
	var target := 3
	assert_false(InputProfileManager.get_current_button_indices("ui_accept").has(target),
		"precondition: the new Cancel button is not Confirm")
	assert_ne(target, old_cancel, "precondition: the rebind actually moves Cancel")
	InputProfileManager.set_custom_binding("ui_cancel", [target])
	assert_eq(_only("ui_cancel"), target, "the rebind must have reached the live InputMap")

	var cm := _menu()
	_press(cm, old_cancel)
	assert_true(cm._testing,
		"the button Cancel used to be on must not close the tester after a rebind")
	_press(cm, target)
	assert_false(cm._testing,
		"the button Cancel was moved to must close the tester")


## Xbox/PlayStation convention swaps the faces. South becomes Confirm and must not dismiss.
func test_face_convention_off_closes_on_cancel_not_on_confirm() -> void:
	var cancel_on := _only("ui_cancel")
	var accept_on := _only("ui_accept")
	InputProfileManager.nintendo_mode = false
	InputProfileManager.apply_profile("Standard")
	var cancel_off := _only("ui_cancel")
	var accept_off := _only("ui_accept")
	assert_eq(cancel_off, accept_on, "precondition: Cancel moved onto the old Confirm button")
	assert_eq(accept_off, cancel_on, "precondition: Confirm moved onto the old Cancel button")
	assert_ne(cancel_off, accept_off, "precondition: the two faces are still distinct")

	var cm := _menu()
	_press(cm, accept_off)
	assert_true(cm._testing,
		"with Confirm on the south face, that button must not close the tester")
	var raw: Label = cm._test_overlay.get_node_or_null("TestBox/TestRaw")
	assert_not_null(raw, "the mapping line must exist")
	assert_string_contains(str(raw.text), "Confirm",
		"the south face must be reported as Confirm, got '%s'" % str(raw.text))

	_press(cm, cancel_off)
	assert_false(cm._testing,
		"Cancel's new button must close the tester after the face convention is turned off")


## The close caption is derived from Cancel, including for a pad that is not the one headless sees.
func test_the_close_caption_names_cancel_on_the_pad_you_hold() -> void:
	InputProfileManager.nintendo_mode = false
	InputProfileManager.apply_profile("Standard")
	var cm := _menu()
	var pad := "Xbox Series Controller"
	var cancel_g: String = InputProfileManager.glyph_for_action("ui_cancel", pad)
	var accept_g: String = InputProfileManager.glyph_for_action("ui_accept", pad)
	assert_ne(cancel_g, accept_g, "precondition: the two faces print different glyphs on Xbox")
	assert_ne(cancel_g, "?", "precondition: Cancel must resolve to a real glyph")
	var hint: String = cm._test_close_hint(pad)
	assert_eq(hint, "%s / Escape to close" % cancel_g,
		"the tester must tell the player to press Cancel, not Confirm")
	cm._refresh_test_close_hint()
	var label: Label = cm._test_overlay.get_node_or_null("TestBox/TestCloseHint")
	assert_not_null(label, "the close caption must be a live label")
	assert_string_contains(str(label.text), "Escape",
		"keyboard Escape remains a way out, got '%s'" % str(label.text))
