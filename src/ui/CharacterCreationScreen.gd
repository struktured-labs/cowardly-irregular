extends Control
class_name CharacterCreationScreen

## CharacterCreationScreen - Full-screen UI for character customization
## Supports 4 party members with gamepad navigation

signal creation_complete(party_customizations: Array)
signal creation_skipped()

const CustomizationScript = preload("res://src/character/CharacterCustomization.gd")

## Current state
var current_character_index: int = 0
var current_option_index: int = 0
var party_customizations: Array = []  # Array of CharacterCustomization objects

## UI constants
const PANEL_WIDTH: int = 620
const PANEL_HEIGHT: int = 440
const OPTION_HEIGHT: int = 24
const MAX_NAME_LENGTH: int = 8

## Available options per character
const OPTIONS: Array[String] = [
	"name",
	"eye_shape",
	"eyebrow_style",
	"nose_shape",
	"mouth_style",
	"hair_style",
	"hair_color",
	"skin_tone",
	"personality",
	"starting_job_1",
	"starting_job_2"
]

## Letter grid for name input (classic FF style)
const NAME_CHARS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz0123456789"
const NAME_GRID_COLS: int = 13

## Job options
const AVAILABLE_JOBS: Array[String] = ["fighter", "white_mage", "black_mage", "thief"]

## UI elements
var _panel: Control = null
var _title_label: Label = null
var _character_tabs: HBoxContainer = null
var _options_container: VBoxContainer = null
var _preview_sprite: Control = null
var _confirm_button: Label = null
var _skip_button: Label = null
var _input_blocked: bool = false
var _name_editing: bool = false
var _name_grid: Control = null
var _name_cursor_x: int = 0
var _name_cursor_y: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Initialize with default party
	party_customizations = CustomizationScript.create_default_party_with_script(CustomizationScript)

	_build_ui()
	_update_display()

	# Block input briefly to prevent accidental selection
	_input_blocked = true
	await get_tree().create_timer(0.3).timeout
	_input_blocked = false


func _build_ui() -> void:
	"""Build the character creation UI"""
	# Dark background
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Main panel
	_panel = Control.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_panel.position = (get_viewport_rect().size - Vector2(PANEL_WIDTH, PANEL_HEIGHT)) / 2
	add_child(_panel)

	# Panel background
	var panel_bg = ColorRect.new()
	panel_bg.color = Color(0.12, 0.12, 0.18)
	panel_bg.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(panel_bg)

	# Border
	_add_border(_panel, Vector2(PANEL_WIDTH, PANEL_HEIGHT))

	# Title
	_title_label = Label.new()
	_title_label.text = "CHARACTER CREATION"
	_title_label.position = Vector2(20, 15)
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	_panel.add_child(_title_label)

	# Character tabs
	_character_tabs = HBoxContainer.new()
	_character_tabs.position = Vector2(20, 45)
	_character_tabs.add_theme_constant_override("separation", 10)
	_panel.add_child(_character_tabs)

	for i in range(4):
		var tab = Label.new()
		tab.text = party_customizations[i].name if i < party_customizations.size() else "Char %d" % (i + 1)
		tab.custom_minimum_size = Vector2(100, 24)
		tab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab.add_theme_font_size_override("font_size", 12)
		_character_tabs.add_child(tab)

	# Options container
	_options_container = VBoxContainer.new()
	_options_container.position = Vector2(20, 85)
	_options_container.add_theme_constant_override("separation", 4)
	_panel.add_child(_options_container)

	# Create option rows
	for option in OPTIONS:
		var row = _create_option_row(option)
		_options_container.add_child(row)

	# Preview area
	var preview_bg = ColorRect.new()
	preview_bg.color = Color(0.08, 0.08, 0.12)
	preview_bg.position = Vector2(400, 85)
	preview_bg.size = Vector2(180, 220)
	_panel.add_child(preview_bg)

	var preview_label = Label.new()
	preview_label.text = "PREVIEW"
	preview_label.position = Vector2(400, 85)
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.custom_minimum_size = Vector2(180, 20)
	preview_label.add_theme_font_size_override("font_size", 10)
	preview_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_panel.add_child(preview_label)

	_preview_sprite = Control.new()
	_preview_sprite.position = Vector2(450, 150)
	_panel.add_child(_preview_sprite)

	# Instructions
	var instructions = Label.new()
	instructions.text = "[↑↓] Option  [←→] Change  [Z/A] Next Char  [X/B] Back  [START] Confirm"
	instructions.position = Vector2(20, PANEL_HEIGHT - 60)
	instructions.add_theme_font_size_override("font_size", 10)
	instructions.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	_panel.add_child(instructions)

	# Confirm button
	_confirm_button = Label.new()
	_confirm_button.text = "[ START ADVENTURE ]"
	_confirm_button.position = Vector2(20, PANEL_HEIGHT - 35)
	_confirm_button.add_theme_font_size_override("font_size", 12)
	_confirm_button.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
	_panel.add_child(_confirm_button)

	# Skip button
	_skip_button = Label.new()
	_skip_button.text = "[ SKIP - Use Defaults ]"
	_skip_button.position = Vector2(300, PANEL_HEIGHT - 35)
	_skip_button.add_theme_font_size_override("font_size", 12)
	_skip_button.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_panel.add_child(_skip_button)


