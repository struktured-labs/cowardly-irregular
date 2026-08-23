extends GutTest

## classify_event is the shared dispatch for AutogrindMonitor AND AutogrindDashboard — one
## table, two panels, and no test named it. A wrong arm here silently changes what the pause
## and tier-cycle keys do in BOTH panels at once.
## The shoulder-button tier_cycle arm is deliberately NOT covered: it reads live hardware via
## Input.is_joy_button_pressed, and faking that leaks Input state across the suite.

func _key(code: int, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = pressed
	return e


func _pad(button: int, pressed: bool = true) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	return e


func test_keyboard_shortcuts_map_to_their_actions() -> void:
	assert_eq(AutogrindInputHelper.classify_event(_key(KEY_P)), "pause", "P must pause")
	assert_eq(AutogrindInputHelper.classify_event(_key(KEY_R)), "adjust_rules", "R must open rules")
	assert_eq(AutogrindInputHelper.classify_event(_key(KEY_T)), "tier_cycle", "T must cycle tier")


func test_an_unmapped_key_classifies_as_nothing() -> void:
	# ARM+. Without this, a function returning a constant would satisfy every test above.
	assert_eq(AutogrindInputHelper.classify_event(_key(KEY_Q)), "",
		"an unmapped key must classify as no action, not fall through to one")


func test_a_key_RELEASE_is_not_an_action() -> void:
	# The `and event.pressed` guard: releasing P must not re-trigger pause.
	assert_eq(AutogrindInputHelper.classify_event(_key(KEY_P, false)), "",
		"a key release must not classify as an action")


func test_joypad_face_buttons_map_to_their_actions() -> void:
	assert_eq(AutogrindInputHelper.classify_event(_pad(JOY_BUTTON_BACK)), "pause",
		"Select/Back must pause")
	assert_eq(AutogrindInputHelper.classify_event(_pad(JOY_BUTTON_START)), "adjust_rules",
		"Start must open the rule editor")


func test_an_unmapped_pad_button_classifies_as_nothing() -> void:
	assert_eq(AutogrindInputHelper.classify_event(_pad(JOY_BUTTON_A)), "",
		"an unmapped pad button must classify as no action")


func test_a_pad_RELEASE_is_not_an_action() -> void:
	assert_eq(AutogrindInputHelper.classify_event(_pad(JOY_BUTTON_BACK, false)), "",
		"a pad button release must not classify as an action")


func test_escape_classifies_as_exit() -> void:
	## ui_cancel is mapped to Escape by Godot default; this is the real runtime path.
	assert_eq(AutogrindInputHelper.classify_event(_key(KEY_ESCAPE)), "exit",
		"Escape must classify as exit")


func test_an_action_event_does_not_crash_the_classifier() -> void:
	## PROBE: the ui_cancel arm calls event.is_echo(), which InputEventKey defines and
	## InputEventAction does NOT. If that arm is reachable with a non-key event it aborts.
	var e := InputEventAction.new()
	e.action = "ui_cancel"
	e.pressed = true
	var r: String = AutogrindInputHelper.classify_event(e)
	assert_eq(r, "exit",
		"an action-typed ui_cancel must classify as exit — is_echo() resolves on it, measured")
