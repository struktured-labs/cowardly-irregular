extends Control
class_name ControlsMenu

## Controls Menu - Button remapping submenu for SettingsMenu.
## Follows RetroPanel border style and SettingsMenu patterns.

signal closed()

## UI State
var selected_index: int = 0  # 0=profile row, 1-6=action rows, 7=reset, 8=test buttons
var _capturing: bool = false
var _capture_action: String = ""
var _capture_timer: float = 0.0
const CAPTURE_TIMEOUT = 5.0
var _testing: bool = false

## Node references
var _panel: Control
var _profile_label: Label
var _action_labels: Dictionary = {}  # action -> Label showing current button
var _highlight_refs: Array = []
var _capture_overlay: Control
var _test_overlay: Control
var _test_result_label: Label
var _conflict_label: Label
var _device_label: Label
var _flash_label: Label
var _flash_timer: float = 0.0

## Layout. Row indices were three hardcoded magic numbers (0/7/8) across _build_ui, _input and
## _activate_row — inserting a row meant editing all three in step or dispatching to the wrong
## one silently. The tail rows are DERIVED from REMAPPABLE_ACTIONS so they cannot drift.
const ROW_PROFILE := 0
const ROW_NINTENDO := 1
const ROW_ACTION_FIRST := 2
const ROW_HEIGHT = 40
const ROW_START_Y = 48

var _row_reset: int = 0
var _row_test: int = 0
var _row_map_pad: int = 0
var _item_count: int = 0

## SDL-mapping capture state. Separate from _capturing, which remaps ONE action to a button
## the player picks; this walks the whole pad to build a mapping SDL doesn't have.
var _mapping: RefCounted = null
var _mapping_overlay: Control = null
var _mapping_prompt: Label = null
var _mapping_status: Label = null


func _compute_row_indices() -> void:
	_row_reset = ROW_ACTION_FIRST + InputProfileManager.REMAPPABLE_ACTIONS.size()
	_row_test = _row_reset + 1
	_row_map_pad = _row_test + 1
	_item_count = _row_map_pad + 1

## Style (matches SettingsMenu)
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_LIGHT = RetroPanel.BORDER_LIGHT
const BORDER_SHADOW = RetroPanel.BORDER_SHADOW
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const WARN_COLOR = Color(1.0, 0.45, 0.35)
const OPTION_SELECTED = Color(0.3, 0.5, 0.8)
const CAPTURE_BG = Color(0.0, 0.0, 0.0, 0.85)


func _ready() -> void:
	_build_ui()
	# A pad can appear, sleep or change MODE while this screen is open — an 8BitDo Ultimate 2
	# re-enumerates under a different product id per mode, which changes its GUID and can void
	# its mapping. Keep the readout honest rather than frozen at open-time.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	refresh_device_label()


## Pure text/severity decision, split out so it is testable without a physical pad attached.
## is_known == false means SDL has no mapping for this GUID, so Godot reports RAW device indices
## and every gamepad binding on this screen points at the wrong physical control.
## face_family/layout are optional so existing callers and their guards keep working; when
## supplied they name the RECOGNISED pad and show its printed face layout, which is the one
## thing a player can check against the controller in their hands.
func describe_pad_status(has_pad: bool, pad_name: String, is_known: bool, guid: String,
		face_family: String = "", layout: String = "") -> Dictionary:
	if not has_pad:
		return {"text": "No gamepad detected — keyboard bindings still apply", "warn": false}
	var ident := ""
	if face_family != "":
		ident = "  ·  %s layout   %s" % [face_family.capitalize(), layout]
	if is_known:
		return {"text": "%s — SDL mapping OK%s" % [pad_name, ident], "warn": false}
	# Points at the pre-existing F11 overlay rather than duplicating it. GamepadDiagnostic has shown
	# name/GUID/is_joy_known plus live button and axis reads since long before this readout existed —
	# the 2026-07-28 controller hunt was a DISCOVERABILITY failure as much as a diagnostic one, so the
	# one place a player looks when their pad misbehaves should name the deeper tool.
	return {
		"text": "%s — NO SDL MAPPING: the buttons below are WRONG for this pad (guid %s) · F11 for live button/axis readout" % [pad_name, guid],
		"warn": true,
	}