func _add_border(parent: Control, size: Vector2) -> void:
	"""Add retro-style border"""
	var border_color = Color(0.4, 0.4, 0.5)
	var thickness = 2

	# Top
	var top = ColorRect.new()
	top.color = border_color.lightened(0.2)
	top.position = Vector2(0, 0)
	top.size = Vector2(size.x, thickness)
	parent.add_child(top)

	# Bottom
	var bottom = ColorRect.new()
	bottom.color = border_color.darkened(0.2)
	bottom.position = Vector2(0, size.y - thickness)
	bottom.size = Vector2(size.x, thickness)
	parent.add_child(bottom)

	# Left
	var left = ColorRect.new()
	left.color = border_color.lightened(0.2)
	left.position = Vector2(0, 0)
	left.size = Vector2(thickness, size.y)
	parent.add_child(left)

	# Right
	var right = ColorRect.new()
	right.color = border_color.darkened(0.2)
	right.position = Vector2(size.x - thickness, 0)
	right.size = Vector2(thickness, size.y)
	parent.add_child(right)


func _create_option_row(option: String) -> Control:
	"""Create a single option row"""
	var row = Control.new()
	row.custom_minimum_size = Vector2(360, OPTION_HEIGHT)
	row.name = "Option_%s" % option

	# Label
	var label = Label.new()
	label.name = "Label"
	label.text = _get_option_label(option)
	label.position = Vector2(0, 4)
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)

	# Value
	var value = Label.new()
	value.name = "Value"
	value.text = ""
	value.position = Vector2(120, 4)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	value.custom_minimum_size = Vector2(200, 20)
	value.add_theme_font_size_override("font_size", 12)
	row.add_child(value)

	# Selection indicator
	var cursor = Label.new()
	cursor.name = "Cursor"
	cursor.text = "▶"
	cursor.position = Vector2(-15, 4)
	cursor.add_theme_font_size_override("font_size", 11)
	cursor.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	cursor.visible = false
	row.add_child(cursor)

	# Arrows for changing value
	var left_arrow = Label.new()
	left_arrow.name = "LeftArrow"
	left_arrow.text = "◀"
	left_arrow.position = Vector2(105, 4)
	left_arrow.add_theme_font_size_override("font_size", 10)
	left_arrow.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	left_arrow.visible = false
	row.add_child(left_arrow)

	var right_arrow = Label.new()
	right_arrow.name = "RightArrow"
	right_arrow.text = "▶"
	right_arrow.position = Vector2(300, 4)
	right_arrow.add_theme_font_size_override("font_size", 10)
	right_arrow.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	right_arrow.visible = false
	row.add_child(right_arrow)

	return row


func _get_option_label(option: String) -> String:
	"""Get display label for option"""
	match option:
		"name": return "Name:"
		"eye_shape": return "Eyes:"
		"eyebrow_style": return "Brows:"
		"nose_shape": return "Nose:"
		"mouth_style": return "Mouth:"
		"hair_style": return "Hair:"
		"hair_color": return "Color:"
		"skin_tone": return "Skin:"
		"personality": return "Nature:"
		"starting_job_1": return "Job 1:"
		"starting_job_2": return "Job 2:"
	return option.capitalize()


