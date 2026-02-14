extends Control
class_name VirtualKeyboard

## Virtual Keyboard - Controller-friendly text input
## Used for naming profiles, characters, etc.
##
## Controller Mapping:
## - D-Pad: Navigate keys
## - A (Z): Press selected key
## - B (X): Backspace / Cancel
## - Start: Confirm
## - Select: Toggle case (lower/upper/symbols)

signal text_submitted(text: String)
signal cancelled()

## Current input text
var input_text: String = ""

## Maximum characters allowed
var max_length: int = 16

## Cursor position on keyboard grid
var cursor_row: int = 0
var cursor_col: int = 0

## Current character set (0=lower, 1=upper, 2=symbols)
var char_set: int = 0

## Visual references
var _title_label: Label
var _input_display: Label
var _key_grid: Control
var _help_label: Label
var _cursor_rect: ColorRect

## Keyboard layouts
const LAYOUTS = [
	# Lowercase
	["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"],
	["k", "l", "m", "n", "o", "p", "q", "r", "s", "t"],
	["u", "v", "w", "x", "y", "z", "0", "1", "2", "3"],
	["4", "5", "6", "7", "8", "9", " ", "⌫", "⇧", "OK"],
]

const LAYOUTS_UPPER = [
	# Uppercase
	["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"],
	["K", "L", "M", "N", "O", "P", "Q", "R", "S", "T"],
	["U", "V", "W", "X", "Y", "Z", "0", "1", "2", "3"],
	["4", "5", "6", "7", "8", "9", " ", "⌫", "⇧", "OK"],
]

const LAYOUTS_SYMBOLS = [
	# Symbols
	["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"],
	["-", "_", "=", "+", "[", "]", "{", "}", "|", "\\"],
	[";", ":", "'", "\"", ",", ".", "<", ">", "/", "?"],
	["`", "~", " ", " ", " ", " ", " ", "⌫", "⇧", "OK"],
]

## Styling
const BG_COLOR = Color(0.1, 0.1, 0.15, 0.95)
const KEY_COLOR = Color(0.2, 0.2, 0.25)
const KEY_HIGHLIGHT = Color(0.3, 0.4, 0.5)
const KEY_SPECIAL = Color(0.25, 0.35, 0.25)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const CURSOR_COLOR = Color(1.0, 1.0, 0.3, 0.5)

const KEY_SIZE = Vector2(40, 40)
const KEY_SPACING = 4


func _ready() -> void:
	_build_ui()


func setup(title: String, initial_text: String = "", max_chars: int = 16) -> void:
	"""Initialize keyboard with title and optional initial text"""
	max_length = max_chars
	input_text = initial_text.substr(0, max_length)
	if _title_label:
		_title_label.text = title
	_refresh_display()
	_refresh_keys()


func _build_ui() -> void:
	"""Build the keyboard UI"""
	# Full screen semi-transparent background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main container centered
	var container = Control.new()
	var container_width = KEY_SIZE.x * 10 + KEY_SPACING * 9 + 40
	var container_height = 200
	container.position = Vector2((size.x - container_width) / 2, (size.y - container_height) / 2)
	container.size = Vector2(container_width, container_height)
	add_child(container)

	# Panel background
	var panel = ColorRect.new()
	panel.color = Color(0.15, 0.15, 0.2)
	panel.position = Vector2(-20, -20)
	panel.size = Vector2(container_width + 40, container_height + 60)
	container.add_child(panel)

	# Border
	_add_border(panel)

	# Title
	_title_label = Label.new()
	_title_label.text = "Enter Name"
	_title_label.position = Vector2(0, -10)
	_title_label.size = Vector2(container_width, 24)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", TEXT_COLOR)
	container.add_child(_title_label)

	# Input display box
	var input_bg = ColorRect.new()
	input_bg.color = Color(0.05, 0.05, 0.1)
	input_bg.position = Vector2(0, 20)
	input_bg.size = Vector2(container_width, 32)
	container.add_child(input_bg)

	_input_display = Label.new()
	_input_display.text = ""
	_input_display.position = Vector2(8, 24)
	_input_display.size = Vector2(container_width - 16, 24)
	_input_display.add_theme_font_size_override("font_size", 18)
	_input_display.add_theme_color_override("font_color", Color.CYAN)
	container.add_child(_input_display)

	# Keyboard grid
	_key_grid = Control.new()
	_key_grid.position = Vector2(0, 60)
	container.add_child(_key_grid)

	# Create cursor highlight
	_cursor_rect = ColorRect.new()
	_cursor_rect.color = CURSOR_COLOR
	_cursor_rect.size = KEY_SIZE
	_key_grid.add_child(_cursor_rect)

	_refresh_keys()

	# Help text
	_help_label = Label.new()
	_help_label.text = "D-Pad:Move  A:Type  B:Back  Select:Case  Start:Done"
	_help_label.position = Vector2(0, container_height + 10)
	_help_label.size = Vector2(container_width, 20)
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_label.add_theme_font_size_override("font_size", 10)
	_help_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	container.add_child(_help_label)


