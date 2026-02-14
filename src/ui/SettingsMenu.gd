extends Control
class_name SettingsMenu

## Settings Menu - Game settings including encounter rate selector

signal closed()
signal settings_changed(setting: String, value: Variant)
signal quit_to_title()

## Encounter rate presets (default 100%)
const ENCOUNTER_PRESETS = [0.0, 0.25, 0.50, 0.75, 1.0, 1.5, 2.0]
const ENCOUNTER_LABELS = ["0", "25", "50", "75", "100", "150", "200"]  # % shown in title

## Volume presets (0-100%)
const VOLUME_PRESETS = [0, 25, 50, 75, 100]
const VOLUME_LABELS = ["0", "25", "50", "75", "100"]

## Battle speed presets
const BATTLE_SPEED_PRESETS = [0.25, 0.5, 1.0, 2.0, 4.0]
const BATTLE_SPEED_LABELS = ["0.25x", "0.5x", "1x", "2x", "4x"]

## Text speed presets
const TEXT_SPEED_PRESETS = ["slow", "normal", "fast", "instant"]
const TEXT_SPEED_LABELS = ["Slow", "Normal", "Fast", "Instant"]

## Current settings
var encounter_rate: float = 1.0  # Default 100%
var encounter_preset_index: int = 4  # Index into ENCOUNTER_PRESETS (100%)
var debug_log_enabled: bool = true  # Default on
var music_volume: int = 100  # 0-100
var music_volume_index: int = 4
var sfx_volume: int = 100  # 0-100
var sfx_volume_index: int = 4
var battle_speed: float = 1.0
var battle_speed_index: int = 2
var text_speed: String = "normal"
var text_speed_index: int = 1

## UI State
var selected_index: int = 0
var _settings_items: Array = []

## Style
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_LIGHT = Color(0.7, 0.7, 0.85)
const BORDER_SHADOW = Color(0.25, 0.25, 0.4)
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const OPTION_BG = Color(0.15, 0.15, 0.2)
const OPTION_SELECTED = Color(0.3, 0.5, 0.8)


func _ready() -> void:
	# Load current settings from GameState
	if GameState:
		if "encounter_rate_multiplier" in GameState:
			encounter_rate = GameState.encounter_rate_multiplier
			encounter_preset_index = _find_closest_preset(encounter_rate)
		if "debug_log_enabled" in GameState:
			debug_log_enabled = GameState.debug_log_enabled
		if "music_volume" in GameState:
			music_volume = GameState.music_volume
			music_volume_index = _find_volume_preset(music_volume)
		if "sfx_volume" in GameState:
			sfx_volume = GameState.sfx_volume
			sfx_volume_index = _find_volume_preset(sfx_volume)
		if "default_battle_speed" in GameState:
			battle_speed = GameState.default_battle_speed
			battle_speed_index = _find_battle_speed_preset(battle_speed)
		if "text_speed" in GameState:
			text_speed = GameState.text_speed
			text_speed_index = TEXT_SPEED_PRESETS.find(text_speed)
			if text_speed_index < 0:
				text_speed_index = 1
	_build_ui()


func _find_closest_preset(value: float) -> int:
	"""Find the closest preset index to the given value"""
	var best_index = 4  # Default to 100%
	var best_diff = 999.0
	for i in range(ENCOUNTER_PRESETS.size()):
		var diff = abs(ENCOUNTER_PRESETS[i] - value)
		if diff < best_diff:
			best_diff = diff
			best_index = i
	return best_index


func _find_volume_preset(value: int) -> int:
	"""Find the closest volume preset index"""
	var best_index = 4  # Default to 100
	var best_diff = 999
	for i in range(VOLUME_PRESETS.size()):
		var diff = abs(VOLUME_PRESETS[i] - value)
		if diff < best_diff:
			best_diff = diff
			best_index = i
	return best_index