func refresh_device_label() -> void:
	if _device_label == null or not is_instance_valid(_device_label):
		return
	var pads := Input.get_connected_joypads()
	var has_pad := not pads.is_empty()
	var device: int = pads[0] if has_pad else -1
	var pad_name := Input.get_joy_name(device) if has_pad else ""
	var family := InputProfileManager.face_family_for_device(pad_name) if has_pad else ""
	var status := describe_pad_status(
		has_pad,
		pad_name,
		Input.is_joy_known(device) if has_pad else false,
		Input.get_joy_guid(device) if has_pad else "",
		family,
		InputProfileManager.face_layout_diagram(family) if has_pad else "",
	)
	_device_label.text = status["text"]
	_device_label.add_theme_color_override("font_color", WARN_COLOR if status["warn"] else DISABLED_COLOR)


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()
	_highlight_refs.clear()
	_action_labels.clear()

	# Full screen background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main panel
	_panel = Control.new()
	_panel.position = Vector2(size.x * 0.2, size.y * 0.1)
	_panel.size = Vector2(size.x * 0.6, size.y * 0.8)
	add_child(_panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(panel_bg)

	RetroPanel.add_border(_panel, _panel.size, BORDER_LIGHT, BORDER_SHADOW)

	# Title
	var title = Label.new()
	title.text = "CONTROLS"
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	_panel.add_child(title)

	# Subtitle carries LIVE DEVICE TRUTH rather than boilerplate. Nothing on screen used to say
	# whether SDL had a mapping for the attached pad, and unmapped every index below is a lie —
	# that absence is what made the 2026-07-25 controller hunt expensive.
	_device_label = Label.new()
	_device_label.position = Vector2(16, 30)
	_device_label.add_theme_font_size_override("font_size", 10)
	_panel.add_child(_device_label)
	refresh_device_label()

	# Column header — only shown for the action rows so user knows what
	# the right-hand columns mean. Drawn just above the first action row.
	var col_header_pad = Label.new()
	col_header_pad.text = "Action"
	col_header_pad.position = Vector2(12, ROW_START_Y + ROW_HEIGHT - 4)
	col_header_pad.add_theme_font_size_override("font_size", 10)
	col_header_pad.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	_panel.add_child(col_header_pad)
	var col_header_pad_btn = Label.new()
	col_header_pad_btn.text = "Gamepad"
	col_header_pad_btn.position = Vector2(320, ROW_START_Y + ROW_HEIGHT - 4)
	col_header_pad_btn.add_theme_font_size_override("font_size", 10)
	col_header_pad_btn.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	_panel.add_child(col_header_pad_btn)
	var col_header_kb = Label.new()
	col_header_kb.text = "Keyboard"
	col_header_kb.position = Vector2(490, ROW_START_Y + ROW_HEIGHT - 4)
	col_header_kb.add_theme_font_size_override("font_size", 10)
	col_header_kb.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	_panel.add_child(col_header_kb)
	var col_header_mouse = Label.new()
	col_header_mouse.text = "Mouse"
	col_header_mouse.position = Vector2(610, ROW_START_Y + ROW_HEIGHT - 4)
	col_header_mouse.add_theme_font_size_override("font_size", 10)
	col_header_mouse.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	_panel.add_child(col_header_mouse)

	# Build rows
	_compute_row_indices()
	var y = ROW_START_Y

	_add_row(ROW_PROFILE, y, "Profile", _get_profile_display(), true)
	y += ROW_HEIGHT

	# Confirm sits on the EAST face when on — the SNES layout. Cycles like the profile row.
	_add_row(ROW_NINTENDO, y, "Nintendo Mode", _get_nintendo_display(), true)
	y += ROW_HEIGHT + 8

	var row_idx = ROW_ACTION_FIRST
	for action in InputProfileManager.REMAPPABLE_ACTIONS:
		var label_text = InputProfileManager.ACTION_LABELS.get(action, action)
		var btn_label = InputProfileManager.get_action_button_label(action)
		_add_row(row_idx, y, label_text, btn_label, false)
		_action_labels[action] = _highlight_refs[row_idx].get_meta("value_label")
		row_idx += 1
		y += ROW_HEIGHT

	y += 8
	_add_row(_row_reset, y, "Reset to Default", "", false, true)
	y += ROW_HEIGHT

	_add_row(_row_test, y, "Test Buttons", "", false, true)
	y += ROW_HEIGHT

	_add_row(_row_map_pad, y, "Map This Pad", _map_pad_hint(), false, true)

	# Conflict display
	_conflict_label = Label.new()
	_conflict_label.position = Vector2(16, _panel.size.y - 52)
	_conflict_label.add_theme_font_size_override("font_size", 10)
	_conflict_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	_panel.add_child(_conflict_label)
	_update_conflict_display()

	# Flash message label (for "Switch to Custom" hint)
	_flash_label = Label.new()
	_flash_label.position = Vector2(16, _panel.size.y - 68)
	_flash_label.add_theme_font_size_override("font_size", 10)
	_flash_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
	_flash_label.visible = false
	_panel.add_child(_flash_label)

	# Footer — list ALL three input methods for transparency
	var footer = Label.new()
	footer.text = "Gamepad: ←→ Profile · A Remap · B Back     Keyboard: Z Confirm · X Back · Enter Remap     Mouse: LMB Click · RMB Back"
	footer.position = Vector2(16, _panel.size.y - 32)
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	_panel.add_child(footer)

	# Right-click to cancel
	MenuMouseHelper.add_right_click_cancel(bg, _close_menu)

	# Capture overlay (hidden)
	_build_capture_overlay()

	# Test overlay (hidden)
	_build_test_overlay()

	_update_selection()


func _add_row(index: int, y: float, label_text: String, value_text: String, is_profile: bool, is_action_btn: bool = false) -> void:
	var highlight = ColorRect.new()
	highlight.position = Vector2(8, y)
	highlight.size = Vector2(_panel.size.x - 16, ROW_HEIGHT)
	highlight.color = Color.TRANSPARENT
	highlight.name = "Row_%d" % index
	_panel.add_child(highlight)
	_highlight_refs.append(highlight)

	var label = Label.new()
	label.text = label_text
	label.position = Vector2(12, 4)
	label.add_theme_font_size_override("font_size", 14)
	if is_action_btn:
		label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	else:
		label.add_theme_color_override("font_color", TEXT_COLOR)
	highlight.add_child(label)

	if is_profile:
		var arrows_left = Label.new()
		arrows_left.text = "<"
		arrows_left.position = Vector2(200, 4)
		arrows_left.add_theme_font_size_override("font_size", 14)
		arrows_left.add_theme_color_override("font_color", Color.YELLOW)
		highlight.add_child(arrows_left)

		var value = Label.new()
		value.text = value_text
		value.position = Vector2(220, 4)
		value.add_theme_font_size_override("font_size", 14)
		value.add_theme_color_override("font_color", Color.YELLOW)
		value.name = "ValueLabel"
		highlight.add_child(value)
		highlight.set_meta("value_label", value)

		var arrows_right = Label.new()
		arrows_right.text = ">"
		arrows_right.position = Vector2(420, 4)
		arrows_right.add_theme_font_size_override("font_size", 14)
		arrows_right.add_theme_color_override("font_color", Color.YELLOW)
		highlight.add_child(arrows_right)
	elif not is_action_btn and value_text != "":
		# Dots + gamepad button label
		var dots = Label.new()
		var dot_count = max(1, 30 - label_text.length())
		dots.text = ".".repeat(dot_count)
		dots.position = Vector2(12 + label_text.length() * 9, 8)
		dots.add_theme_font_size_override("font_size", 10)
		dots.add_theme_color_override("font_color", Color(0.3, 0.3, 0.4))
		highlight.add_child(dots)

		var value = Label.new()
		value.text = value_text
		value.position = Vector2(320, 4)
		value.size = Vector2(160, ROW_HEIGHT - 8)
		value.add_theme_font_size_override("font_size", 13)
		value.add_theme_color_override("font_color", OPTION_SELECTED)
		value.name = "ValueLabel"
		highlight.add_child(value)
		highlight.set_meta("value_label", value)

		# Read-only keyboard binding column (sourced from InputMap)
		# Look up by InputProfileManager.REMAPPABLE_ACTIONS index — `index`
		# arg is 1-based for action rows (0 is profile selector).
		var action_idx: int = index - 1
		if action_idx >= 0 and action_idx < InputProfileManager.REMAPPABLE_ACTIONS.size():
			var action_id: String = InputProfileManager.REMAPPABLE_ACTIONS[action_idx]
			var kb_label_text := InputProfileManager.get_action_key_label(action_id)
			var kb_label = Label.new()
			kb_label.text = kb_label_text
			kb_label.position = Vector2(490, 4)
			kb_label.size = Vector2(110, ROW_HEIGHT - 8)
			kb_label.add_theme_font_size_override("font_size", 13)
			# Slightly muted color since it's not remappable here
			kb_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
			highlight.add_child(kb_label)

			var mouse_label_text := InputProfileManager.get_action_mouse_label(action_id)
			var mouse_label = Label.new()
			mouse_label.text = mouse_label_text
			mouse_label.position = Vector2(610, 4)
			mouse_label.size = Vector2(120, ROW_HEIGHT - 8)
			mouse_label.add_theme_font_size_override("font_size", 13)
			mouse_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
			highlight.add_child(mouse_label)

	# Mouse support
	MenuMouseHelper.make_clickable(highlight, index, _panel.size.x - 16, ROW_HEIGHT,
		_on_row_click.bind(index), _on_row_hover.bind(index))


func _build_capture_overlay() -> void:
	_capture_overlay = Control.new()
	_capture_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_capture_overlay.visible = false
	_capture_overlay.z_index = 10
	add_child(_capture_overlay)

	var overlay_bg = ColorRect.new()
	overlay_bg.color = CAPTURE_BG
	overlay_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_capture_overlay.add_child(overlay_bg)

	var box = ColorRect.new()
	box.color = PANEL_COLOR
	box.position = Vector2(size.x * 0.25, size.y * 0.35)
	box.size = Vector2(size.x * 0.5, size.y * 0.3)
	box.name = "CaptureBox"
	_capture_overlay.add_child(box)

	RetroPanel.add_border(box, box.size, BORDER_LIGHT, BORDER_SHADOW)

	var prompt = Label.new()
	prompt.text = "Press a gamepad button..."
	prompt.position = Vector2(20, 30)
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", Color.YELLOW)
	prompt.name = "CapturePrompt"
	box.add_child(prompt)

	var hint = Label.new()
	hint.text = "B to cancel  |  5s timeout"
	hint.position = Vector2(20, 60)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", DISABLED_COLOR)
	box.add_child(hint)

	var timer_label = Label.new()
	timer_label.text = "5.0s"
	timer_label.position = Vector2(20, 90)
	timer_label.add_theme_font_size_override("font_size", 14)
	timer_label.add_theme_color_override("font_color", TEXT_COLOR)
	timer_label.name = "TimerLabel"
	box.add_child(timer_label)


func _build_test_overlay() -> void:
	_test_overlay = Control.new()
	_test_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_test_overlay.visible = false
	_test_overlay.z_index = 10
	add_child(_test_overlay)

	var overlay_bg = ColorRect.new()
	overlay_bg.color = CAPTURE_BG
	overlay_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_test_overlay.add_child(overlay_bg)

	var box = ColorRect.new()
	box.color = PANEL_COLOR
	box.position = Vector2(size.x * 0.2, size.y * 0.25)
	box.size = Vector2(size.x * 0.6, size.y * 0.5)
	box.name = "TestBox"
	_test_overlay.add_child(box)

	RetroPanel.add_border(box, box.size, BORDER_LIGHT, BORDER_SHADOW)

	var title = Label.new()
	title.text = "BUTTON TEST"
	title.position = Vector2(20, 16)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color.YELLOW)
	box.add_child(title)

	var prompt = Label.new()
	prompt.text = "Press any gamepad button..."
	prompt.position = Vector2(20, 52)
	prompt.add_theme_font_size_override("font_size", 14)
	prompt.add_theme_color_override("font_color", TEXT_COLOR)
	prompt.name = "TestPrompt"
	box.add_child(prompt)

	_test_result_label = Label.new()
	_test_result_label.text = ""
	_test_result_label.position = Vector2(20, 90)
	_test_result_label.add_theme_font_size_override("font_size", 22)
	_test_result_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	_test_result_label.name = "TestResult"
	box.add_child(_test_result_label)

	var raw_label = Label.new()
	raw_label.text = ""
	raw_label.position = Vector2(20, 126)
	raw_label.add_theme_font_size_override("font_size", 13)
	raw_label.add_theme_color_override("font_color", DISABLED_COLOR)
	raw_label.name = "TestRaw"
	box.add_child(raw_label)

	var hint = Label.new()
	hint.text = "B / Escape to close"
	hint.position = Vector2(20, box.size.y - 36)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", DISABLED_COLOR)
	box.add_child(hint)


