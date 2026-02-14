extends Control
class_name TitleScreen

## TitleScreen - Retro 12-16 bit style title screen
## Classic JRPG aesthetic with animated elements

signal new_game_selected()
signal continue_selected()
signal settings_selected()

## Menu state
var selected_index: int = 0
var menu_items: Array[Dictionary] = []
var _can_input: bool = false

## Animation state
var _title_offset: float = 0.0
var _star_positions: Array[Vector2] = []
var _cursor_blink: bool = true
var _blink_timer: float = 0.0

## Colors - 16-bit palette
const BG_COLOR = Color(0.02, 0.02, 0.06)
const TITLE_COLOR = Color(0.95, 0.85, 0.4)
const TITLE_SHADOW = Color(0.6, 0.3, 0.1)
const MENU_COLOR = Color(0.9, 0.9, 0.95)
const MENU_SELECTED = Color(1.0, 1.0, 0.5)
const MENU_DISABLED = Color(0.4, 0.4, 0.5)
const CURSOR_COLOR = Color(1.0, 0.9, 0.3)
const STAR_COLORS = [
	Color(0.6, 0.6, 0.8, 0.8),
	Color(0.8, 0.8, 1.0, 0.6),
	Color(1.0, 1.0, 1.0, 0.9),
	Color(0.7, 0.8, 1.0, 0.5)
]

## UI elements
var _title_container: Control = null
var _menu_container: VBoxContainer = null
var _stars_container: Control = null
var _version_label: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Generate star field
	_generate_stars()

	# Build UI
	_build_ui()

	# Start music
	if SoundManager:
		SoundManager.play_music("title")

	# Delay input to prevent accidental selection
	await get_tree().create_timer(0.5).timeout
	_can_input = true


func _process(delta: float) -> void:
	# Animate title float
	_title_offset = sin(Time.get_ticks_msec() / 1000.0) * 3.0
	if _title_container:
		_title_container.position.y = 80 + _title_offset

	# Cursor blink
	_blink_timer += delta
	if _blink_timer >= 0.4:
		_blink_timer = 0.0
		_cursor_blink = not _cursor_blink
		_update_cursor()

	# Animate stars (twinkle)
	_animate_stars(delta)


func _generate_stars() -> void:
	"""Generate random star positions for background"""
	_star_positions.clear()
	var viewport_size = get_viewport_rect().size
	for i in range(60):
		_star_positions.append(Vector2(
			randf() * viewport_size.x,
			randf() * viewport_size.y
		))


func _build_ui() -> void:
	"""Build the title screen UI"""
	var viewport_size = get_viewport_rect().size

	# Background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Stars container
	_stars_container = Control.new()
	_stars_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stars_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stars_container)
	_draw_stars()

	# Gradient overlay (darker at edges)
	var gradient = _create_vignette(viewport_size)
	add_child(gradient)

	# Title container
	_title_container = Control.new()
	_title_container.position = Vector2(0, 80)
	_title_container.size = Vector2(viewport_size.x, 120)
	add_child(_title_container)

	# Title shadow
	var title_shadow = Label.new()
	title_shadow.text = "COWARDLY IRREGULAR"
	title_shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_shadow.position = Vector2(3, 3)
	title_shadow.add_theme_font_size_override("font_size", 42)
	title_shadow.add_theme_color_override("font_color", TITLE_SHADOW)
	_title_container.add_child(title_shadow)

	# Title main
	var title = Label.new()
	title.text = "COWARDLY IRREGULAR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	_title_container.add_child(title)

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "~ Where Automation is Enlightenment ~"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector2(0, 180)
	subtitle.size = Vector2(viewport_size.x, 30)
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.5, 0.7))
	add_child(subtitle)

	# Menu container
	_menu_container = VBoxContainer.new()
	_menu_container.position = Vector2(viewport_size.x / 2 - 100, viewport_size.y / 2 + 20)
	_menu_container.add_theme_constant_override("separation", 8)
	add_child(_menu_container)

	# Build menu items
	_build_menu()

	# Version label
	_version_label = Label.new()
	_version_label.text = "v0.4.0"
	_version_label.position = Vector2(viewport_size.x - 80, viewport_size.y - 30)
	_version_label.add_theme_font_size_override("font_size", 10)
	_version_label.add_theme_color_override("font_color", Color(0.3, 0.3, 0.4))
	add_child(_version_label)

	# Controls hint
	var controls = Label.new()
	controls.text = "[Z/A] Select    [X/B] Back"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.position = Vector2(0, viewport_size.y - 50)
	controls.size = Vector2(viewport_size.x, 20)
	controls.add_theme_font_size_override("font_size", 11)
	controls.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	add_child(controls)