func _update_display() -> void:
	"""Update all display elements"""
	if party_customizations.size() == 0:
		return

	var current = party_customizations[current_character_index]

	# Update tabs
	for i in range(_character_tabs.get_child_count()):
		var tab = _character_tabs.get_child(i)
		var char_name = party_customizations[i].name if i < party_customizations.size() else "Char %d" % (i + 1)
		tab.text = char_name
		if i == current_character_index:
			tab.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
		else:
			tab.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))

	# Update options
	for i in range(_options_container.get_child_count()):
		if i >= OPTIONS.size():
			break  # Bounds check to prevent array out of bounds
		var row = _options_container.get_child(i)
		var option = OPTIONS[i]
		var value_label = row.get_node("Value")
		var cursor = row.get_node("Cursor")
		var left_arrow = row.get_node("LeftArrow")
		var right_arrow = row.get_node("RightArrow")

		value_label.text = _get_option_value(current, option)
		cursor.visible = (i == current_option_index)
		left_arrow.visible = (i == current_option_index)
		right_arrow.visible = (i == current_option_index)

		if i == current_option_index:
			value_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))
		else:
			value_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))

	# Update preview
	_update_preview(current)


func _get_option_value(custom, option: String) -> String:
	"""Get display value for option"""
	match option:
		"name":
			return custom.name
		"eye_shape":
			return CustomizationScript.get_eye_shape_name(custom.eye_shape)
		"eyebrow_style":
			return CustomizationScript.get_eyebrow_style_name(custom.eyebrow_style)
		"nose_shape":
			return CustomizationScript.get_nose_shape_name(custom.nose_shape)
		"mouth_style":
			return CustomizationScript.get_mouth_style_name(custom.mouth_style)
		"hair_style":
			return CustomizationScript.get_hair_style_name(custom.hair_style)
		"hair_color":
			return _get_color_name(custom.hair_color, CustomizationScript.HAIR_COLORS)
		"skin_tone":
			return _get_color_name(custom.skin_tone, CustomizationScript.SKIN_TONES)
		"personality":
			return "%s (%s)" % [
				CustomizationScript.get_personality_name(custom.personality),
				CustomizationScript.get_personality_description(custom.personality)
			]
		"starting_job_1":
			return custom.starting_jobs[0].capitalize() if custom.starting_jobs.size() > 0 else "None"
		"starting_job_2":
			return custom.starting_jobs[1].capitalize() if custom.starting_jobs.size() > 1 else "None"
	return ""


func _get_color_name(color: Color, presets: Array[Color]) -> String:
	"""Get name for a color from presets"""
	for i in range(presets.size()):
		if presets[i].is_equal_approx(color):
			if presets == CustomizationScript.HAIR_COLORS:
				match i:
					0: return "Black"
					1: return "Brown"
					2: return "Blonde"
					3: return "Red"
					4: return "Silver"
					5: return "Blue"
					6: return "Green"
					7: return "Pink"
			else:  # Skin tones
				match i:
					0: return "Light"
					1: return "Fair"
					2: return "Medium"
					3: return "Tan"
					4: return "Dark"
	return "Custom"