func _start_test() -> void:
	_testing = true
	_test_overlay.visible = true
	var result = _test_overlay.get_node_or_null("TestBox/TestResult")
	if result:
		result.text = ""
	var raw = _test_overlay.get_node_or_null("TestBox/TestRaw")
	if raw:
		raw.text = ""
	if SoundManager:
		SoundManager.play_ui("menu_select")


func _stop_test() -> void:
	_testing = false
	_test_overlay.visible = false
	if SoundManager:
		SoundManager.play_ui("menu_close")


func _handle_test_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_X or event.keycode == KEY_ESCAPE:
			_stop_test()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventJoypadButton and event.pressed:
		var btn = event.button_index
		var label_str = InputProfileManager.get_button_label(btn)
		var result = _test_overlay.get_node_or_null("TestBox/TestResult")
		if result:
			result.text = "Button %d: %s" % [btn, label_str]
		var raw = _test_overlay.get_node_or_null("TestBox/TestRaw")
		if raw:
			# Show which action this maps to in the active profile, if any
			var mapped_actions = []
			var bindings = InputProfileManager.get_profile_bindings(InputProfileManager.active_profile)
			for action in bindings:
				if btn in bindings[action]:
					var action_label = InputProfileManager.ACTION_LABELS.get(action, action)
					mapped_actions.append(action_label)
			if mapped_actions.is_empty():
				raw.text = "(no action mapped)"
			else:
				raw.text = "Mapped to: %s" % " / ".join(mapped_actions)

		# B (button 0) also closes after showing the result — but only if it
		# was already shown before (i.e. user presses B intentionally to exit).
		# We let it display first on press then user presses B again to close.
		# Actually: if btn == 0, close immediately so it's not confusing.
		if btn == 0:
			_stop_test()

		get_viewport().set_input_as_handled()
		return

	if event is InputEventJoypadMotion or event is InputEventKey:
		get_viewport().set_input_as_handled()


