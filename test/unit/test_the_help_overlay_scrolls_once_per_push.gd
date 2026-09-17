extends GutTest

## One stick push must scroll the help overlay exactly as far as one d-pad press.
##
## ⛔ MEASURED BEFORE THE FIX: dpad 48 px · odd ramp 240 (5 steps) · even ramp 192 (4 steps).
## ui_up/ui_down bind the stick's Y axis and an axis carries no echo flag, so the F1 reference —
## the screen a player opens BECAUSE they are lost — scrolled a fifth of a page per nudge.
##
## 🔑 THREE EARLIER PROBES OF MINE REPORTED "NOTHING MOVED" AND ALL THREE WERE WRONG, which is why
## this file reads the bar THROUGH the target on every observation:
##
##     ScrollContainer.get_v_scroll_bar() does NOT hand back a stable object.
##     Captured once at fixture time it goes stale, the overlay scrolls the live bar, and the
##     held reference reads 0 forever — a subject working perfectly behind a reader that cannot
##     see it. Measured: `tgt.get_v_scroll_bar() == held_bar` -> FALSE.
##
## That is why the surface sat in KNOWN_UNCONVERTED as UNMEASURED rather than exempt. Had I filed
## it clean on those three readings, this defect would have shipped behind my own note saying
## there was nothing here.

const ODD := [0.55, 0.65, 0.75, 0.85, 0.95]
const EVEN := [0.55, 0.75, 0.85, 0.95]


func after_each() -> void:
	Input.action_release("ui_down")
	Input.parse_input_event(_motion(0.0))
	MenuNav.step(_motion(0.0))


func _motion(v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = JOY_AXIS_LEFT_Y
	e.axis_value = v
	return e


## Read THROUGH the target, never a held reference. See the header.
func _scroll_value(m: Node) -> float:
	var t = m.get("_scroll_target")
	if t == null:
		return -1.0
	var sb = t.get_v_scroll_bar()
	if sb == null:
		return -2.0
	return sb.value


func _open() -> Node:
	Input.action_release("ui_down")
	Input.parse_input_event(_motion(0.0))
	MenuNav.step(_motion(0.0))
	await get_tree().process_frame
	var m: Node = load("res://src/ui/HowToPlayOverlay.gd").new()
	add_child_autofree(m)
	await get_tree().process_frame
	(m as CanvasItem).visible = true
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(300, 120)
	sc.size = Vector2(300, 120)
	var lbl := Label.new()
	lbl.custom_minimum_size = Vector2(280, 4000)
	lbl.text = "line\n".repeat(400)
	sc.add_child(lbl)
	m.add_child(sc)
	await get_tree().process_frame
	await get_tree().process_frame
	m.set("_scroll_target", sc)
	return m


func _ramp(m: Node, steps: Array) -> void:
	Input.action_press("ui_down", 1.0)
	for v in steps:
		Input.parse_input_event(_motion(v))
		m.call("_input", _motion(v))
	Input.action_release("ui_down")


## CONTROL for the fixture itself: if the helper cannot move the bar, every arm below compares
## two zeros. This is the assert the three failed probes would have tripped.
func test_control_the_fixture_can_scroll_at_all() -> void:
	var m: Node = await _open()
	assert_eq(_scroll_value(m), 0.0, "the fixture must start at the top")
	m.call("_scroll_help", 48.0)
	assert_eq(_scroll_value(m), 48.0,
		"_scroll_help could not move the bar — the fixture is wrong, and nothing below this line "
		+ "means anything. A held get_v_scroll_bar() reference reads 0 forever.")


func test_a_stick_push_scrolls_one_press_worth_at_either_parity() -> void:
	var a: Node = await _open()
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_DPAD_DOWN
	b.pressed = true
	Input.action_press("ui_down", 1.0)
	a.call("_input", b)
	Input.action_release("ui_down")
	var one: float = _scroll_value(a)
	assert_gt(one, 0.0,
		"LIVENESS: a d-pad press did not scroll — the handler early-returned or the fixture is short")

	for label in ["odd", "even"]:
		var m: Node = await _open()
		_ramp(m, ODD if label == "odd" else EVEN)
		assert_eq(_scroll_value(m), one,
			"%s-length stick push scrolled %.0f px, one press scrolls %.0f — an axis carries no "
			% [label, _scroll_value(m), one] + "echo flag, so every ramp step reads as a fresh press")


## ⛔ RadialPicker is the last raw-reading surface and it is IMMUNE BY CONSTRUCTION — measured, not
## assumed, which is the distinction I got wrong on AutogrindUI. It selects a slot by the stick's
## ANGLE rather than stepping a cursor, so every event of a ramp lands on the SAME slot:
##
##     d-pad down   _selected -> 3
##     odd ramp     [3, 3, 3, 3, 3]      even ramp   [3, 3, 3, 3]
##
## It could only be measured at all because `Input.parse_input_event()` updates the live axis state
## that `_input_direction` reads via `Input.get_joy_axis()` — a synthetic event alone leaves the
## device at zero, which is why three earlier sweeps could not drive it and I filed it UNMEASURED.
##
## This arm exists so the immunity cannot quietly become a defect: if anyone makes the selection
## RELATIVE (`_selected += 1`) instead of absolute, a ramp starts accumulating and this reds.
func test_the_radial_picker_selects_by_angle_not_by_steps() -> void:
	Input.parse_input_event(_motion(0.0))
	await get_tree().process_frame
	var m: Node = load("res://src/ui/RadialPicker.gd").new()
	add_child_autofree(m)
	await get_tree().process_frame
	m.call("setup", {"title": "T", "options": [
		{"id": "a", "label": "A"}, {"id": "b", "label": "B"}, {"id": "c", "label": "C"},
		{"id": "d", "label": "D"}, {"id": "e", "label": "E"}, {"id": "f", "label": "F"}]})
	await get_tree().process_frame
	(m as CanvasItem).visible = true

	var seen: Array = []
	for v in ODD:
		Input.parse_input_event(_motion(v))
		await get_tree().process_frame
		m.call("_unhandled_input", _motion(v))
		seen.append(int(m.get("_selected")))
	Input.parse_input_event(_motion(0.0))

	assert_gt(seen.size(), 1, "CONTROL: the ramp must deliver more than one event")
	assert_ne(int(seen[0]), 0,
		"LIVENESS: the stick never selected a slot — parse_input_event did not reach "
		+ "Input.get_joy_axis, and the arm below would be comparing unmoved values")
	for i in range(1, seen.size()):
		assert_eq(int(seen[i]), int(seen[0]),
			"event %d of the ramp moved the selection to %d, but event 0 chose %d — the picker has "
			% [i, int(seen[i]), int(seen[0])] + "become RELATIVE, so a ramp now accumulates")
