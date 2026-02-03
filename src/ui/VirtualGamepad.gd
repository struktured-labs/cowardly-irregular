extends CanvasLayer
class_name VirtualGamepadClass

## Virtual gamepad overlay for touch/mobile/web
## Renders D-pad + A/B/L/R/Start/Select buttons
## Sends InputEventAction so the rest of the game works unchanged

const OPACITY = 0.45
const PRESSED_OPACITY = 0.7
const REFERENCE_HEIGHT = 480.0  # Sizes are designed for this viewport height

## Computed sizes (scaled to viewport)
var _scale: float = 1.0
var _button_radius: float = 28.0
var _dpad_size: float = 72.0
var _dpad_button_size: float = 44.0
var _small_radius: float = 22.0
var _diamond_offset: float = 36.0
var _margin: float = 90.0
var _margin_y_bottom: float = 100.0
var _shoulder_y: float = 50.0
var _center_gap: float = 40.0
var _bottom_row_y: float = 36.0

## Whether to show the virtual gamepad
var _visible := false
var _buttons: Dictionary = {}
var _dpad_center: Vector2 = Vector2.ZERO
var _active_dpad: String = ""
var _touch_map: Dictionary = {}  # touch_index -> button_name


func _ready() -> void:
	layer = 100
	# Auto-detect touch device
	if _is_touch_device():
		_visible = true
		_compute_scale()
		_create_buttons()
		_draw_dpad()


func _compute_scale() -> void:
	"""Scale all sizes relative to viewport height for DPI awareness"""
	var vp_h = get_viewport().get_visible_rect().size.y
	_scale = vp_h / REFERENCE_HEIGHT
	_button_radius = 28.0 * _scale
	_dpad_size = 72.0 * _scale
	_dpad_button_size = 44.0 * _scale
	_small_radius = 22.0 * _scale
	_diamond_offset = 36.0 * _scale
	_margin = 90.0 * _scale
	_margin_y_bottom = 100.0 * _scale
	_shoulder_y = 50.0 * _scale
	_center_gap = 40.0 * _scale
	_bottom_row_y = 36.0 * _scale


func _is_touch_device() -> bool:
	# Show on web builds and when no gamepad connected
	return OS.has_feature("web") or DisplayServer.is_touchscreen_available()


func _create_buttons() -> void:
	var vp = get_viewport().get_visible_rect().size

	# D-pad (bottom-left)
	_dpad_center = Vector2(_margin, vp.y - _margin_y_bottom)
	_create_dpad_button("ui_up", _dpad_center + Vector2(0, -_dpad_button_size))
	_create_dpad_button("ui_down", _dpad_center + Vector2(0, _dpad_button_size))
	_create_dpad_button("ui_left", _dpad_center + Vector2(-_dpad_button_size, 0))
	_create_dpad_button("ui_right", _dpad_center + Vector2(_dpad_button_size, 0))

	# Action buttons (bottom-right) — full SNES diamond: Y(left) X(top) A(right) B(bottom)
	var action_center = Vector2(vp.x - _margin, vp.y - _margin_y_bottom)
	_create_action_button("ui_accept", action_center + Vector2(_diamond_offset, 0), "A", Color(0.2, 0.7, 0.3))
	_create_action_button("ui_cancel", action_center + Vector2(0, _diamond_offset), "B", Color(0.8, 0.3, 0.3))
	_create_joypad_button(JOY_BUTTON_X, action_center + Vector2(0, -_diamond_offset), "X", Color(0.3, 0.4, 0.8))
	_create_joypad_button(JOY_BUTTON_Y, action_center + Vector2(-_diamond_offset, 0), "Y", Color(0.6, 0.5, 0.2))

	# L/R shoulder buttons (top corners)
	_create_action_button("battle_defer", Vector2(60 * _scale, _shoulder_y), "L", Color(0.5, 0.5, 0.7))
	_create_action_button("battle_advance", Vector2(vp.x - 60 * _scale, _shoulder_y), "R", Color(0.5, 0.5, 0.7))

	# Start/Select (bottom center)
	_create_action_button("ui_menu", Vector2(vp.x / 2 + _center_gap, vp.y - _bottom_row_y), "START", Color(0.5, 0.5, 0.5), true)
	_create_action_button("battle_toggle_auto", Vector2(vp.x / 2 - _center_gap, vp.y - _bottom_row_y), "SEL", Color(0.5, 0.5, 0.5), true)


func _create_dpad_button(action: String, pos: Vector2) -> void:
	var btn = _make_touch_area(action, pos, Vector2(_dpad_button_size, _dpad_button_size))
	_buttons[action] = {"node": btn, "pos": pos, "radius": _dpad_button_size / 2, "pressed": false}


func _create_joypad_button(button_index: int, pos: Vector2, label_text: String, color: Color) -> void:
	"""Create a button that sends InputEventJoypadButton (for X/Y that need raw button events)"""
	var radius = _button_radius
	var btn = _make_touch_area("joy_%d" % button_index, pos, Vector2(radius * 2, radius * 2))

	var circle = _draw_circle_texture(radius, color, label_text)
	circle.position = pos - Vector2(radius, radius)
	add_child(circle)

	var key = "joy_%d" % button_index
	_buttons[key] = {"node": btn, "pos": pos, "radius": radius, "pressed": false, "visual": circle, "joypad_button": button_index}