func _update_preview(custom) -> void:
	"""Update the character preview sprite with face details"""
	# Clear existing preview
	for child in _preview_sprite.get_children():
		child.queue_free()

	# Face base (oval shape approximation)
	var face = ColorRect.new()
	face.color = custom.skin_tone
	face.size = Vector2(56, 64)
	face.position = Vector2(-28, 0)
	_preview_sprite.add_child(face)

	# Hair (varies by style)
	var hair = ColorRect.new()
	hair.color = custom.hair_color
	match custom.hair_style:
		CustomizationScript.HairStyle.SHORT:
			hair.size = Vector2(60, 20)
			hair.position = Vector2(-30, -15)
		CustomizationScript.HairStyle.LONG:
			hair.size = Vector2(64, 45)
			hair.position = Vector2(-32, -20)
		CustomizationScript.HairStyle.SPIKY:
			hair.size = Vector2(70, 30)
			hair.position = Vector2(-35, -25)
		CustomizationScript.HairStyle.BRAIDED:
			hair.size = Vector2(58, 35)
			hair.position = Vector2(-29, -18)
		CustomizationScript.HairStyle.PONYTAIL:
			hair.size = Vector2(55, 25)
			hair.position = Vector2(-27, -18)
		CustomizationScript.HairStyle.MOHAWK:
			hair.size = Vector2(20, 40)
			hair.position = Vector2(-10, -35)
	_preview_sprite.add_child(hair)

	# Eyes (varies by shape)
	var eye_color = Color(0.2, 0.2, 0.3)
	var eye_left = ColorRect.new()
	var eye_right = ColorRect.new()
	eye_left.color = eye_color
	eye_right.color = eye_color
	match custom.eye_shape:
		CustomizationScript.EyeShape.NORMAL:
			eye_left.size = Vector2(8, 6)
			eye_right.size = Vector2(8, 6)
		CustomizationScript.EyeShape.NARROW:
			eye_left.size = Vector2(10, 3)
			eye_right.size = Vector2(10, 3)
		CustomizationScript.EyeShape.WIDE:
			eye_left.size = Vector2(10, 8)
			eye_right.size = Vector2(10, 8)
		CustomizationScript.EyeShape.CLOSED:
			eye_left.size = Vector2(10, 2)
			eye_right.size = Vector2(10, 2)
	eye_left.position = Vector2(-20, 18)
	eye_right.position = Vector2(6, 18)
	_preview_sprite.add_child(eye_left)
	_preview_sprite.add_child(eye_right)

	# Eyebrows (varies by style)
	var brow_color = custom.hair_color.darkened(0.3)
	var brow_left = ColorRect.new()
	var brow_right = ColorRect.new()
	brow_left.color = brow_color
	brow_right.color = brow_color
	match custom.eyebrow_style:
		CustomizationScript.EyebrowStyle.NORMAL:
			brow_left.size = Vector2(10, 2)
			brow_right.size = Vector2(10, 2)
		CustomizationScript.EyebrowStyle.THICK:
			brow_left.size = Vector2(12, 4)
			brow_right.size = Vector2(12, 4)
		CustomizationScript.EyebrowStyle.THIN:
			brow_left.size = Vector2(10, 1)
			brow_right.size = Vector2(10, 1)
		CustomizationScript.EyebrowStyle.ARCHED:
			brow_left.size = Vector2(10, 2)
			brow_right.size = Vector2(10, 2)
	brow_left.position = Vector2(-21, 12)
	brow_right.position = Vector2(5, 12)
	_preview_sprite.add_child(brow_left)
	_preview_sprite.add_child(brow_right)

	# Nose (varies by shape)
	var nose = ColorRect.new()
	nose.color = custom.skin_tone.darkened(0.15)
	match custom.nose_shape:
		CustomizationScript.NoseShape.NORMAL:
			nose.size = Vector2(6, 10)
		CustomizationScript.NoseShape.SMALL:
			nose.size = Vector2(4, 6)
		CustomizationScript.NoseShape.POINTED:
			nose.size = Vector2(5, 12)
		CustomizationScript.NoseShape.BROAD:
			nose.size = Vector2(10, 8)
	nose.position = Vector2(-nose.size.x / 2, 28)
	_preview_sprite.add_child(nose)

	# Mouth (varies by style)
	var mouth = ColorRect.new()
	match custom.mouth_style:
		CustomizationScript.MouthStyle.NEUTRAL:
			mouth.color = Color(0.6, 0.3, 0.3)
			mouth.size = Vector2(12, 3)
		CustomizationScript.MouthStyle.SMILE:
			mouth.color = Color(0.7, 0.4, 0.4)
			mouth.size = Vector2(16, 4)
		CustomizationScript.MouthStyle.FROWN:
			mouth.color = Color(0.5, 0.25, 0.25)
			mouth.size = Vector2(14, 3)
		CustomizationScript.MouthStyle.SMIRK:
			mouth.color = Color(0.65, 0.35, 0.35)
			mouth.size = Vector2(10, 3)
	mouth.position = Vector2(-mouth.size.x / 2, 45)
	_preview_sprite.add_child(mouth)

	# Name under preview
	var name_label = Label.new()
	name_label.text = custom.name
	name_label.position = Vector2(-40, 75)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(80, 20)
	name_label.add_theme_font_size_override("font_size", 12)
	_preview_sprite.add_child(name_label)

	# Job info
	var job_label = Label.new()
	job_label.text = "%s / %s" % [
		custom.starting_jobs[0].capitalize() if custom.starting_jobs.size() > 0 else "",
		custom.starting_jobs[1].capitalize() if custom.starting_jobs.size() > 1 else ""
	]
	job_label.position = Vector2(-50, 95)
	job_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	job_label.custom_minimum_size = Vector2(100, 20)
	job_label.add_theme_font_size_override("font_size", 10)
	job_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	_preview_sprite.add_child(job_label)


