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
var _flash_label: Label
var _flash_timer: float = 0.0

## Layout
const ITEM_COUNT = 9  # profile + 6 actions + reset + test buttons
const ROW_HEIGHT = 40
const ROW_START_Y = 48

## Style (matches SettingsMenu)
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_LIGHT = RetroPanel.BORDER_LIGHT
const BORDER_SHADOW = RetroPanel.BORDER_SHADOW
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const OPTION_SELECTED = Color(0.3, 0.5, 0.8)
const CAPTURE_BG = Color(0.0, 0.0, 0.0, 0.85)


func _ready() -> void:
	_build_ui()


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

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Gamepad button remapping"
	subtitle.position = Vector2(16, 30)
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", DISABLED_COLOR)
	_panel.add_child(subtitle)

	# Build rows
	var y = ROW_START_Y

	# Row 0: Profile selector
	_add_row(0, y, "Profile", _get_profile_display(), true)
	y += ROW_HEIGHT + 8

	# Rows 1-6: Remappable actions
	var row_idx = 1
	for action in InputProfileManager.REMAPPABLE_ACTIONS:
		var label_text = InputProfileManager.ACTION_LABELS.get(action, action)
		var btn_label = InputProfileManager.get_action_button_label(action)
		_add_row(row_idx, y, label_text, btn_label, false)
		_action_labels[action] = _highlight_refs[row_idx].get_meta("value_label")
		row_idx += 1
		y += ROW_HEIGHT

	# Row 7: Reset to Default
	y += 8
	_add_row(7, y, "Reset to Default", "", false, true)
	y += ROW_HEIGHT

	# Row 8: Test Buttons
	_add_row(8, y, "Test Buttons", "", false, true)

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

	# Footer
	var footer = Label.new()
	footer.text = "Left/Right: Profile  A: Remap  B: Back"
	footer.position = Vector2(16, _panel.size.y - 32)
	footer.add_theme_font_size_override("font_size", 12)
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
		# Dots + value on the right
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
		value.add_theme_font_size_override("font_size", 14)
		value.add_theme_color_override("font_color", OPTION_SELECTED)
		value.name = "ValueLabel"
		highlight.add_child(value)
		highlight.set_meta("value_label", value)

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
	# Update profile label
	if _highlight_refs.size() > 0:
		var val_label = _highlight_refs[0].get_meta("value_label") if _highlight_refs[0].has_meta("value_label") else null
		if val_label:
			val_label.text = _get_profile_display()

	# Update action labels
	for action in _action_labels:
		_action_labels[action].text = InputProfileManager.get_action_button_label(action)

	_update_conflict_display()


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
		var timer_label = _capture_overlay.get_node_or_null("*/TimerLabel")
		if timer_label:
			timer_label.text = "%.1fs" % max(0, _capture_timer)
		if _capture_timer <= 0:
			_cancel_capture()


func _input(event: InputEvent) -> void:
	if not visible:
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
		selected_index = min(ITEM_COUNT - 1, selected_index + 1)
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_left") and not event.is_echo():
		if selected_index == 0:
			_cycle_profile(-1)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right") and not event.is_echo():
		if selected_index == 0:
			_cycle_profile(1)
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
	if selected_index == 0:
		# Profile row - cycle forward on A press
		_cycle_profile(1)
		return

	if selected_index == 7:
		# Reset to default
		InputProfileManager.reset_custom_to_preset()
		_update_all_labels()
		if SoundManager:
			SoundManager.play_ui("menu_select")
		_show_flash("Reset to defaults")
		return

	if selected_index == 8:
		# Test Buttons diagnostic
		_start_test()
		return

	# Action rows (1-6) — remap
	var action_idx = selected_index - 1
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
	var prompt = _capture_overlay.get_node_or_null("*/CapturePrompt")
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