func _create_action_button(action: String, pos: Vector2, label_text: String, color: Color, small: bool = false) -> void:
	var radius = _button_radius if not small else _small_radius
	var btn = _make_touch_area(action, pos, Vector2(radius * 2, radius * 2))

	# Visual circle
	var circle = _draw_circle_texture(radius, color, label_text)
	circle.position = pos - Vector2(radius, radius)
	add_child(circle)

	_buttons[action] = {"node": btn, "pos": pos, "radius": radius, "pressed": false, "visual": circle}


func _make_touch_area(_action: String, pos: Vector2, btn_size: Vector2) -> Control:
	var area = Control.new()
	area.position = pos - btn_size / 2
	area.size = btn_size
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(area)
	return area


func _draw_circle_texture(radius: float, color: Color, label_text: String) -> TextureRect:
	var s = int(radius * 2)
	var img = Image.create(s, s, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = s / 2.0
	for y in range(s):
		for x in range(s):
			var dist = sqrt(pow(x - cx, 2) + pow(y - cx, 2))
			if dist < radius - 2:
				var t = dist / radius
				var c = color.darkened(t * 0.3)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, OPACITY))
			elif dist < radius:
				img.set_pixel(x, y, Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, OPACITY))

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Label on button
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", int((11 if label_text.length() <= 2 else 8) * _scale))
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.add_child(lbl)

	return rect


func _draw_dpad() -> void:
	var s = int(_dpad_size * 2.4)
	var img = Image.create(s, s, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = s / 2.0
	var arm_w = _dpad_button_size * 0.7
	var arm_len = _dpad_size * 0.9
	var color = Color(0.4, 0.4, 0.5)

	# Cross shape
	for y in range(s):
		for x in range(s):
			var dy = abs(y - cx)
			var dx = abs(x - cx)
			if (dy < arm_w / 2 and dx < arm_len / 2) or (dx < arm_w / 2 and dy < arm_len / 2):
				var dist = max(dx, dy) / (arm_len / 2)
				img.set_pixel(x, y, Color(color.r, color.g, color.b, OPACITY * (1.0 - dist * 0.3)))

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = _dpad_center - Vector2(s / 2.0, s / 2.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)

	# Arrow labels
	var arrow_offset = 30.0 * _scale
	var font_sz = int(14 * _scale)
	for dir_data in [["^", Vector2(0, -arrow_offset)], ["v", Vector2(0, arrow_offset)], ["<", Vector2(-arrow_offset, 0)], [">", Vector2(arrow_offset, 0)]]:
		var lbl = Label.new()
		lbl.text = dir_data[0]
		lbl.add_theme_font_size_override("font_size", font_sz)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.position = _dpad_center + dir_data[1] - Vector2(8 * _scale, 10 * _scale)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lbl)


func _input(event: InputEvent) -> void:
	if not _visible:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			var action = _get_button_at(event.position)
			if action != "":
				_touch_map[event.index] = action
				_press_action(action)
				get_viewport().set_input_as_handled()
		else:
			if _touch_map.has(event.index):
				var action = _touch_map[event.index]
				_release_action(action)
				_touch_map.erase(event.index)
				get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag:
		if _touch_map.has(event.index):
			var old_action = _touch_map[event.index]
			var new_action = _get_button_at(event.position)
			if new_action != old_action:
				_release_action(old_action)
				if new_action != "":
					_touch_map[event.index] = new_action
					_press_action(new_action)
				else:
					_touch_map.erase(event.index)
			get_viewport().set_input_as_handled()


func _get_button_at(pos: Vector2) -> String:
	for action in _buttons:
		var btn = _buttons[action]
		var dist = pos.distance_to(btn["pos"])
		if dist < btn["radius"] * 1.3:  # Slightly generous hitbox
			return action
	return ""


func _press_action(action: String) -> void:
	if _buttons.has(action):
		_buttons[action]["pressed"] = true
		if _buttons[action].has("visual"):
			_buttons[action]["visual"].modulate.a = PRESSED_OPACITY / OPACITY

		# Joypad buttons send InputEventJoypadButton instead of InputEventAction
		if _buttons[action].has("joypad_button"):
			var ev = InputEventJoypadButton.new()
			ev.button_index = _buttons[action]["joypad_button"]
			ev.pressed = true
			Input.parse_input_event(ev)
			return

	var ev = InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _release_action(action: String) -> void:
	if _buttons.has(action):
		_buttons[action]["pressed"] = false
		if _buttons[action].has("visual"):
			_buttons[action]["visual"].modulate.a = 1.0

		if _buttons[action].has("joypad_button"):
			var ev = InputEventJoypadButton.new()
			ev.button_index = _buttons[action]["joypad_button"]
			ev.pressed = false
			Input.parse_input_event(ev)
			return

	var ev = InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)