func _find_battle_speed_preset(value: float) -> int:
	"""Find the closest battle speed preset index"""
	var best_index = 2  # Default to 1x
	var best_diff = 999.0
	for i in range(BATTLE_SPEED_PRESETS.size()):
		var diff = abs(BATTLE_SPEED_PRESETS[i] - value)
		if diff < best_diff:
			best_diff = diff
			best_index = i
	return best_index


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

	# Beveled retro border
	RetroPanel.add_border(panel, panel.size, BORDER_LIGHT, BORDER_SHADOW)

	# Title
	var title = Label.new()
	title.text = "SETTINGS"
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	panel.add_child(title)

	# Encounter Rate setting
	var encounter_item = _create_option_setting(
		"Encounter Rate (%)",
		"Controls random battle frequency",
		ENCOUNTER_LABELS,
		encounter_preset_index,
		0
	)
	encounter_item.position = Vector2(16, 48)
	panel.add_child(encounter_item)
	_settings_items.append({"control": encounter_item, "type": "option", "id": "encounter_rate"})

	# Debug Log toggle
	var debug_item = _create_toggle_setting(
		"Debug Log",
		"Show debug messages on screen",
		debug_log_enabled,
		1
	)
	debug_item.position = Vector2(16, 128)
	panel.add_child(debug_item)
	_settings_items.append({"control": debug_item, "type": "toggle", "id": "debug_log"})

	# Music Volume
	var music_item = _create_volume_setting(
		"Music Volume",
		"Background music volume",
		VOLUME_LABELS,
		music_volume_index,
		2
	)
	music_item.position = Vector2(16, 188)
	panel.add_child(music_item)
	_settings_items.append({"control": music_item, "type": "volume", "id": "music_volume"})

	# SFX Volume
	var sfx_item = _create_volume_setting(
		"SFX Volume",
		"Sound effects volume",
		VOLUME_LABELS,
		sfx_volume_index,
		3
	)
	sfx_item.position = Vector2(16, 248)
	panel.add_child(sfx_item)
	_settings_items.append({"control": sfx_item, "type": "volume", "id": "sfx_volume"})

	# Battle Speed Default
	var speed_item = _create_option_setting_small(
		"Battle Speed Default",
		"Default battle animation speed",
		BATTLE_SPEED_LABELS,
		battle_speed_index,
		4
	)
	speed_item.position = Vector2(16, 308)
	panel.add_child(speed_item)
	_settings_items.append({"control": speed_item, "type": "battle_speed", "id": "battle_speed"})

	# Text Speed
	var text_item = _create_option_setting_small(
		"Text Speed",
		"Dialogue text display speed",
		TEXT_SPEED_LABELS,
		text_speed_index,
		5
	)
	text_item.position = Vector2(16, 368)
	panel.add_child(text_item)
	_settings_items.append({"control": text_item, "type": "text_speed", "id": "text_speed"})

	# Quit to Title button
	var quit_item = _create_action_button(
		"Quit to Title",
		"Return to the title screen",
		6
	)
	quit_item.position = Vector2(16, 428)
	panel.add_child(quit_item)
	_settings_items.append({"control": quit_item, "type": "action", "id": "quit_to_title"})

	# Footer
	var footer = Label.new()
	footer.text = "←→: Adjust  A: Select  B: Back"
	footer.position = Vector2(16, panel.size.y - 32)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(footer)

	_update_selection()


func _create_option_setting(label_text: String, description: String, options: Array, current_index: int, index: int) -> Control:
	"""Create an option selector setting control"""
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

	# Description
	var desc = Label.new()
	desc.text = description
	desc.position = Vector2(8, 22)
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", DISABLED_COLOR)
	container.add_child(desc)

	# Options row
	var options_container = HBoxContainer.new()
	options_container.position = Vector2(8, 44)
	options_container.name = "OptionsContainer"
	container.add_child(options_container)

	for i in range(options.size()):
		var option_bg = ColorRect.new()
		option_bg.custom_minimum_size = Vector2(40, 24)  # Smaller boxes to fit all 7
		option_bg.color = OPTION_SELECTED if i == current_index else OPTION_BG
		option_bg.name = "OptionBG_%d" % i
		options_container.add_child(option_bg)

		var option_label = Label.new()
		option_label.text = options[i]
		option_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		option_label.size = Vector2(40, 24)
		option_label.position = Vector2(0, 0)
		option_label.add_theme_font_size_override("font_size", 10)  # Smaller font
		option_label.add_theme_color_override("font_color", Color.YELLOW if i == current_index else TEXT_COLOR)
		option_label.name = "OptionLabel_%d" % i
		option_bg.add_child(option_label)

		# Add spacing between options
		if i < options.size() - 1:
			var spacer = Control.new()
			spacer.custom_minimum_size = Vector2(2, 1)  # Less spacing
			options_container.add_child(spacer)

	return container


