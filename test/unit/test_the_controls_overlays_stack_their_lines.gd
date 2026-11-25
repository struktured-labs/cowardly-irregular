extends GutTest

## The Controls screen's two overlays (remap capture, Button Test) placed their lines at fixed y (30/60/90 and
## 16/52/90/126) while every font scaled with Text Size, so at 200% the 32 px prompt ran into the line under it.
## They now stack by drawn height, wrap inside the box, and the box (and its border) grows when the words need it.

const CM := "res://src/ui/ControlsMenu.gd"
const CAPTURE_PX := {"CapturePrompt": 16, "CaptureHint": 12, "TimerLabel": 14}
const TEST_PX := {"TestPrompt": 14, "TestResult": 22, "TestRaw": 13, "TestCloseHint": 12}

var _saved = null


func before_each() -> void:
	_saved = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _saved


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, or every preset loop passes empty: " + str(p))
	return p


func _menu_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var layer := CanvasLayer.new()
	vp.add_child(layer)
	var m: Control = load(CM).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


## The longest remappable action name, so the capture prompt is at its widest.
func _longest_action() -> String:
	var best := ""
	for a in InputProfileManager.REMAPPABLE_ACTIONS:
		if str(InputProfileManager.ACTION_LABELS.get(a, a)).length() > str(InputProfileManager.ACTION_LABELS.get(best, best)).length():
			best = a
	return best


## Lines in child order: each starts below the one before, keeps its Text Size, and ends inside the box; the box stays on screen.
func _judge(scale: float, box: Control, px: Dictionary, screen: Vector2) -> Array:
	var bad: Array = []
	var prev_bottom: float = -INF
	var prev_name: String = ""
	var seen: int = 0
	for c in box.get_children():
		if not (c is Label):
			continue
		var l := c as Label
		seen += 1
		if px.has(str(l.name)) and l.get_theme_font_size("font_size") != TextScale.scaled(int(px[str(l.name)])):
			bad.append("%.2fx %s drawn at %d px, the setting asks %d" % [scale, l.name, l.get_theme_font_size("font_size"), TextScale.scaled(int(px[str(l.name)]))])
		var h: float = l.get_minimum_size().y
		if l.position.y < prev_bottom - 0.5:
			bad.append("%.2fx %s starts at %.0f, inside %s (ends %.0f)" % [scale, l.name, l.position.y, prev_name, prev_bottom])
		if l.position.x + l.size.x > box.size.x + 0.5 or l.position.y + h > box.size.y + 0.5:
			bad.append("%.2fx %s ends at (%.0f, %.0f) outside its %.0fx%.0f box" % [scale, l.name, l.position.x + l.size.x, l.position.y + h, box.size.x, box.size.y])
		prev_bottom = l.position.y + h
		prev_name = str(l.name)
	if seen < 3:
		bad.append("%.2fx the box holds %d lines, expected 3+" % [scale, seen])
	if box.position.y < -0.5 or box.position.y + box.size.y > screen.y + 0.5:
		bad.append("%.2fx the box runs off screen (%.0f..%.0f)" % [scale, box.position.y, box.position.y + box.size.y])
	return bad


## CONTROL: at the largest preset the authored 30/60 stacking cannot hold the capture prompt, so the arms below can see it.
func test_control_the_authored_rows_do_not_fit_the_largest_size() -> void:
	var p: Array = _presets()
	var m: Control = await _menu_at(float(p.max()))
	var f: Font = m.get_theme_font("font", "Label")
	assert_gt(30.0 + f.get_height(TextScale.scaled(16)), 60.0, "CONTROL: at %.2fx the prompt from y 30 reaches the hint's authored y 60" % float(p.max()))