func _input(event: InputEvent) -> void:
	if _input_blocked:
		return

	# Name editing mode
	if _name_editing:
		_handle_name_input(event)
		return

	# Navigation - check echo to prevent rapid-fire when holding keys
	if event.is_action_pressed("ui_up") and not event.is_echo():
		current_option_index = (current_option_index - 1) if current_option_index > 0 else OPTIONS.size() - 1
		SoundManager.play_ui("menu_move")
		_update_display()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		current_option_index = (current_option_index + 1) % OPTIONS.size()
		SoundManager.play_ui("menu_move")
		_update_display()
		get_viewport().set_input_as_handled()

	# Allow echo on left/right for faster option cycling
	elif event.is_action_pressed("ui_left"):
		_change_option(-1)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right"):
		_change_option(1)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		if OPTIONS[current_option_index] == "name":
			_start_name_editing()
		else:
			_next_character()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_previous_character()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_menu") and not event.is_echo():  # Start button
		_confirm_creation()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_TAB:
		_skip_creation()
		get_viewport().set_input_as_handled()


func _change_option(direction: int) -> void:
	"""Change the current option value"""
	var current = party_customizations[current_character_index]
	var option = OPTIONS[current_option_index]

	match option:
		"name":
			_start_name_editing()

		"eye_shape":
			var shapes = CustomizationScript.EyeShape.values()
			if shapes.size() > 0:
				var idx = max(0, shapes.find(current.eye_shape))
				idx = (idx + direction) % shapes.size()
				if idx < 0: idx = shapes.size() - 1
				current.eye_shape = shapes[idx]

		"eyebrow_style":
			var styles = CustomizationScript.EyebrowStyle.values()
			if styles.size() > 0:
				var idx = max(0, styles.find(current.eyebrow_style))
				idx = (idx + direction) % styles.size()
				if idx < 0: idx = styles.size() - 1
				current.eyebrow_style = styles[idx]

		"nose_shape":
			var shapes = CustomizationScript.NoseShape.values()
			if shapes.size() > 0:
				var idx = max(0, shapes.find(current.nose_shape))
				idx = (idx + direction) % shapes.size()
				if idx < 0: idx = shapes.size() - 1
				current.nose_shape = shapes[idx]

		"mouth_style":
			var styles = CustomizationScript.MouthStyle.values()
			if styles.size() > 0:
				var idx = max(0, styles.find(current.mouth_style))
				idx = (idx + direction) % styles.size()
				if idx < 0: idx = styles.size() - 1
				current.mouth_style = styles[idx]

		"hair_style":
			var styles = CustomizationScript.HairStyle.values()
			if styles.size() > 0:
				var idx = max(0, styles.find(current.hair_style))
				idx = (idx + direction) % styles.size()
				if idx < 0: idx = styles.size() - 1
				current.hair_style = styles[idx]

		"hair_color":
			var colors = CustomizationScript.HAIR_COLORS
			if colors.size() > 0:
				var idx = _find_color_index(current.hair_color, colors)
				idx = (idx + direction) % colors.size()
				if idx < 0: idx = colors.size() - 1
				current.hair_color = colors[idx]

		"skin_tone":
			var tones = CustomizationScript.SKIN_TONES
			if tones.size() > 0:
				var idx = _find_color_index(current.skin_tone, tones)
				idx = (idx + direction) % tones.size()
				if idx < 0: idx = tones.size() - 1
				current.skin_tone = tones[idx]

		"personality":
			var types = CustomizationScript.Personality.values()
			if types.size() > 0:
				var idx = max(0, types.find(current.personality))
				idx = (idx + direction) % types.size()
				if idx < 0: idx = types.size() - 1
				current.personality = types[idx]

		"starting_job_1":
			if AVAILABLE_JOBS.size() > 0:
				var idx = max(0, AVAILABLE_JOBS.find(current.starting_jobs[0]))
				idx = (idx + direction) % AVAILABLE_JOBS.size()
				if idx < 0: idx = AVAILABLE_JOBS.size() - 1
				current.starting_jobs[0] = AVAILABLE_JOBS[idx]

		"starting_job_2":
			if AVAILABLE_JOBS.size() > 0:
				var idx = max(0, AVAILABLE_JOBS.find(current.starting_jobs[1]))
				idx = (idx + direction) % AVAILABLE_JOBS.size()
				if idx < 0: idx = AVAILABLE_JOBS.size() - 1
				current.starting_jobs[1] = AVAILABLE_JOBS[idx]

	SoundManager.play_ui("menu_select")
	_update_display()