func _create_volume_setting(label_text: String, description: String, options: Array, current_index: int, index: int) -> Control:
	"""Create a volume slider setting control"""
	var container = Control.new()
	container.size = Vector2(400, 60)

	# Selection highlight
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if index == selected_index else Color.TRANSPARENT
	highlight.size = Vector2(400, 60)
	highlight.name = "Highlight"
	container.add_child(highlight)

	# Label
	var label = Label.new()
	label.text = label_text
	label.position = Vector2(8, 4)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	container.add_child(label)

	# Description
	var desc = Label.new()
	desc.text = description
	desc.position = Vector2(8, 22)
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", DISABLED_COLOR)
	container.add_child(desc)

	# Options row
	var options_container = HBoxContainer.new()
	options_container.position = Vector2(8, 38)
	options_container.name = "OptionsContainer"
	container.add_child(options_container)

	for i in range(options.size()):
		var option_bg = ColorRect.new()
		option_bg.custom_minimum_size = Vector2(50, 20)
		option_bg.color = OPTION_SELECTED if i == current_index else OPTION_BG
		option_bg.name = "OptionBG_%d" % i
		options_container.add_child(option_bg)

		var option_label = Label.new()
		option_label.text = options[i] + "%"
		option_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		option_label.size = Vector2(50, 20)
		option_label.add_theme_font_size_override("font_size", 10)
		option_label.add_theme_color_override("font_color", Color.YELLOW if i == current_index else TEXT_COLOR)
		option_label.name = "OptionLabel_%d" % i
		option_bg.add_child(option_label)

		if i < options.size() - 1:
			var spacer = Control.new()
			spacer.custom_minimum_size = Vector2(2, 1)
			options_container.add_child(spacer)

	return container


func _create_option_setting_small(label_text: String, description: String, options: Array, current_index: int, index: int) -> Control:
	"""Create a smaller option selector setting control"""
	var container = Control.new()
	container.size = Vector2(400, 60)

	# Selection highlight
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if index == selected_index else Color.TRANSPARENT
	highlight.size = Vector2(400, 60)
	highlight.name = "Highlight"
	container.add_child(highlight)

	# Label
	var label = Label.new()
	label.text = label_text
	label.position = Vector2(8, 4)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	container.add_child(label)

	# Description
	var desc = Label.new()
	desc.text = description
	desc.position = Vector2(8, 22)
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", DISABLED_COLOR)
	container.add_child(desc)

	# Options row
	var options_container = HBoxContainer.new()
	options_container.position = Vector2(8, 38)
	options_container.name = "OptionsContainer"
	container.add_child(options_container)

	for i in range(options.size()):
		var option_bg = ColorRect.new()
		option_bg.custom_minimum_size = Vector2(60, 20)
		option_bg.color = OPTION_SELECTED if i == current_index else OPTION_BG
		option_bg.name = "OptionBG_%d" % i
		options_container.add_child(option_bg)

		var option_label = Label.new()
		option_label.text = options[i]
		option_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		option_label.size = Vector2(60, 20)
		option_label.add_theme_font_size_override("font_size", 10)
		option_label.add_theme_color_override("font_color", Color.YELLOW if i == current_index else TEXT_COLOR)
		option_label.name = "OptionLabel_%d" % i
		option_bg.add_child(option_label)

		if i < options.size() - 1:
			var spacer = Control.new()
			spacer.custom_minimum_size = Vector2(2, 1)
			options_container.add_child(spacer)

	return container