func _get_profile_display() -> String:
	return InputProfileManager.active_profile


func _update_selection() -> void:
	for i in range(_highlight_refs.size()):
		_highlight_refs[i].color = SELECTED_COLOR if i == selected_index else Color.TRANSPARENT


func _update_all_labels() -> void:
	_set_row_value(ROW_PROFILE, _get_profile_display())
	_set_row_value(ROW_NINTENDO, _get_nintendo_display())

	# Update action labels
	for action in _action_labels:
		_action_labels[action].text = InputProfileManager.get_action_button_label(action)

	_update_conflict_display()


func _set_row_value(row: int, text: String) -> void:
	if row < 0 or row >= _highlight_refs.size():
		return
	if not _highlight_refs[row].has_meta("value_label"):
		return
	var val_label = _highlight_refs[row].get_meta("value_label")
	if val_label:
		val_label.text = text


## Reads as the glyph PRINTED on the attached pad rather than the position — a player holding
## an Xbox pad should be told "Ⓑ", not the Nintendo name for the same physical button.
func _get_nintendo_display() -> String:
	var on: bool = InputProfileManager.nintendo_mode
	var glyph: String = InputProfileManager.glyph_for_action("ui_accept")
	return "%s   Confirm = %s  (%s face)" % ["ON" if on else "OFF", glyph, "east" if on else "south"]