func _add_border(panel: ColorRect) -> void:
	"""Add decorative border"""
	var border_color = Color(0.5, 0.5, 0.6)
	var border_width = 2

	# Top
	var top = ColorRect.new()
	top.color = border_color
	top.position = Vector2(0, 0)
	top.size = Vector2(panel.size.x, border_width)
	panel.add_child(top)

	# Left
	var left = ColorRect.new()
	left.color = border_color
	left.position = Vector2(0, 0)
	left.size = Vector2(border_width, panel.size.y)
	panel.add_child(left)

	# Bottom (darker)
	var bottom = ColorRect.new()
	bottom.color = border_color.darkened(0.3)
	bottom.position = Vector2(0, panel.size.y - border_width)
	bottom.size = Vector2(panel.size.x, border_width)
	panel.add_child(bottom)

	# Right (darker)
	var right = ColorRect.new()
	right.color = border_color.darkened(0.3)
	right.position = Vector2(panel.size.x - border_width, 0)
	right.size = Vector2(border_width, panel.size.y)
	panel.add_child(right)


func _refresh_keys() -> void:
	"""Refresh the keyboard display"""
	# Clear existing key labels (but not cursor)
	for child in _key_grid.get_children():
		if child != _cursor_rect:
			child.queue_free()

	var layout = _get_current_layout()

	for row in range(layout.size()):
		for col in range(layout[row].size()):
			var key_char = layout[row][col]
			var key_pos = Vector2(col * (KEY_SIZE.x + KEY_SPACING), row * (KEY_SIZE.y + KEY_SPACING))

			# Key background
			var key_bg = ColorRect.new()
			if key_char in ["⌫", "⇧", "OK"]:
				key_bg.color = KEY_SPECIAL
			else:
				key_bg.color = KEY_COLOR
			key_bg.position = key_pos
			key_bg.size = KEY_SIZE
			_key_grid.add_child(key_bg)

			# Key label
			var key_label = Label.new()
			key_label.text = key_char
			key_label.position = key_pos
			key_label.size = KEY_SIZE
			key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			key_label.add_theme_font_size_override("font_size", 16)
			key_label.add_theme_color_override("font_color", TEXT_COLOR)
			_key_grid.add_child(key_label)

	_update_cursor()


func _get_current_layout() -> Array:
	"""Get the current character layout based on char_set"""
	match char_set:
		0: return LAYOUTS
		1: return LAYOUTS_UPPER
		2: return LAYOUTS_SYMBOLS
		_: return LAYOUTS


func _refresh_display() -> void:
	"""Update the input text display"""
	if _input_display:
		# Show text with cursor
		var display_text = input_text
		if display_text.length() < max_length:
			display_text += "_"  # Cursor
		_input_display.text = display_text