func _create_toggle_setting(label_text: String, description: String, is_on: bool, index: int) -> Control:
	"""Create a toggle (on/off) setting control"""
	var container = Control.new()
	container.size = Vector2(400, 60)

	# Selection highlight
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if index == selected_index else Color.TRANSPARENT
	highlight.size = Vector2(400, 60)
	highlight.name = "Highlight"
	container.add_child(highlight)

	# Label
	var label = Label.new()
	label.text = label_text
	label.position = Vector2(8, 4)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	container.add_child(label)

	# Description
	var desc = Label.new()
	desc.text = description
	desc.position = Vector2(8, 22)
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", DISABLED_COLOR)
	container.add_child(desc)

	# Toggle display
	var toggle_container = HBoxContainer.new()
	toggle_container.position = Vector2(8, 40)
	toggle_container.name = "ToggleContainer"
	container.add_child(toggle_container)

	# OFF option
	var off_bg = ColorRect.new()
	off_bg.custom_minimum_size = Vector2(50, 20)
	off_bg.color = OPTION_BG if is_on else OPTION_SELECTED
	off_bg.name = "OffBG"
	toggle_container.add_child(off_bg)

	var off_label = Label.new()
	off_label.text = "OFF"
	off_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	off_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	off_label.size = Vector2(50, 20)
	off_label.add_theme_font_size_override("font_size", 11)
	off_label.add_theme_color_override("font_color", TEXT_COLOR if is_on else Color.YELLOW)
	off_label.name = "OffLabel"
	off_bg.add_child(off_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(4, 1)
	toggle_container.add_child(spacer)

	# ON option
	var on_bg = ColorRect.new()
	on_bg.custom_minimum_size = Vector2(50, 20)
	on_bg.color = OPTION_SELECTED if is_on else OPTION_BG
	on_bg.name = "OnBG"
	toggle_container.add_child(on_bg)

	var on_label = Label.new()
	on_label.text = "ON"
	on_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	on_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	on_label.size = Vector2(50, 20)
	on_label.add_theme_font_size_override("font_size", 11)
	on_label.add_theme_color_override("font_color", Color.YELLOW if is_on else TEXT_COLOR)
	on_label.name = "OnLabel"
	on_bg.add_child(on_label)

	return container


func _create_action_button(label_text: String, description: String, index: int) -> Control:
	"""Create an action button setting (press A to activate)"""
	var container = Control.new()
	container.size = Vector2(400, 50)

	# Selection highlight
	var highlight = ColorRect.new()
	highlight.color = SELECTED_COLOR if index == selected_index else Color.TRANSPARENT
	highlight.size = Vector2(400, 50)
	highlight.name = "Highlight"
	container.add_child(highlight)

	# Label
	var label = Label.new()
	label.text = label_text
	label.position = Vector2(8, 4)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))  # Reddish for quit action
	container.add_child(label)

	# Description
	var desc = Label.new()
	desc.text = description
	desc.position = Vector2(8, 22)
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", DISABLED_COLOR)
	container.add_child(desc)

	# Action hint
	var hint = Label.new()
	hint.text = "[Press A]"
	hint.position = Vector2(8, 36)
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color.YELLOW)
	hint.name = "ActionHint"
	container.add_child(hint)

	return container


func _update_toggle_display(index: int, is_on: bool) -> void:
	"""Update toggle visual"""
	if index >= _settings_items.size():
		return
	var item = _settings_items[index]
	var control = item["control"]

	var off_bg = control.get_node_or_null("ToggleContainer/OffBG")
	var on_bg = control.get_node_or_null("ToggleContainer/OnBG")
	var off_label = control.get_node_or_null("ToggleContainer/OffBG/OffLabel")
	var on_label = control.get_node_or_null("ToggleContainer/OnBG/OnLabel")

	if off_bg:
		off_bg.color = OPTION_BG if is_on else OPTION_SELECTED
	if on_bg:
		on_bg.color = OPTION_SELECTED if is_on else OPTION_BG
	if off_label:
		off_label.add_theme_color_override("font_color", TEXT_COLOR if is_on else Color.YELLOW)
	if on_label:
		on_label.add_theme_color_override("font_color", Color.YELLOW if is_on else TEXT_COLOR)