## An already-mapped pad rarely needs this; an unmapped one always does, so the row says which.
func _map_pad_hint() -> String:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return "no pad connected"
	if Input.is_joy_known(pads[0]):
		return "SDL already knows this pad — recapture only if it misbehaves"
	return "THIS PAD IS UNMAPPED — capture it"


func _start_pad_mapping() -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_show_flash("Connect a pad first")
		return
	var device: int = pads[0]
	var CaptureScript = load("res://src/input/ControllerMappingCapture.gd")
	_mapping = CaptureScript.new(Input.get_joy_guid(device), Input.get_joy_name(device))
	_build_mapping_overlay()
	_mapping_overlay.visible = true
	_refresh_mapping_prompt()
	if SoundManager:
		SoundManager.play_ui("menu_select")


func _refresh_mapping_prompt() -> void:
	if _mapping_prompt == null or _mapping == null:
		return
	_mapping_prompt.text = _mapping.current_prompt()
	if _mapping_status:
		_mapping_status.text = "%s   ·   %s\nB / X = skip this control   ·   Esc = cancel" % [
			_mapping.pad_name, _mapping.guid]


## Consumes raw pad events during a mapping walk. Keyboard is NOT bindable here — an SDL
## mapping describes a gamepad, and accepting a keypress would emit a token SDL ignores.
func _handle_mapping_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		var kc := (event as InputEventKey).keycode
		if kc == KEY_ESCAPE:
			_cancel_mapping()
			return
		if kc == KEY_X:
			_mapping.skip()
			_advance_mapping()
			return
		return
	if event is InputEventJoypadButton and not (event as InputEventJoypadButton).pressed:
		return
	if _mapping.record(event):
		_advance_mapping()