func _create_vignette(size: Vector2) -> Control:
	"""Create a subtle vignette overlay"""
	var container = Control.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Top gradient
	var top = ColorRect.new()
	top.color = Color(0, 0, 0, 0.3)
	top.position = Vector2(0, 0)
	top.size = Vector2(size.x, 60)
	container.add_child(top)

	# Bottom gradient
	var bottom = ColorRect.new()
	bottom.color = Color(0, 0, 0, 0.4)
	bottom.position = Vector2(0, size.y - 80)
	bottom.size = Vector2(size.x, 80)
	container.add_child(bottom)

	return container


func _draw_stars() -> void:
	"""Draw stars to the stars container"""
	for child in _stars_container.get_children():
		child.queue_free()

	for i in range(_star_positions.size()):
		var pos = _star_positions[i]
		var star = ColorRect.new()
		var size_val = randf_range(1, 3)
		star.size = Vector2(size_val, size_val)
		star.position = pos
		star.color = STAR_COLORS[i % STAR_COLORS.size()]
		star.name = "Star_%d" % i
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stars_container.add_child(star)


func _animate_stars(delta: float) -> void:
	"""Animate star twinkle"""
	if not _stars_container:
		return
	for i in range(_stars_container.get_child_count()):
		var star = _stars_container.get_child(i)
		if star is ColorRect:
			# Twinkle effect
			var twinkle = sin(Time.get_ticks_msec() / 500.0 + i * 0.5) * 0.3 + 0.7
			star.modulate.a = twinkle


func _build_menu() -> void:
	"""Build menu items based on save state"""
	menu_items.clear()
	for child in _menu_container.get_children():
		child.queue_free()

	# Check for existing save
	var has_save = _check_for_save()

	# Continue (only if save exists)
	if has_save:
		menu_items.append({"id": "continue", "label": "CONTINUE", "enabled": true})

	# New Game
	menu_items.append({"id": "new_game", "label": "NEW GAME", "enabled": true})

	# Settings
	menu_items.append({"id": "settings", "label": "SETTINGS", "enabled": true})

	# Help / Controls
	menu_items.append({"id": "help", "label": "HELP", "enabled": true})

	# Create menu item labels
	for i in range(menu_items.size()):
		var item = menu_items[i]
		var row = _create_menu_row(i, item)
		_menu_container.add_child(row)

	_update_selection()


func _create_menu_row(index: int, item: Dictionary) -> Control:
	"""Create a single menu row"""
	var row = Control.new()
	row.custom_minimum_size = Vector2(200, 28)
	row.name = "MenuItem_%d" % index

	# Cursor
	var cursor = Label.new()
	cursor.name = "Cursor"
	cursor.text = ">"
	cursor.position = Vector2(0, 2)
	cursor.add_theme_font_size_override("font_size", 18)
	cursor.add_theme_color_override("font_color", CURSOR_COLOR)
	cursor.visible = (index == selected_index)
	row.add_child(cursor)

	# Label
	var label = Label.new()
	label.name = "Label"
	label.text = item["label"]
	label.position = Vector2(24, 2)
	label.add_theme_font_size_override("font_size", 18)
	if item["enabled"]:
		label.add_theme_color_override("font_color", MENU_COLOR if index != selected_index else MENU_SELECTED)
	else:
		label.add_theme_color_override("font_color", MENU_DISABLED)
	row.add_child(label)

	return row


func _update_selection() -> void:
	"""Update visual selection state"""
	for i in range(_menu_container.get_child_count()):
		var row = _menu_container.get_child(i)
		var cursor = row.get_node_or_null("Cursor")
		var label = row.get_node_or_null("Label")
		var is_selected = (i == selected_index)

		if cursor:
			cursor.visible = is_selected and _cursor_blink
		if label and i < menu_items.size():
			var item = menu_items[i]
			if item["enabled"]:
				label.add_theme_color_override("font_color", MENU_SELECTED if is_selected else MENU_COLOR)


func _update_cursor() -> void:
	"""Update cursor visibility for blink effect"""
	if selected_index < _menu_container.get_child_count():
		var row = _menu_container.get_child(selected_index)
		var cursor = row.get_node_or_null("Cursor")
		if cursor:
			cursor.visible = _cursor_blink


func _check_for_save() -> bool:
	"""Check if any save file exists"""
	if FileAccess.file_exists("user://save_data.json"):
		return true
	if FileAccess.file_exists("user://saves/save_00.json"):
		return true
	return false