func _update_selection() -> void:
	"""Update visual selection state"""
	for i in range(_settings_items.size()):
		var item = _settings_items[i]
		var highlight = item["control"].get_node_or_null("Highlight")
		if highlight:
			highlight.color = SELECTED_COLOR if i == selected_index else Color.TRANSPARENT


func _update_option_display(index: int, option_index: int) -> void:
	"""Update option selector visual"""
	if index >= _settings_items.size():
		return
	var item = _settings_items[index]
	var control = item["control"]

	var options_container = control.get_node_or_null("OptionsContainer")
	if not options_container:
		return

	# Update all option backgrounds and labels
	for i in range(ENCOUNTER_PRESETS.size()):
		var bg = control.get_node_or_null("OptionsContainer/OptionBG_%d" % i)
		if bg:
			bg.color = OPTION_SELECTED if i == option_index else OPTION_BG
			var label = bg.get_node_or_null("OptionLabel_%d" % i)
			if label:
				label.add_theme_color_override("font_color", Color.YELLOW if i == option_index else TEXT_COLOR)


func _input(event: InputEvent) -> void:
	"""Handle settings input"""
	if not visible:
		return

	# Navigation - check echo to prevent rapid-fire when holding keys
	if event.is_action_pressed("ui_up") and not event.is_echo():
		selected_index = max(0, selected_index - 1)
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		selected_index = min(_settings_items.size() - 1, selected_index + 1)
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	# Adjust value - allow echo for left/right to make adjusting sliders easier
	elif event.is_action_pressed("ui_left"):
		_adjust_setting(-1)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right"):
		_adjust_setting(1)
		get_viewport().set_input_as_handled()

	# Confirm/Activate
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_activate_setting()
		get_viewport().set_input_as_handled()

	# Close
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close_settings()
		get_viewport().set_input_as_handled()


func _adjust_setting(delta: int) -> void:
	"""Adjust the currently selected setting"""
	if selected_index >= _settings_items.size():
		return

	var item = _settings_items[selected_index]
	if item["id"] == "encounter_rate":
		encounter_preset_index = clampi(encounter_preset_index + delta, 0, ENCOUNTER_PRESETS.size() - 1)
		encounter_rate = ENCOUNTER_PRESETS[encounter_preset_index]
		_update_option_display(selected_index, encounter_preset_index)
		_save_encounter_rate()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "debug_log":
		# Toggle on any left/right press
		debug_log_enabled = not debug_log_enabled
		_update_toggle_display(selected_index, debug_log_enabled)
		_save_debug_log_setting()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "music_volume":
		music_volume_index = clampi(music_volume_index + delta, 0, VOLUME_PRESETS.size() - 1)
		music_volume = VOLUME_PRESETS[music_volume_index]
		_update_volume_display(selected_index, music_volume_index)
		_save_music_volume()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "sfx_volume":
		sfx_volume_index = clampi(sfx_volume_index + delta, 0, VOLUME_PRESETS.size() - 1)
		sfx_volume = VOLUME_PRESETS[sfx_volume_index]
		_update_volume_display(selected_index, sfx_volume_index)
		_save_sfx_volume()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "battle_speed":
		battle_speed_index = clampi(battle_speed_index + delta, 0, BATTLE_SPEED_PRESETS.size() - 1)
		battle_speed = BATTLE_SPEED_PRESETS[battle_speed_index]
		_update_small_option_display(selected_index, battle_speed_index, BATTLE_SPEED_PRESETS.size())
		_save_battle_speed()
		if SoundManager:
			SoundManager.play_ui("menu_move")
	elif item["id"] == "text_speed":
		text_speed_index = clampi(text_speed_index + delta, 0, TEXT_SPEED_PRESETS.size() - 1)
		text_speed = TEXT_SPEED_PRESETS[text_speed_index]
		_update_small_option_display(selected_index, text_speed_index, TEXT_SPEED_PRESETS.size())
		_save_text_speed()
		if SoundManager:
			SoundManager.play_ui("menu_move")