func _advance_mapping() -> void:
	if _mapping.is_complete():
		_finish_mapping()
		return
	_refresh_mapping_prompt()


## Writes the captured mapping to user:// and registers it live, so the pad is correct in this
## session rather than only after a restart. Refuses to persist an incomplete mapping — SDL
## would accept it silently and then report the wrong physical controls.
func _finish_mapping() -> void:
	var mapping: String = _mapping.build()
	if mapping == "":
		var missing: Array = _mapping.missing_required()
		_show_flash("Incomplete — missing %s. Nothing saved." % ", ".join(missing))
		_cancel_mapping()
		return
	Input.add_joy_mapping(mapping, true)
	var saved := _append_user_mapping(mapping)
	_cancel_mapping()
	refresh_device_label()
	_update_all_labels()
	_show_flash("Mapped. %s" % ("Saved for next launch." if saved else "NOT saved — see log."))


## Appends to the captured-mappings file, replacing any entry for the same GUID so recapturing
## a pad corrects it rather than stacking duplicates SDL resolves by order.
func _append_user_mapping(mapping: String) -> bool:
	var CM = load("res://src/input/ControllerMappings.gd")
	var path: String = CM.USER_MAPPINGS_PATH
	var entries: Array = []
	if FileAccess.file_exists(path):
		var rf := FileAccess.open(path, FileAccess.READ)
		if rf:
			var parsed = JSON.parse_string(rf.get_as_text())
			if parsed is Array:
				entries = parsed
	var guid: String = mapping.split(",")[0]
	var kept: Array = []
	for e in entries:
		if e is String and e.split(",")[0] != guid:
			kept.append(e)
	kept.append(mapping)
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("input"):
		dir.make_dir("input")
	var wf := FileAccess.open(path, FileAccess.WRITE)
	if wf == null:
		push_warning("[ControlsMenu] Could not write %s (error %d) — the captured mapping applies to this session only and will be lost on restart." % [path, FileAccess.get_open_error()])
		return false
	wf.store_string(JSON.stringify(kept, "\t"))
	wf.close()
	return true