func _input(event: InputEvent) -> void:
	if not _can_input:
		return

	# Close help overlay with B/Escape
	if _help_overlay and event.is_action_pressed("ui_cancel"):
		_close_help_overlay()
		get_viewport().set_input_as_handled()
		return

	# Navigation - check echo to prevent rapid-fire when holding keys
	if event.is_action_pressed("ui_up") and not event.is_echo():
		_move_selection(-1)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		_move_selection(1)
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_select_item()
		get_viewport().set_input_as_handled()


func _move_selection(delta: int) -> void:
	"""Move menu selection"""
	var old_index = selected_index
	selected_index = clampi(selected_index + delta, 0, menu_items.size() - 1)

	# Skip disabled items
	while selected_index >= 0 and selected_index < menu_items.size():
		if menu_items[selected_index]["enabled"]:
			break
		selected_index += delta

	# Clamp again
	selected_index = clampi(selected_index, 0, menu_items.size() - 1)

	if selected_index != old_index:
		if SoundManager:
			SoundManager.play_ui("menu_move")
		_update_selection()


func _select_item() -> void:
	"""Select current menu item"""
	if selected_index >= menu_items.size():
		return

	var item = menu_items[selected_index]
	if not item["enabled"]:
		return

	if SoundManager:
		SoundManager.play_ui("menu_select")

	match item["id"]:
		"new_game":
			new_game_selected.emit()
		"continue":
			continue_selected.emit()
		"settings":
			settings_selected.emit()
		"help":
			_show_help_overlay()


var _help_overlay: Control = null

func _show_help_overlay() -> void:
	"""Show controls and game concepts help screen"""
	if _help_overlay:
		return
	_can_input = false

	_help_overlay = Control.new()
	_help_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help_overlay.z_index = 50
	add_child(_help_overlay)

	# Dim background
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.05, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_overlay.add_child(bg)

	var vp = get_viewport_rect().size

	# Title
	var title = Label.new()
	title.text = "HOW TO PLAY"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(vp.x / 2 - 120, 30)
	title.size = Vector2(240, 30)
	_help_overlay.add_child(title)

	# Help content using RichTextLabel for formatting
	var content = RichTextLabel.new()
	content.bbcode_enabled = true
	content.scroll_active = true
	content.position = Vector2(60, 75)
	content.size = Vector2(vp.x - 120, vp.y - 120)
	content.add_theme_font_size_override("normal_font_size", 13)
	content.add_theme_font_size_override("bold_font_size", 14)
	content.add_theme_color_override("default_color", Color(0.9, 0.9, 0.95))

	content.text = """[b][color=yellow]CONTROLS[/color][/b]
[color=gray]Gamepad          Keyboard[/color]
D-Pad             Arrow Keys      Navigate
A Button          Z / Enter       Confirm / Select
B Button          X / Escape      Cancel / Back
L Shoulder        L Key           Defer (skip turn, +1 AP)
R Shoulder        R Key           Advance (queue action, -1 AP)
Start             F5              Open Autobattle Editor
Select            F6              Toggle Autobattle

[b][color=yellow]BATTLE SYSTEM (CTB)[/color][/b]
Each turn you choose: [color=lime]Attack[/color], use [color=cyan]Magic[/color], or strategize with AP.

[color=white]AP (Action Points)[/color] range from -4 to +4.
  [color=lime]Defer (L)[/color]: Skip your turn. Gain +1 AP, take less damage.
  [color=cyan]Advance (R)[/color]: Queue extra actions. Each costs 1 AP.
    Queue up to 4 actions, then they all execute at once!

[b][color=yellow]AUTOBATTLE[/color][/b]
This game is designed to be automated!
Open the [color=lime]Autobattle Editor[/color] (Start/F5) to write rules:
  IF [condition] THEN [action]
Rules are checked top-to-bottom. First match wins.
Toggle autobattle per character with Select/F6.

[b][color=yellow]TIPS[/color][/b]
- Deferring builds AP for powerful multi-action turns later
- Queue multiple heals or attacks with Advance for burst plays
- Autobattle scripts run automatically - master them to win!
- Different terrains boost/reduce elemental damage
- Explore the overworld to find the cave and village

[color=gray]Press B / X / Escape to close[/color]"""
	_help_overlay.add_child(content)

	await get_tree().create_timer(0.3).timeout
	_can_input = true


func _close_help_overlay() -> void:
	if _help_overlay:
		_help_overlay.queue_free()
		_help_overlay = null
