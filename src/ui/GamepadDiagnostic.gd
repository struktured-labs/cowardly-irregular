extends Control
class_name GamepadDiagnostic

var _label: RichTextLabel
var _active: bool = false


## Every action the PROJECT declares, not a hardcoded six. The old list showed 6 of 14 and two of
## those six are dead (camera_rotate_*, no handler anywhere), so a tester chasing "my A button does
## nothing" got no ui_accept row at all — on a pad whose whole failure mode is mode switches moving
## button indices. Parsed once and cached; this runs every frame while the overlay is open.
static var _cached_actions: Array[String] = []


static func project_actions() -> Array[String]:
	if not _cached_actions.is_empty():
		return _cached_actions
	var src := FileAccess.get_file_as_string("res://project.godot")
	var start := src.find("[input]")
	if start < 0:
		return _cached_actions
	var stop := src.find("\n[", start + 1)
	var body := src.substr(start, (stop - start) if stop > start else -1)
	for m in RegEx.create_from_string("(?m)^([A-Za-z_][A-Za-z0-9_]*)=\\{").search_all(body):
		_cached_actions.append(m.get_string(1))
	return _cached_actions


func _ready() -> void:
	visible = false
	z_index = 100
	set_anchors_preset(PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	_label = RichTextLabel.new()
	_label.set_anchors_preset(PRESET_FULL_RECT)
	_label.bbcode_enabled = true
	_label.scroll_active = false
	_label.add_theme_font_size_override("normal_font_size", 18)
	add_child(_label)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		_active = not _active
		visible = _active


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var e = event as InputEventJoypadMotion
		if abs(e.axis_value) > 0.1:
			print("[GAMEPAD] JoyMotion dev=%d axis=%d val=%.3f" % [e.device, e.axis, e.axis_value])
	elif event is InputEventJoypadButton and event.pressed:
		var e = event as InputEventJoypadButton
		print("[GAMEPAD] JoyButton dev=%d btn=%d" % [e.device, e.button_index])
	elif event is InputEventMouseMotion:
		var e = event as InputEventMouseMotion
		if e.relative.length() > 5.0:
			print("[GAMEPAD] MouseMotion rel=%s" % str(e.relative))


func _process(_delta: float) -> void:
	if not _active:
		return

	var text = "[b][color=yellow]GAMEPAD DIAGNOSTIC (F11 to close)[/color][/b]\n\n"

	for dev in Input.get_connected_joypads():
		var name = Input.get_joy_name(dev)
		var guid = Input.get_joy_guid(dev)
		var known = Input.is_joy_known(dev)
		text += "[color=cyan]Device %d: %s[/color]\n" % [dev, name]
		text += "  GUID: %s  Known: %s\n" % [guid, "YES" if known else "NO"]

		text += "  [color=lime]Axes:[/color] "
		for ax in range(8):
			var val = Input.get_joy_axis(dev, ax)
			if abs(val) > 0.05:
				text += "[color=white]%d=%.2f[/color] " % [ax, val]
			else:
				text += "[color=gray]%d=%.2f[/color] " % [ax, val]
		text += "\n"

		text += "  [color=lime]Buttons:[/color] "
		for btn in range(20):
			if Input.is_joy_button_pressed(dev, btn):
				text += "[color=yellow]%d[/color] " % btn
		text += "\n\n"

	text += "[color=cyan]Input Actions:[/color]\n"
	for action in project_actions():
		if InputMap.has_action(action):
			var strength = Input.get_action_strength(action)
			var color = "yellow" if strength > 0.1 else "gray"
			text += "  [color=%s]%s: %.2f[/color]\n" % [color, action, strength]

	text += "\n[color=cyan]Mouse velocity:[/color] %s\n" % str(Input.get_last_mouse_velocity())

	_label.text = text