func _cancel_mapping() -> void:
	_mapping = null
	if _mapping_overlay and is_instance_valid(_mapping_overlay):
		_mapping_overlay.visible = false


func _build_mapping_overlay() -> void:
	if _mapping_overlay and is_instance_valid(_mapping_overlay):
		return
	_mapping_overlay = Control.new()
	_mapping_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mapping_overlay.visible = false
	add_child(_mapping_overlay)

	var bg := ColorRect.new()
	bg.color = CAPTURE_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mapping_overlay.add_child(bg)

	var title := Label.new()
	title.text = "MAP THIS PAD"
	title.position = Vector2(size.x * 0.5 - 80, size.y * 0.32)
	title.add_theme_font_size_override("font_size", 18)
	_mapping_overlay.add_child(title)

	_mapping_prompt = Label.new()
	_mapping_prompt.position = Vector2(size.x * 0.5 - 240, size.y * 0.42)
	_mapping_prompt.size = Vector2(480, 30)
	_mapping_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mapping_prompt.add_theme_font_size_override("font_size", 15)
	_mapping_overlay.add_child(_mapping_prompt)

	_mapping_status = Label.new()
	_mapping_status.position = Vector2(size.x * 0.5 - 240, size.y * 0.52)
	_mapping_status.size = Vector2(480, 50)
	_mapping_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mapping_status.add_theme_font_size_override("font_size", 10)
	_mapping_status.add_theme_color_override("font_color", DISABLED_COLOR)
	_mapping_overlay.add_child(_mapping_status)


func _toggle_nintendo_mode() -> void:
	InputProfileManager.set_nintendo_mode(not InputProfileManager.nintendo_mode)
	_update_all_labels()
	refresh_device_label()
	if SoundManager:
		SoundManager.play_ui("menu_select")


func _update_conflict_display() -> void:
	if not _conflict_label:
		return
	var conflicts = InputProfileManager.detect_conflicts()
	if conflicts.is_empty():
		_conflict_label.text = "Conflicts: None"
		_conflict_label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.4))
	else:
		var parts = []
		for c in conflicts:
			var action_names = []
			for a in c["actions"]:
				action_names.append(InputProfileManager.ACTION_LABELS.get(a, a))
			parts.append("%s: %s" % [c["label"], " & ".join(action_names)])
		_conflict_label.text = "Conflicts: %s" % ", ".join(parts)
		_conflict_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))


func _show_flash(msg: String) -> void:
	if _flash_label:
		_flash_label.text = msg
		_flash_label.visible = true
		_flash_timer = 1.5