func _find_color_index(color: Color, presets: Array[Color]) -> int:
	"""Find index of color in presets"""
	for i in range(presets.size()):
		if presets[i].is_equal_approx(color):
			return i
	return 0


func _start_name_editing() -> void:
	"""Start editing name with letter grid (FF-style)"""
	_name_editing = true
	_name_cursor_x = 0
	_name_cursor_y = 0
	_show_name_grid()
	SoundManager.play_ui("menu_select")


func _show_name_grid() -> void:
	"""Show the letter selection grid"""
	if _name_grid:
		_name_grid.queue_free()

	_name_grid = Control.new()
	_name_grid.position = Vector2(20, 320)
	_panel.add_child(_name_grid)

	# Background - solid color for readability
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.15, 1.0)
	bg.size = Vector2(560, 100)
	_name_grid.add_child(bg)

	# Border for visual clarity
	var border = ColorRect.new()
	border.color = Color(0.4, 0.35, 0.5)
	border.size = Vector2(564, 104)
	border.position = Vector2(-2, -2)
	border.z_index = -1
	_name_grid.add_child(border)

	# Current name display
	var name_label = Label.new()
	name_label.name = "NameDisplay"
	name_label.text = "Name: " + party_customizations[current_character_index].name + "_"
	name_label.position = Vector2(10, 5)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	_name_grid.add_child(name_label)

	# Letter grid
	var grid_start_y = 30
	var rows = (NAME_CHARS.length() + NAME_GRID_COLS - 1) / NAME_GRID_COLS
	for row_idx in range(rows):
		for col_idx in range(NAME_GRID_COLS):
			var char_idx = row_idx * NAME_GRID_COLS + col_idx
			if char_idx >= NAME_CHARS.length():
				break
			var c = NAME_CHARS[char_idx]
			var letter = Label.new()
			letter.name = "Char_%d_%d" % [row_idx, col_idx]
			letter.text = c if c != " " else "_"
			letter.position = Vector2(15 + col_idx * 22, grid_start_y + row_idx * 18)
			letter.add_theme_font_size_override("font_size", 12)
			_name_grid.add_child(letter)

	# Special buttons: [DEL] [OK]
	var del_btn = Label.new()
	del_btn.name = "DelBtn"
	del_btn.text = "[DEL]"
	del_btn.position = Vector2(320, grid_start_y + 54)
	del_btn.add_theme_font_size_override("font_size", 12)
	_name_grid.add_child(del_btn)

	var ok_btn = Label.new()
	ok_btn.name = "OkBtn"
	ok_btn.text = "[OK]"
	ok_btn.position = Vector2(380, grid_start_y + 54)
	ok_btn.add_theme_font_size_override("font_size", 12)
	_name_grid.add_child(ok_btn)

	# Instructions
	var hint = Label.new()
	hint.text = "[D-pad] Move  [A/Z] Select  [B/X] Delete  [Start] Done"
	hint.position = Vector2(10, 85)
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	_name_grid.add_child(hint)

	_update_name_grid_cursor()


func _update_name_grid_cursor() -> void:
	"""Update cursor highlighting in name grid"""
	if not _name_grid:
		return

	var rows = (NAME_CHARS.length() + NAME_GRID_COLS - 1) / NAME_GRID_COLS

	# Reset all letter colors
	for row_idx in range(rows):
		for col_idx in range(NAME_GRID_COLS):
			var letter = _name_grid.get_node_or_null("Char_%d_%d" % [row_idx, col_idx])
			if letter:
				letter.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))

	# Highlight special buttons
	var del_btn = _name_grid.get_node_or_null("DelBtn")
	var ok_btn = _name_grid.get_node_or_null("OkBtn")
	if del_btn:
		del_btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	if ok_btn:
		ok_btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))

	# Highlight current selection
	if _name_cursor_y < rows:
		var letter = _name_grid.get_node_or_null("Char_%d_%d" % [_name_cursor_y, _name_cursor_x])
		if letter:
			letter.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))
	elif _name_cursor_y == rows:
		# Special button row
		if _name_cursor_x == 0 and del_btn:
			del_btn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		elif _name_cursor_x == 1 and ok_btn:
			ok_btn.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))