func _save_encounter_rate() -> void:
	"""Save encounter rate to GameState"""
	if GameState:
		GameState.encounter_rate_multiplier = encounter_rate
	settings_changed.emit("encounter_rate", encounter_rate)
	DebugLogOverlay.log("[SETTINGS] Encounter rate set to %d%%" % int(encounter_rate * 100))


func _save_debug_log_setting() -> void:
	"""Save debug log setting to GameState and update overlay"""
	if GameState:
		GameState.debug_log_enabled = debug_log_enabled
	# Update the overlay visibility
	if DebugLogOverlay:
		DebugLogOverlay.set_enabled(debug_log_enabled)
	settings_changed.emit("debug_log", debug_log_enabled)
	print("[SETTINGS] Debug log %s" % ("enabled" if debug_log_enabled else "disabled"))


func _update_volume_display(index: int, option_index: int) -> void:
	"""Update volume selector visual"""
	if index >= _settings_items.size():
		return
	var item = _settings_items[index]
	var control = item["control"]

	for i in range(VOLUME_PRESETS.size()):
		var bg = control.get_node_or_null("OptionsContainer/OptionBG_%d" % i)
		if bg:
			bg.color = OPTION_SELECTED if i == option_index else OPTION_BG
			var label = bg.get_node_or_null("OptionLabel_%d" % i)
			if label:
				label.add_theme_color_override("font_color", Color.YELLOW if i == option_index else TEXT_COLOR)


func _update_small_option_display(index: int, option_index: int, count: int) -> void:
	"""Update small option selector visual"""
	if index >= _settings_items.size():
		return
	var item = _settings_items[index]
	var control = item["control"]

	for i in range(count):
		var bg = control.get_node_or_null("OptionsContainer/OptionBG_%d" % i)
		if bg:
			bg.color = OPTION_SELECTED if i == option_index else OPTION_BG
			var label = bg.get_node_or_null("OptionLabel_%d" % i)
			if label:
				label.add_theme_color_override("font_color", Color.YELLOW if i == option_index else TEXT_COLOR)


func _save_music_volume() -> void:
	"""Save music volume setting"""
	if GameState:
		GameState.music_volume = music_volume
	if SoundManager:
		SoundManager.set_music_volume(music_volume / 100.0)
	settings_changed.emit("music_volume", music_volume)
	print("[SETTINGS] Music volume set to %d%%" % music_volume)


func _save_sfx_volume() -> void:
	"""Save SFX volume setting"""
	if GameState:
		GameState.sfx_volume = sfx_volume
	if SoundManager:
		SoundManager.set_sfx_volume(sfx_volume / 100.0)
	settings_changed.emit("sfx_volume", sfx_volume)
	print("[SETTINGS] SFX volume set to %d%%" % sfx_volume)


func _save_battle_speed() -> void:
	"""Save battle speed default setting"""
	if GameState:
		GameState.default_battle_speed = battle_speed
	settings_changed.emit("battle_speed", battle_speed)
	print("[SETTINGS] Default battle speed set to %.2fx" % battle_speed)


func _save_text_speed() -> void:
	"""Save text speed setting"""
	if GameState:
		GameState.text_speed = text_speed
	settings_changed.emit("text_speed", text_speed)
	print("[SETTINGS] Text speed set to %s" % text_speed)


func _activate_setting() -> void:
	"""Activate the currently selected setting (for action buttons)"""
	if selected_index >= _settings_items.size():
		return

	var item = _settings_items[selected_index]
	if item["type"] == "action":
		if item["id"] == "quit_to_title":
			if SoundManager:
				SoundManager.play_ui("menu_select")
			quit_to_title.emit()
			queue_free()
	elif item["type"] == "toggle":
		# A button also toggles for convenience
		_adjust_setting(1)


func _close_settings() -> void:
	"""Close settings menu"""
	if SoundManager:
		SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
