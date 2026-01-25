extends Control
class_name SettingsMenu

## Settings Menu - Game settings including encounter rate slider

signal closed()
signal settings_changed(setting: String, value: Variant)

## Current settings
var encounter_rate: float = 1.0  # 0.0 to 1.0 (0% to 100%)

## UI State
var selected_index: int = 0
var _settings_items: Array = []

## Style
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_COLOR = Color(0.4, 0.4, 0.5)
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const SLIDER_BG = Color(0.15, 0.15, 0.2)
const SLIDER_FILL = Color(0.3, 0.5, 0.8)


func _ready() -> void:
	# Load current encounter rate from GameState
	if GameState and "encounter_rate_multiplier" in GameState:
		encounter_rate = GameState.encounter_rate_multiplier
	_build_ui()


func _build_ui() -> void:
	"""Build the settings UI"""
	for child in get_children():
		child.queue_free()
	_settings_items.clear()

	# Full screen background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main panel
	var panel = Control.new()
	panel.position = Vector2(size.x * 0.2, size.y * 0.15)
	panel.size = Vector2(size.x * 0.6, size.y * 0.7)
	add_child(panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)

	# Title
	var title = Label.new()
	title.text = "SETTINGS"
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	# Encounter Rate setting
	var encounter_item = _create_slider_setting(
		"Encounter Rate",
		"Controls random battle frequency (0% = no battles)",
		encounter_rate,
		0
	)
	encounter_item.position = Vector2(16, 48)
	panel.add_child(encounter_item)
	_settings_items.append({"control": encounter_item, "type": "slider", "id": "encounter_rate"})

	# Future settings placeholders
	var sound_label = Label.new()
	sound_label.text = "More settings coming soon..."
	sound_label.position = Vector2(16, 140)
	sound_label.add_theme_font_size_override("font_size", 12)
	sound_label.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(sound_label)

	# Footer
	var footer = Label.new()
	footer.text = "←→: Adjust  B: Back"
	footer.position = Vector2(16, panel.size.y - 32)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(footer)

	_update_selection()


func _create_slider_setting(label_text: String, description: String, value: float, index: int) -> Control:
	"""Create a slider setting control"""
	var container = Control.new()
	container.size = Vector2(400, 80)

	# Selection highlight
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if index == selected_index else Color.TRANSPARENT
	highlight.size = Vector2(400, 80)
	highlight.name = "Highlight"
	container.add_child(highlight)

	# Label
	var label = Label.new()
	label.text = label_text
	label.position = Vector2(8, 4)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	container.add_child(label)

	# Value display
	var value_label = Label.new()
	value_label.text = "%d%%" % int(value * 100)
	value_label.name = "ValueLabel"
	value_label.position = Vector2(350, 4)
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", Color.YELLOW)
	container.add_child(value_label)

	# Description
	var desc = Label.new()
	desc.text = description
	desc.position = Vector2(8, 22)
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", DISABLED_COLOR)
	container.add_child(desc)

	# Slider background
	var slider_bg = ColorRect.new()
	slider_bg.color = SLIDER_BG
	slider_bg.position = Vector2(8, 44)
	slider_bg.size = Vector2(380, 20)
	container.add_child(slider_bg)

	# Slider fill
	var slider_fill = ColorRect.new()
	slider_fill.color = SLIDER_FILL
	slider_fill.position = Vector2(8, 44)
	slider_fill.size = Vector2(380 * value, 20)
	slider_fill.name = "SliderFill"
	container.add_child(slider_fill)

	# Tick marks (0%, 25%, 50%, 75%, 100%)
	for i in range(5):
		var tick = ColorRect.new()
		tick.color = Color(0.5, 0.5, 0.5)
		tick.position = Vector2(8 + 380 * (i / 4.0) - 1, 42)
		tick.size = Vector2(2, 24)
		container.add_child(tick)

	return container


func _update_selection() -> void:
	"""Update visual selection state"""
	for i in range(_settings_items.size()):
		var item = _settings_items[i]
		var highlight = item["control"].get_node_or_null("Highlight")
		if highlight:
			highlight.color = SELECTED_COLOR if i == selected_index else Color.TRANSPARENT


func _update_slider_display(index: int, value: float) -> void:
	"""Update slider visual"""
	if index >= _settings_items.size():
		return
	var item = _settings_items[index]
	var control = item["control"]

	var value_label = control.get_node_or_null("ValueLabel")
	if value_label:
		value_label.text = "%d%%" % int(value * 100)

	var slider_fill = control.get_node_or_null("SliderFill")
	if slider_fill:
		slider_fill.size.x = 380 * value


func _input(event: InputEvent) -> void:
	"""Handle settings input"""
	if not visible:
		return

	# Navigation
	if event.is_action_pressed("ui_up"):
		selected_index = max(0, selected_index - 1)
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down"):
		selected_index = min(_settings_items.size() - 1, selected_index + 1)
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	# Adjust value
	elif event.is_action_pressed("ui_left"):
		_adjust_setting(-0.05)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right"):
		_adjust_setting(0.05)
		get_viewport().set_input_as_handled()

	# Close
	elif event.is_action_pressed("ui_cancel"):
		_close_settings()
		get_viewport().set_input_as_handled()


func _adjust_setting(delta: float) -> void:
	"""Adjust the currently selected setting"""
	if selected_index >= _settings_items.size():
		return

	var item = _settings_items[selected_index]
	if item["id"] == "encounter_rate":
		encounter_rate = clampf(encounter_rate + delta, 0.0, 1.0)
		_update_slider_display(selected_index, encounter_rate)
		_save_encounter_rate()
		if SoundManager:
			SoundManager.play_ui("menu_move")


func _save_encounter_rate() -> void:
	"""Save encounter rate to GameState"""
	if GameState:
		GameState.encounter_rate_multiplier = encounter_rate
	settings_changed.emit("encounter_rate", encounter_rate)


func _close_settings() -> void:
	"""Close settings menu"""
	if SoundManager:
		SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