func _handle_name_input(event: InputEvent) -> void:
	"""Handle gamepad/keyboard input for name grid"""
	var current = party_customizations[current_character_index]
	var rows = (NAME_CHARS.length() + NAME_GRID_COLS - 1) / NAME_GRID_COLS
	var max_rows = rows + 1  # +1 for special buttons row

	if event.is_action_pressed("ui_up"):
		_name_cursor_y = (_name_cursor_y - 1) if _name_cursor_y > 0 else max_rows - 1
		if _name_cursor_y == rows:
			_name_cursor_x = mini(_name_cursor_x, 1)  # Only 2 buttons
		SoundManager.play_ui("menu_move")
		_update_name_grid_cursor()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down"):
		_name_cursor_y = (_name_cursor_y + 1) % max_rows
		if _name_cursor_y == rows:
			_name_cursor_x = mini(_name_cursor_x, 1)  # Only 2 buttons
		SoundManager.play_ui("menu_move")
		_update_name_grid_cursor()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_left"):
		if _name_cursor_y < rows:
			_name_cursor_x = (_name_cursor_x - 1) if _name_cursor_x > 0 else NAME_GRID_COLS - 1
		else:
			_name_cursor_x = (_name_cursor_x - 1) if _name_cursor_x > 0 else 1
		SoundManager.play_ui("menu_move")
		_update_name_grid_cursor()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right"):
		if _name_cursor_y < rows:
			_name_cursor_x = (_name_cursor_x + 1) % NAME_GRID_COLS
		else:
			_name_cursor_x = (_name_cursor_x + 1) % 2
		SoundManager.play_ui("menu_move")
		_update_name_grid_cursor()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept"):
		if _name_cursor_y < rows:
			# Add letter
			var char_idx = _name_cursor_y * NAME_GRID_COLS + _name_cursor_x
			if char_idx < NAME_CHARS.length() and current.name.length() < MAX_NAME_LENGTH:
				current.name += NAME_CHARS[char_idx]
				_update_name_display_in_grid()
				SoundManager.play_ui("menu_select")
		elif _name_cursor_y == rows:
			if _name_cursor_x == 0:
				# DEL
				if current.name.length() > 0:
					current.name = current.name.substr(0, current.name.length() - 1)
					_update_name_display_in_grid()
					SoundManager.play_ui("menu_cancel")
			else:
				# OK
				_close_name_grid()
				SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel"):
		# Delete last character
		if current.name.length() > 0:
			current.name = current.name.substr(0, current.name.length() - 1)
			_update_name_display_in_grid()
			SoundManager.play_ui("menu_cancel")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_menu"):
		# Start = done
		_close_name_grid()
		SoundManager.play_ui("menu_select")
		get_viewport().set_input_as_handled()


func _update_name_display_in_grid() -> void:
	"""Update the name display in the grid"""
	if not _name_grid:
		return
	var name_label = _name_grid.get_node_or_null("NameDisplay")
	if name_label:
		name_label.text = "Name: " + party_customizations[current_character_index].name + "_"


func _close_name_grid() -> void:
	"""Close the name editing grid"""
	_name_editing = false
	if _name_grid:
		_name_grid.queue_free()
		_name_grid = null
	_update_display()


func _next_character() -> void:
	"""Move to next character"""
	if current_character_index < 3:
		current_character_index += 1
		current_option_index = 0
		SoundManager.play_ui("menu_expand")
		_update_display()
	else:
		_confirm_creation()


func _previous_character() -> void:
	"""Move to previous character"""
	if current_character_index > 0:
		current_character_index -= 1
		current_option_index = 0
		SoundManager.play_ui("menu_cancel")
		_update_display()


func _confirm_creation() -> void:
	"""Confirm and complete character creation"""
	SoundManager.play_ui("menu_select")
	creation_complete.emit(party_customizations)
	queue_free()


func _skip_creation() -> void:
	"""Skip creation and use defaults"""
	SoundManager.play_ui("menu_cancel")
	creation_skipped.emit()
	queue_free()