func _process(delta: float) -> void:
	# Flash message timer
	if _flash_timer > 0:
		_flash_timer -= delta
		if _flash_timer <= 0 and _flash_label:
			_flash_label.visible = false

	# Capture timeout
	if _capturing:
		_capture_timer -= delta
		# Update timer display
		var timer_label = _capture_overlay.get_node_or_null("CaptureBox/TimerLabel")
		if timer_label:
			timer_label.text = "%.1fs" % max(0, _capture_timer)
		if _capture_timer <= 0:
			_cancel_capture()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if _mapping != null:
		_handle_mapping_input(event)
		get_viewport().set_input_as_handled()
		return

	if _capturing:
		_handle_capture_input(event)
		return

	if _testing:
		_handle_test_input(event)
		return

	if event.is_action_pressed("ui_up") and not event.is_echo():
		selected_index = max(0, selected_index - 1)
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		selected_index = min(_item_count - 1, selected_index + 1)
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_left") and not event.is_echo():
		match selected_index:
			ROW_PROFILE: _cycle_profile(-1)
			ROW_NINTENDO: _toggle_nintendo_mode()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right") and not event.is_echo():
		match selected_index:
			ROW_PROFILE: _cycle_profile(1)
			ROW_NINTENDO: _toggle_nintendo_mode()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_activate_row()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close_menu()
		get_viewport().set_input_as_handled()


func _cycle_profile(delta: int) -> void:
	InputProfileManager.cycle_profile(delta)
	_update_all_labels()
	if SoundManager:
		SoundManager.play_ui("menu_move")


func _activate_row() -> void:
	if selected_index == ROW_PROFILE:
		# Profile row - cycle forward on A press
		_cycle_profile(1)
		return

	if selected_index == ROW_NINTENDO:
		_toggle_nintendo_mode()
		return

	if selected_index == _row_reset:
		# Reset to default
		InputProfileManager.reset_custom_to_preset()
		_update_all_labels()
		if SoundManager:
			SoundManager.play_ui("menu_select")
		_show_flash("Reset to defaults")
		return

	if selected_index == _row_test:
		# Test Buttons diagnostic
		_start_test()
		return

	if selected_index == _row_map_pad:
		_start_pad_mapping()
		return

	var action_idx = selected_index - ROW_ACTION_FIRST
	if action_idx < 0 or action_idx >= InputProfileManager.REMAPPABLE_ACTIONS.size():
		return

	# Only allow remapping in Custom profile
	if InputProfileManager.active_profile != "Custom":
		_show_flash("Switch to Custom profile to remap")
		if SoundManager:
			SoundManager.play_ui("menu_move")
		return

	_start_capture(InputProfileManager.REMAPPABLE_ACTIONS[action_idx])


func _start_capture(action: String) -> void:
	_capturing = true
	_capture_action = action
	_capture_timer = CAPTURE_TIMEOUT
	_capture_overlay.visible = true
	var prompt = _capture_overlay.get_node_or_null("CaptureBox/CapturePrompt")
	if prompt:
		var label = InputProfileManager.ACTION_LABELS.get(action, action)
		prompt.text = "Remap '%s' — press a button..." % label
	if SoundManager:
		SoundManager.play_ui("menu_select")


func _cancel_capture() -> void:
	_capturing = false
	_capture_action = ""
	_capture_overlay.visible = false


func _handle_capture_input(event: InputEvent) -> void:
	# Cancel on B/ui_cancel key press
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_X or event.keycode == KEY_ESCAPE:
			_cancel_capture()
			get_viewport().set_input_as_handled()
			return

	# Cancel on B button (button 0 = A/South = SNES B = ui_cancel)
	if event is InputEventJoypadButton and event.pressed:
		# Button 0 always cancels capture (consistent with SNES B = cancel)
		if event.button_index == 0:
			_cancel_capture()
			if SoundManager:
				SoundManager.play_ui("menu_close")
			get_viewport().set_input_as_handled()
			return

		# Any other button = capture it
		var btn = event.button_index
		InputProfileManager.set_custom_binding(_capture_action, [btn])
		_cancel_capture()
		_update_all_labels()
		if SoundManager:
			SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()
		return

	# Consume all other input during capture
	if event is InputEventJoypadMotion or event is InputEventKey:
		get_viewport().set_input_as_handled()


func _on_row_click(index: int) -> void:
	selected_index = index
	_update_selection()
	_activate_row()


func _on_row_hover(index: int) -> void:
	if index != selected_index:
		selected_index = index
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")


func _close_menu() -> void:
	if SoundManager:
		SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