func _update_cursor() -> void:
	"""Update cursor position"""
	if _cursor_rect:
		var pos = Vector2(
			cursor_col * (KEY_SIZE.x + KEY_SPACING),
			cursor_row * (KEY_SIZE.y + KEY_SPACING)
		)
		_cursor_rect.position = pos


func _input(event: InputEvent) -> void:
	"""Handle keyboard input"""
	if not visible:
		return

	var layout = _get_current_layout()
	if layout.is_empty() or layout[0].is_empty():
		return
	var max_row = layout.size() - 1
	var max_col = layout[0].size() - 1

	# Navigation - check echo to prevent rapid-fire when holding keys
	if event.is_action_pressed("ui_up") and not event.is_echo():
		cursor_row = (cursor_row - 1 + layout.size()) % layout.size()
		_update_cursor()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		cursor_row = (cursor_row + 1) % layout.size()
		_update_cursor()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_left") and not event.is_echo():
		cursor_col = (cursor_col - 1 + layout[0].size()) % layout[0].size()
		_update_cursor()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_right") and not event.is_echo():
		cursor_col = (cursor_col + 1) % layout[0].size()
		_update_cursor()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	# Press key (A button)
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_press_key()
		get_viewport().set_input_as_handled()

	# Backspace / Cancel (B button) - allow echo for backspace-like behavior
	elif event.is_action_pressed("ui_cancel"):
		if input_text.length() > 0:
			input_text = input_text.substr(0, input_text.length() - 1)
			_refresh_display()
			SoundManager.play_ui("menu_cancel")
		else:
			# Cancel if text is empty
			SoundManager.play_ui("menu_close")
			cancelled.emit()
		get_viewport().set_input_as_handled()

	# Toggle case (Select button / Tab key)
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK:
		char_set = (char_set + 1) % 3
		_refresh_keys()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		char_set = (char_set + 1) % 3
		_refresh_keys()
		SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	# Confirm (Start button)
	elif event.is_action_pressed("ui_menu"):  # Start
		_submit_text()
		get_viewport().set_input_as_handled()

	# Physical keyboard support
	elif event is InputEventKey and event.pressed and not event.echo:
		var key = event as InputEventKey
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			_submit_text()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_ESCAPE:
			SoundManager.play_ui("menu_close")
			cancelled.emit()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_BACKSPACE:
			if input_text.length() > 0:
				input_text = input_text.substr(0, input_text.length() - 1)
				_refresh_display()
				SoundManager.play_ui("menu_cancel")
			get_viewport().set_input_as_handled()
		elif key.unicode > 0 and key.unicode < 128:
			var char = String.chr(key.unicode)
			if input_text.length() < max_length:
				input_text += char
				_refresh_display()
				SoundManager.play_ui("menu_select")
			get_viewport().set_input_as_handled()


func _press_key() -> void:
	"""Handle pressing the currently selected key"""
	var layout = _get_current_layout()
	var key_char = layout[cursor_row][cursor_col]

	match key_char:
		"⌫":  # Backspace
			if input_text.length() > 0:
				input_text = input_text.substr(0, input_text.length() - 1)
				_refresh_display()
				SoundManager.play_ui("menu_cancel")
		"⇧":  # Shift/Case toggle
			char_set = (char_set + 1) % 3
			_refresh_keys()
			SoundManager.play_ui("menu_move")
		"OK":  # Submit
			_submit_text()
		" ":  # Space
			if input_text.length() < max_length:
				input_text += " "
				_refresh_display()
				SoundManager.play_ui("menu_select")
		_:  # Regular character
			if input_text.length() < max_length:
				input_text += key_char
				_refresh_display()
				SoundManager.play_ui("menu_select")


func _submit_text() -> void:
	"""Submit the entered text"""
	if input_text.strip_edges().length() > 0:
		SoundManager.play_ui("menu_select")
		text_submitted.emit(input_text.strip_edges())
	else:
		# Empty text - just cancel
		SoundManager.play_ui("menu_close")
		cancelled.emit()
