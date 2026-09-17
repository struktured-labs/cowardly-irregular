extends GutTest

## ui_up/ui_down bind the LEFT STICK'S Y axis and ui_left/ui_right its X axis, alongside the d-pad
## buttons. An axis carries no echo flag, so a stick push emits one event per value change and every
## one reads as pressed — and the `is_action_pressed(...) and not event.is_echo()` guard every menu
## uses takes all of them.
##
## MEASURED on a six-step ramp past the 0.5 deadzone:
##     ui_down is_action_pressed  5 of 6
##     a menu's own guard          5 cursor steps on ONE nudge
##
## ⛔ THE PROJECT ALREADY LATCHES A STICK FOR THIS REASON. AutogrindGridEditor._handle_value_stick
## carries `_value_stick_latched` at a 0.6 deadzone for the RIGHT stick. The LEFT stick — the one
## every menu navigates with — had no latch anywhere.

const RAMP := [0.55, 0.7, 0.85, 0.95, 1.0]


func _motion(axis: int, v: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = v
	return ev


func _button(index: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = index
	ev.pressed = true
	return ev


## Cleared through the public path so this file runs against a build that lacks the latch.
func _clear() -> void:
	for a in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		Input.action_release(a)
	MenuNav.step(_motion(JOY_AXIS_LEFT_Y, 0.0))
	MenuNav.step(_motion(JOY_AXIS_LEFT_X, 0.0))


func before_each() -> void:
	_clear()


func after_each() -> void:
	_clear()


func _bound_button(action: String) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			return (e as InputEventJoypadButton).button_index
	return -1


## ANTI-VACUITY FIRST: if the synthetic ramp does not read as a burst, every "exactly once" assert
## below passes over nothing.
func test_the_ramp_really_reads_as_a_burst() -> void:
	var pressed := 0
	for v in RAMP:
		if _motion(JOY_AXIS_LEFT_Y, v).is_action_pressed("ui_down"):
			pressed += 1
	assert_gt(pressed, 1, "the fixture must reproduce the burst — %d of %d ramp steps read as pressed"
		% [pressed, RAMP.size()])


## ⛔ THE DEFECT.
func test_one_stick_push_steps_once() -> void:
	Input.action_press("ui_down")
	var steps := 0
	for v in RAMP:
		if MenuNav.step(_motion(JOY_AXIS_LEFT_Y, v)) != "":
			steps += 1
	assert_eq(steps, 1, "a single stick push must move the cursor once, not once per ramp value")


func test_the_horizontal_axis_is_latched_too() -> void:
	Input.action_press("ui_right")
	var steps := 0
	for v in RAMP:
		if MenuNav.step(_motion(JOY_AXIS_LEFT_X, v)) != "":
			steps += 1
	assert_eq(steps, 1, "the X axis bursts exactly as the Y axis does")


## The two axes must latch INDEPENDENTLY, or holding a direction would swallow the other one.
func test_a_held_vertical_does_not_swallow_a_horizontal_step() -> void:
	Input.action_press("ui_down")
	assert_eq(MenuNav.step(_motion(JOY_AXIS_LEFT_Y, 0.9)), "ui_down", "precondition: the vertical stepped")
	assert_eq(MenuNav.step(_motion(JOY_AXIS_LEFT_Y, 1.0)), "", "…and its ramp does not repeat")

	Input.action_press("ui_right")
	assert_eq(MenuNav.step(_motion(JOY_AXIS_LEFT_X, 0.9)), "ui_right",
		"a horizontal push must still step while the vertical is held")


## A d-pad press emits exactly one event, so it is NOT latched — latching it would let a stale
## latch swallow a real press.
func test_a_dpad_press_is_never_latched() -> void:
	var down := _bound_button("ui_down")
	assert_gt(down, -1, "precondition: ui_down must be bound to a joypad button")
	Input.action_press("ui_down")
	assert_eq(MenuNav.step(_button(down)), "ui_down", "the d-pad steps")
	assert_eq(MenuNav.step(_button(down)), "ui_down", "…and steps again, because buttons do not burst")


func test_releasing_the_stick_arms_the_next_push() -> void:
	Input.action_press("ui_down")
	assert_eq(MenuNav.step(_motion(JOY_AXIS_LEFT_Y, 0.9)), "ui_down", "first push steps")
	assert_eq(MenuNav.step(_motion(JOY_AXIS_LEFT_Y, 1.0)), "", "the ramp does not")
	Input.action_release("ui_down")
	MenuNav.step(_motion(JOY_AXIS_LEFT_Y, 0.0))
	Input.action_press("ui_down")
	assert_eq(MenuNav.step(_motion(JOY_AXIS_LEFT_Y, 0.9)), "ui_down",
		"after a genuine release the next push steps again")


## A menu closing mid-push leaves the latch set; an unrelated event arriving while nothing is held
## must clear it rather than swallowing the next menu's first step.
func test_a_stranded_latch_heals() -> void:
	Input.action_press("ui_down")
	assert_eq(MenuNav.step(_motion(JOY_AXIS_LEFT_Y, 0.9)), "ui_down", "precondition: the push stepped")
	Input.action_release("ui_down")          # released with no menu listening

	var unrelated := InputEventKey.new()
	unrelated.keycode = KEY_F7
	unrelated.pressed = true
	assert_eq(MenuNav.step(unrelated), "", "an unrelated key steps nothing")

	Input.action_press("ui_down")
	assert_eq(MenuNav.step(_motion(JOY_AXIS_LEFT_Y, 0.9)), "ui_down",
		"the next genuine push must step — a stale latch would have eaten it")