func test_the_capture_box_stacks_its_lines_at_every_size() -> void:
	var bad: Array = []
	var act: String = _longest_action()
	for scale in _presets():
		var m: Control = await _menu_at(float(scale))
		m._start_capture(act)
		await get_tree().process_frame
		bad.append_array(_judge(float(scale), m._capture_overlay.get_node("CaptureBox"), CAPTURE_PX, m.size))
		m._cancel_capture()
	assert_eq(bad, [], "the capture box stacks its lines: %s" % [bad])


## Driven through the real button handler, which writes the result and mapped lines.
func test_the_button_test_box_stacks_its_lines_at_every_size() -> void:
	var bad: Array = []
	for scale in _presets():
		var m: Control = await _menu_at(float(scale))
		m._test_overlay.visible = true
		## Not a Cancel button: the handler closes the tester on ui_cancel (south face under Nintendo) and writes nothing.
		var ev := InputEventJoypadButton.new()
		ev.button_index = JOY_BUTTON_LEFT_SHOULDER
		assert_false(ev.is_action_pressed("ui_cancel"), "PRECONDITION: the probe button is not Cancel")
		ev.pressed = true
		m._handle_test_input(ev)
		await get_tree().process_frame
		var box: Control = m._test_overlay.get_node("TestBox")
		assert_ne(str((box.get_node("TestResult") as Label).text), "", "PRECONDITION: the press wrote a result line")
		bad.append_array(_judge(float(scale), box, TEST_PX, m.size))
	assert_eq(bad, [], "the Button Test box stacks its lines: %s" % [bad])


## Words longer than the box grows it, the border follows the new edge, and it stays on screen.
func test_a_box_grows_for_its_words_and_its_border_follows() -> void:
	var m: Control = await _menu_at(1.0)
	var box: Control = m._test_overlay.get_node("TestBox")
	var before: float = box.size.y
	(box.get_node("TestRaw") as Label).text = "Mapped to: " + "Navigate Up / Navigate Down / Confirm / Cancel / Party Chat / ".repeat(40)
	assert_gt(m._wrapped_h(box.get_node("TestRaw"), box.size.x - 40.0) + 126.0 + 36.0, before, "CONTROL: these words need more than the authored box")
	m._restack_box(box)
	await get_tree().process_frame
	assert_gt(box.size.y, before, "the box grows to hold its words")
	var border_bottom: float = 0.0
	for c in box.get_children():
		if c is ColorRect and not (c as ColorRect).is_queued_for_deletion():
			border_bottom = maxf(border_bottom, (c as ColorRect).position.y + (c as ColorRect).size.y)
	assert_almost_eq(border_bottom, box.size.y, 0.5, "the border's bottom edge is the grown box's bottom")
	assert_eq(_judge(1.0, box, TEST_PX, m.size), [], "and its lines still stack inside it, on screen")


## 100% renders as built: the authored y and the authored box, for both overlays.
func test_the_default_size_renders_the_shipped_overlays() -> void:
	var m: Control = await _menu_at(1.0)
	m._start_capture(_longest_action())
	await get_tree().process_frame
	var cb: Control = m._capture_overlay.get_node("CaptureBox")
	var ys: Array = []
	for n in ["CapturePrompt", "CaptureHint", "TimerLabel"]:
		ys.append(int((cb.get_node(n) as Label).position.y))
	assert_eq(ys, [30, 60, 90], "the capture lines sit at their authored y at 100%")
	assert_almost_eq(cb.size, m.size * Vector2(0.5, 0.3), Vector2(0.5, 0.5), "the capture box keeps its authored size at 100%")
	m._cancel_capture()
	var tb: Control = m._test_overlay.get_node("TestBox")
	var tys: Array = []
	for c in tb.get_children():
		if c is Label:
			tys.append(int((c as Label).position.y))
	assert_eq(tys, [16, 52, 90, 126, int(tb.size.y) - 36], "the Button Test lines sit at their authored y at 100%")
	assert_almost_eq(tb.size, m.size * Vector2(0.6, 0.5), Vector2(0.5, 0.5), "the Button Test box keeps its authored size at 100%")
