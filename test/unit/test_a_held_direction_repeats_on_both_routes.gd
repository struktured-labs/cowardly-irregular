extends GutTest

## Holding a direction must repeat, and a STICK hold must behave exactly like a D-PAD hold.
##
## 🔑 WHY THIS COULD NOT BE WRITTEN UNTIL NOW. MenuRepeat is POLLED — it asks
## `Input.is_action_pressed()` rather than reading events — and every existing arm drives it with
## `Input.action_press()`, which sets the action state directly and never exercises the axis
## binding. So the analog-held path, which is the actual pad case, was untested.
## `Input.parse_input_event()` updates the live axis state the poll reads, which makes it testable:
##
##     centred        is_action_pressed(ui_down) = false   strength 0.00
##     stick at 0.9   is_action_pressed(ui_down) = true    strength 0.80
##
## That matters because MenuNav LATCHES the stick to one step per push while MenuRepeat POLLS for
## the hold. Those two have to compose — one step, then a ramp — and my own conversions landed in
## these menus when only the d-pad half could be checked.
##
## ⛔ COUNT TRANSITIONS, NOT THE FINAL POSITION. VirtualKeyboard's grid is 4 rows, so seven repeats
## land back where three would: my first probe read "hold = 0" and I nearly filed a dead repeat.
## A wrapping cursor makes N steps indistinguishable from none — the same ambiguity that hid the
## GameOverScreen toggle from an odd-length ramp, in the instrument instead of the subject.

const HOLD_SECONDS := 1.2
const FRAME := 1.0 / 60.0

## Menus carrying BOTH MenuNav (the latch) and MenuRepeat (the poll). EquipmentMenu, Win98Menu and
## OverworldMenu also carry both and are NOT here: their handlers early-return on state this
## fixture does not build, so they are uncovered rather than clean — the distinction that turned
## out to matter for HowToPlayOverlay, which I filed unmeasured and which had a real defect.
const MENUS := [
	{"name": "SettingsMenu", "path": "res://src/ui/SettingsMenu.gd", "cursor": "selected_index"},
	{"name": "VirtualKeyboard", "path": "res://src/ui/VirtualKeyboard.gd", "cursor": "cursor_row"},
]


func after_each() -> void:
	_centre()


func _motion(v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = JOY_AXIS_LEFT_Y
	e.axis_value = v
	return e


func _centre() -> void:
	for a in ["ui_down", "ui_up"]:
		Input.action_release(a)
	Input.parse_input_event(_motion(0.0))
	MenuNav.step(_motion(0.0))


func _open(spec: Dictionary) -> Node:
	_centre()
	await get_tree().process_frame
	var m: Node = load(spec["path"]).new()
	add_child_autofree(m)
	await get_tree().process_frame
	if m is CanvasItem:
		(m as CanvasItem).visible = true
	m.set(spec["cursor"], 0)
	return m


## Steps counted as TRANSITIONS of the cursor, so a wrap cannot read as stillness.
func _hold(m: Node, cursor: String) -> int:
	var last: int = int(m.get(cursor))
	var steps := 0
	var t := 0.0
	while t < HOLD_SECONDS:
		m.call("_process", FRAME)
		var now: int = int(m.get(cursor))
		if now != last:
			steps += 1
			last = now
		t += FRAME
	return steps


func test_a_held_stick_repeats_exactly_as_a_held_dpad_does() -> void:
	var checked := 0
	for spec in MENUS:
		# D-PAD: one press event, then hold the action
		var d: Node = await _open(spec)
		var b := InputEventJoypadButton.new()
		b.button_index = JOY_BUTTON_DPAD_DOWN
		b.pressed = true
		Input.action_press("ui_down", 1.0)
		d.call("_input", b)
		var d_push: int = int(d.get(spec["cursor"]))
		var d_repeats: int = _hold(d, spec["cursor"])
		Input.action_release("ui_down")
		_centre()

		assert_ne(d_push, 0,
			"LIVENESS: %s did not step on a d-pad press — its handler early-returned, and the "
			% spec["name"] + "comparison below would be between two dead runs")
		assert_gt(d_repeats, 1,
			"%s did not REPEAT on a held d-pad: %d transitions in %.1fs. MenuRepeat polls "
			% [spec["name"], d_repeats, HOLD_SECONDS] + "Input.is_action_pressed and should ramp")

		# STICK: push past the deadzone, deliver the ramp, then hold steady
		var s: Node = await _open(spec)
		Input.parse_input_event(_motion(0.9))
		await get_tree().process_frame
		for v in [0.55, 0.75, 0.9]:
			s.call("_input", _motion(v))
		var s_push: int = int(s.get(spec["cursor"]))
		var s_repeats: int = _hold(s, spec["cursor"])
		_centre()

		assert_eq(s_push, d_push,
			"%s: one stick push moved the cursor to %d, one d-pad press to %d — the latch should "
			% [spec["name"], s_push, d_push] + "make a push worth exactly one press")
		assert_eq(s_repeats, d_repeats,
			"%s: a held STICK repeated %d times, a held d-pad %d. MenuRepeat polls the action, so "
			% [spec["name"], s_repeats, d_repeats] + "an axis held past the deadzone must ramp identically")
		checked += 1
	assert_eq(checked, MENUS.size(),
		"every listed menu must reach the comparison; %d of %d did" % [checked, MENUS.size()])


## CONTROL for the instrument: the live axis state must actually reach the poll MenuRepeat makes,
## or both sides of every comparison above are measuring a released stick.
func test_control_a_held_stick_reads_as_a_pressed_action() -> void:
	_centre()
	await get_tree().process_frame
	assert_false(Input.is_action_pressed("ui_down"), "centred, the action must be released")
	Input.parse_input_event(_motion(0.9))
	await get_tree().process_frame
	assert_true(Input.is_action_pressed("ui_down"),
		"a stick at 0.9 past a 0.50 deadzone must read as pressed — if this fails, "
		+ "parse_input_event no longer reaches the Input singleton and the arms above are vacuous")
	_centre()
