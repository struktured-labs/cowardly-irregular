extends GutTest

## A left-stick nudge moved the story-choice cursor ~5 rows. ui_up/ui_down share the stick's Y axis
## and an axis carries no echo flag, so every step of the ramp read as pressed — and
## DialogueChoiceMenu had no echo guard at all, not even the one that grants nothing here.
##
## world6_orrery offers FOUR options, the menu SWALLOWS B (cancellable = false, so a story choice
## cannot be backed out of), and one confirm writes a flag the scene continues from. So an overshoot
## is not recoverable by looking, the way a paging list's is: the player can only confirm something
## they did not aim at. cowir-sfx measured the audio half — play_ui("menu_move") is suppressed for a
## repeat of the same key inside 80 ms, so the cue reports FEWER moves than happened and agrees with
## the wrong mental model.
##
## Both menus now route their nav through MenuNav (cowir-controller's shared latch, .367) rather than
## a thirteenth private one: _axis_held / _shoulder_held / _value_stick_latched were already three
## names for one idea.
##
## THE WHEEL ARM IS THE LOAD-BEARING ONE cowir-controller asked for on the way in: DialogueChoiceMenu
## is the first consumer that navigates on the mouse wheel, and a wheel event has no held state to
## poll. It is safe because ui_up/ui_down bind no mouse button — probed in a live InputMap, not read
## from project.godot, because these are engine-DEFAULT actions whose bindings never appear there.

const MenuScript = preload("res://src/llm/DialogueChoiceMenu.gd")
const RAMP := [0.55, 0.7, 0.85, 0.95, 1.0]

var _menu: Node = null


func _motion(axis: int, v: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = v
	return ev


func _wheel(up: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	return ev


func _key(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


## Cleared through the public path, so this file runs against a build without the latch too.
func _clear() -> void:
	for a in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		Input.action_release(a)
	MenuNav.step(_motion(JOY_AXIS_LEFT_Y, 0.0))
	MenuNav.step(_motion(JOY_AXIS_LEFT_X, 0.0))


func before_each() -> void:
	_clear()
	_menu = MenuScript.new()
	add_child_autofree(_menu)


func after_each() -> void:
	_clear()


func _present(options: Array) -> void:
	var runner := func() -> void:
		await _menu.present(options)
	runner.call()


func test_one_stick_push_moves_the_choice_cursor_once() -> void:
	_present(["I don't know.", "Wherever they went.", "Maybe they went to rest.", "...I'm sorry."])
	assert_eq(_menu._selection, 0, "control: a fresh menu starts on the first option")
	# HELD for real: MenuNav's self-heal polls Input.is_action_pressed, so without this the latch
	# clears between synthetic events and the ramp steps five times against a CORRECT menu.
	Input.action_press("ui_down")
	var stepped := 0
	for v in RAMP:
		var before: int = _menu._selection
		_menu._input(_motion(JOY_AXIS_LEFT_Y, v))
		if _menu._selection != before:
			stepped += 1
	assert_eq(stepped, 1, "a four-option story choice must move ONE row per stick push, not %d" % stepped)
	assert_eq(_menu._selection, 1, "and it must be the next option, not a row several down")


func test_the_ramp_arm_can_see_a_burst() -> void:
	# ARM+: without this the arm above would pass on a menu that ignores the stick entirely.
	var seen := 0
	for v in RAMP:
		if _motion(JOY_AXIS_LEFT_Y, v).is_action_pressed("ui_down"):
			seen += 1
	assert_gt(seen, 1, "control: the ramp really does read as several presses (%d) — that is the defect" % seen)


func test_a_dpad_press_still_steps_every_time() -> void:
	# Buttons are not latched: a d-pad emits exactly one pressed event, and latching them would let
	# a stale latch swallow a real press.
	_present(["a", "b", "c", "d"])
	for i in 3:
		var before: int = _menu._selection
		_menu._input(_key("ui_down"))
		assert_ne(_menu._selection, before, "d-pad press %d must step" % (i + 1))


func test_the_wheel_bypasses_the_latch_entirely() -> void:
	# The arm cowir-controller asked for: this is the first MenuNav consumer with a wheel path.
	_present(["a", "b", "c", "d"])
	assert_eq(MenuNav.step(_wheel(false)), "", "a wheel event names no direction to MenuNav")
	# A latched vertical must NOT suppress the wheel.
	Input.action_press("ui_down")
	assert_eq(MenuNav.step(_motion(JOY_AXIS_LEFT_Y, 0.9)), "ui_down", "precondition: the stick latched")
	var before: int = _menu._selection
	_menu._input(_wheel(false))
	assert_ne(_menu._selection, before, "the wheel still navigates while the stick latch is set")
	var mid: int = _menu._selection
	_menu._input(_wheel(true))
	assert_ne(_menu._selection, mid, "and both wheel directions do")


func test_the_gallery_cursor_steps_once_and_keeps_its_place() -> void:
	# CutsceneGallery restores _selected_item_idx across opens, which cowir-controller flagged as
	# exercised for zero menus: the latch and a restored cursor are independent, unmeasured together.
	var gallery := CutsceneGallery.new()
	add_child_autofree(gallery)
	gallery._items_by_world = {1: [
		{"id": "a", "title": "a", "unlocked": true}, {"id": "b", "title": "b", "unlocked": true},
		{"id": "c", "title": "c", "unlocked": true}, {"id": "d", "title": "d", "unlocked": true},
	]}
	gallery._world_order = [1]
	gallery._selected_world_idx = 0
	gallery._selected_item_idx = 2  # a restored cursor, not a fresh one
	Input.action_press("ui_down")
	var stepped := 0
	for v in RAMP:
		var before: int = gallery._selected_item_idx
		gallery._input(_motion(JOY_AXIS_LEFT_Y, v))
		if gallery._selected_item_idx != before:
			stepped += 1
	assert_eq(stepped, 1, "the gallery must step once per push from a RESTORED cursor too (%d)" % stepped)
	assert_eq(gallery._selected_item_idx, 3, "and from index 2 that is index 3")
