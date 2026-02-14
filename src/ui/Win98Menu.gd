extends Control
class_name Win98Menu

## Retro RPG Style Cascading Menu System
## Classic pixel-tile borders like FF/DQ style

signal item_selected(item_id: String, item_data: Variant)
signal item_held(item_id: String, item_data: Variant)  # For long press actions
signal menu_closed()
signal actions_submitted(actions: Array)  # For Advance mode - multiple actions
signal defer_requested()  # L button with no queue - defer turn
signal go_back_requested()  # B button at root to go back to previous player
signal confirm_turn_requested()  # L button held - confirm current queue and end turn


## Get currently selected item ID (for hold detection)
func get_selected_item_id() -> String:
	if selected_index >= 0 and selected_index < menu_items.size():
		return menu_items[selected_index].get("id", "")
	return ""


func get_selected_item_data() -> Variant:
	if selected_index >= 0 and selected_index < menu_items.size():
		return menu_items[selected_index].get("data", null)
	return null

## Menu styling per character class - retro palette
const CHARACTER_STYLES = {
	"fighter": {
		"bg": Color(0.1, 0.1, 0.2),              # Dark blue
		"border": Color(0.9, 0.9, 1.0),          # White border
		"border_shadow": Color(0.3, 0.3, 0.5),   # Shadow
		"text": Color(1.0, 1.0, 1.0),
		"highlight_bg": Color(0.3, 0.3, 0.6),
		"highlight_text": Color(1.0, 1.0, 0.5),  # Yellow highlight
		"cursor": Color(1.0, 1.0, 1.0)
	},
	"white_mage": {
		"bg": Color(0.15, 0.1, 0.2),             # Dark purple-pink
		"border": Color(1.0, 0.8, 0.9),          # Pink-white
		"border_shadow": Color(0.4, 0.2, 0.3),
		"text": Color(1.0, 0.95, 1.0),
		"highlight_bg": Color(0.4, 0.2, 0.4),
		"highlight_text": Color(1.0, 0.8, 1.0),
		"cursor": Color(1.0, 0.8, 0.9)
	},
	"thief": {
		"bg": Color(0.1, 0.1, 0.1),              # Near black
		"border": Color(0.6, 0.5, 0.7),          # Muted purple
		"border_shadow": Color(0.2, 0.15, 0.25),
		"text": Color(0.9, 0.85, 1.0),
		"highlight_bg": Color(0.25, 0.2, 0.3),
		"highlight_text": Color(0.8, 1.0, 0.6),  # Green-ish
		"cursor": Color(0.6, 0.5, 0.7)
	},
	"black_mage": {
		"bg": Color(0.05, 0.0, 0.1),             # Deep purple-black
		"border": Color(0.5, 0.3, 0.7),          # Purple
		"border_shadow": Color(0.15, 0.1, 0.2),
		"text": Color(0.8, 0.7, 1.0),
		"highlight_bg": Color(0.2, 0.1, 0.3),
		"highlight_text": Color(1.0, 0.5, 0.5),  # Red-ish
		"cursor": Color(0.7, 0.4, 0.9)
	}
}

var style: Dictionary = CHARACTER_STYLES["fighter"]
var menu_items: Array = []
var selected_index: int = 0
var submenu: Win98Menu = null
var parent_menu: Win98Menu = null
var anchor_position: Vector2 = Vector2.ZERO
var menu_title: String = ""
var expand_left: bool = true  # Submenus expand to the left (tree style)
var expand_up: bool = true  # Submenus expand upward (tree style)
var is_root_menu: bool = false  # Root menus can't be closed by clicking outside
var _can_close_on_click: bool = false  # Delay before accepting click-outside-to-close
var _can_accept_input: bool = false  # Delay before accepting keyboard input
var _submenu_timer: Timer = null  # Delay before expanding submenu
var _cursor_blink_timer: Timer = null  # Blinking cursor
var _cursor_visible: bool = true
var _audio_player: AudioStreamPlayer = null
var _target_highlight: Control = null  # Rectangle highlight around target
var _pending_target_pos: Vector2 = Vector2.ZERO  # Target position for line
var _queued_actions: Array = []  # Actions queued via Advance mode
var _max_queue_size: int = 4  # Max actions (limited by AP)
var _is_closing: bool = false  # Prevent double-close
var _current_ap: int = 0  # Current AP for display
var _ap_label: Label = null  # AP display label
var _can_go_back: bool = false  # Whether B button can go to previous player
var battle_mode: bool = true  # Whether to show battle-specific UI (AP, advance/defer)
var _initial_selection_id: String = ""  # ID to pre-select when menu opens
var _submenu_memory: Dictionary = {}  # {menu_id: submenu_item_id} for command memory
var _l_button_pressed: bool = false  # Track if L button is held
var _l_button_press_time: float = 0.0  # When L was pressed
const L_HOLD_CONFIRM_TIME: float = 0.15  # Seconds to hold L for confirm (reduced for snappier response)

## Signals for target selection with position
signal target_selected(item_id: String, item_data: Variant, target_pos: Vector2)

## Pixel tile size
const TILE_SIZE = 4
const ITEM_HEIGHT = 16
const MENU_PADDING = 8
const SUBMENU_DELAY = 0.12  # Delay before submenu expands


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Make menu input independent of battle speed (Engine.time_scale)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_setup_timers()
	_setup_audio()
	# Don't call _build_menu() here - setup() will call it with proper data
	# This prevents a race condition when setup() is called immediately after add_child()
	# Ensure we can receive input
	focus_mode = Control.FOCUS_ALL
	grab_focus()


func _process(delta: float) -> void:
	# Guard against running on freed node
	if not is_instance_valid(self) or _is_closing:
		return
	# Check for L button hold-to-confirm
	if _l_button_pressed and battle_mode:
		var hold_time = Time.get_ticks_msec() / 1000.0 - _l_button_press_time
		if hold_time >= L_HOLD_CONFIRM_TIME:
			_l_button_pressed = false
			_confirm_turn_with_queue()


func _exit_tree() -> void:
	"""Cleanup when removed from tree"""
	# Stop timers to prevent pending callbacks
	if _submenu_timer and is_instance_valid(_submenu_timer):
		_submenu_timer.stop()
	if _cursor_blink_timer and is_instance_valid(_cursor_blink_timer):
		_cursor_blink_timer.stop()
	_cleanup_target_highlight()
	if submenu and is_instance_valid(submenu):
		submenu.queue_free()
		submenu = null


func _setup_timers() -> void:
	"""Setup timers for animations"""
	# Submenu delay timer - independent of battle speed
	_submenu_timer = Timer.new()
	_submenu_timer.one_shot = true
	_submenu_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_submenu_timer.timeout.connect(_on_submenu_timer_timeout)
	add_child(_submenu_timer)

	# Cursor blink timer - independent of battle speed
	_cursor_blink_timer = Timer.new()
	_cursor_blink_timer.wait_time = 0.3
	_cursor_blink_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_cursor_blink_timer.timeout.connect(_on_cursor_blink)
	add_child(_cursor_blink_timer)
	_cursor_blink_timer.start()

	# Target highlight (styled rectangle around selected target)
	_setup_target_highlight()


func _setup_target_highlight() -> void:
	"""Create a styled rectangle highlight for target selection"""
	_target_highlight = Control.new()
	_target_highlight.z_index = 99
	_target_highlight.visible = false
	_target_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Add as sibling so it's not clipped by menu bounds
	call_deferred("_add_target_highlight_to_parent")


func _add_target_highlight_to_parent() -> void:
	"""Add target highlight as sibling for proper rendering"""
	if _target_highlight and get_parent():
		get_parent().add_child(_target_highlight)


func _update_target_highlight() -> void:
	"""Update target highlight rectangle around selected target"""
	if not _target_highlight or not is_instance_valid(_target_highlight):
		return

	# Get current item data
	if selected_index < 0 or selected_index >= menu_items.size():
		_target_highlight.visible = false
		return

	var item = menu_items[selected_index]
	var item_data = item.get("data", null)

	# Check if item has target position
	var target_pos = Vector2.ZERO
	if item_data is Dictionary and item_data.has("target_pos"):
		target_pos = item_data.get("target_pos", Vector2.ZERO)

	if target_pos == Vector2.ZERO:
		_target_highlight.visible = false
		_pending_target_pos = Vector2.ZERO
		return

	_pending_target_pos = target_pos

	# Build the highlight box around target
	_build_target_highlight_box(target_pos)
	_target_highlight.visible = true


func _build_target_highlight_box(target_pos: Vector2) -> void:
	"""Build a styled rectangle with pointer around the target"""
	# Clear existing children
	for child in _target_highlight.get_children():
		child.queue_free()

	# Box dimensions (around sprite)
	var box_width = 90
	var box_height = 70
	var border_width = 3

	# Position centered on target (offset down to account for sprite anchor)
	var box_pos = target_pos - Vector2(box_width / 2, box_height / 2 - 5)
	_target_highlight.position = box_pos
	_target_highlight.size = Vector2(box_width, box_height)

	# Colors matching menu style
	var border_color = style.get("cursor", Color(1.0, 1.0, 0.3))
	var corner_color = border_color.lightened(0.3)

	# Top border
	var top = ColorRect.new()
	top.color = border_color
	top.position = Vector2(border_width, 0)
	top.size = Vector2(box_width - border_width * 2, border_width)
	_target_highlight.add_child(top)

	# Bottom border
	var bottom = ColorRect.new()
	bottom.color = border_color
	bottom.position = Vector2(border_width, box_height - border_width)
	bottom.size = Vector2(box_width - border_width * 2, border_width)
	_target_highlight.add_child(bottom)

	# Left border
	var left = ColorRect.new()
	left.color = border_color
	left.position = Vector2(0, border_width)
	left.size = Vector2(border_width, box_height - border_width * 2)
	_target_highlight.add_child(left)

	# Right border
	var right = ColorRect.new()
	right.color = border_color
	right.position = Vector2(box_width - border_width, border_width)
	right.size = Vector2(border_width, box_height - border_width * 2)
	_target_highlight.add_child(right)

	# Corner tiles (brighter)
	var corners = [
		Vector2(0, 0),  # Top-left
		Vector2(box_width - border_width, 0),  # Top-right
		Vector2(0, box_height - border_width),  # Bottom-left
		Vector2(box_width - border_width, box_height - border_width)  # Bottom-right
	]
	for corner_pos in corners:
		var corner = ColorRect.new()
		corner.color = corner_color
		corner.position = corner_pos
		corner.size = Vector2(border_width, border_width)
		_target_highlight.add_child(corner)

	# Add pointer arrow at top pointing down
	var pointer = Label.new()
	pointer.text = "▼"
	pointer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pointer.position = Vector2(box_width / 2 - 8, -18)
	pointer.add_theme_color_override("font_color", border_color)
	pointer.add_theme_font_size_override("font_size", 16)
	_target_highlight.add_child(pointer)


func _fade_target_highlight(on_complete: Callable = Callable()) -> void:
	"""Fade out the target highlight with animation"""
	if not _target_highlight or not is_instance_valid(_target_highlight):
		if on_complete.is_valid():
			on_complete.call()
		return

	if not _target_highlight.visible:
		if on_complete.is_valid():
			on_complete.call()
		return

	var tween = create_tween()
	# Multiply duration by time_scale to keep consistent real-time speed
	tween.tween_property(_target_highlight, "modulate:a", 0.0, 0.15 * Engine.time_scale).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		if is_instance_valid(_target_highlight):
			_target_highlight.visible = false
			_target_highlight.modulate.a = 1.0  # Reset for next use
		if on_complete.is_valid():
			on_complete.call()
	)


func _setup_audio() -> void:
	"""Setup audio for menu sounds (now uses SoundManager)"""
	# Legacy audio player no longer needed - SoundManager handles all sounds
	pass


func _play_move_sound() -> void:
	"""Play sound when moving between menu items"""
	SoundManager.play_ui("menu_move")


func _play_select_sound() -> void:
	"""Play sound when selecting an item"""
	SoundManager.play_ui("menu_select")


func _play_expand_sound() -> void:
	"""Play sound when submenu expands"""
	SoundManager.play_ui("menu_expand")


func _play_advance_sound() -> void:
	"""Play sound when queueing an action (Advance mode)"""
	SoundManager.play_ui("advance_queue")


func _play_undo_sound() -> void:
	"""Play sound when undoing a queued action"""
	SoundManager.play_ui("advance_undo")


func _play_defer_sound() -> void:
	"""Play sound when deferring"""
	SoundManager.play_ui("defer")


func _play_cancel_sound() -> void:
	"""Play sound when canceling"""
	SoundManager.play_ui("menu_cancel")


func _on_cursor_blink() -> void:
	"""Toggle cursor visibility for blink effect"""
	_cursor_visible = not _cursor_visible
	_update_cursor_visibility()


func _update_cursor_visibility() -> void:
	"""Update cursor visibility in current selection"""
	var container = _get_items_container()
	if not container:
		return

	for i in range(container.get_child_count()):
		var row = container.get_child(i)
		var cursor = row.get_node_or_null("Cursor")
		if cursor and i == selected_index:
			cursor.visible = _cursor_visible


func _on_submenu_timer_timeout() -> void:
	"""Called when submenu delay timer fires"""
	if selected_index < 0 or selected_index >= menu_items.size():
		return

	var item = menu_items[selected_index]
	if item.has("submenu") and not item.get("disabled", false):
		_do_open_submenu(selected_index, item)


func setup(title: String, items: Array, pos: Vector2, character_class: String = "fighter") -> void:
	"""Setup the menu with items and position"""
	menu_title = title
	menu_items = items
	anchor_position = pos
	selected_index = 0

	if CHARACTER_STYLES.has(character_class):
		style = CHARACTER_STYLES[character_class]
	else:
		style = CHARACTER_STYLES["fighter"]

	if is_inside_tree():
		_build_menu()


func _build_menu() -> void:
	"""Build the retro pixel-tile menu"""
	# Clear existing children
	for child in get_children():
		child.queue_free()

	if menu_items.size() == 0:
		return

	# Calculate menu width dynamically based on item label lengths
	var content_padding = MENU_PADDING * 2 + TILE_SIZE * 2 + 20  # borders + cursor + gap
	var max_label_width = 0
	var font = ThemeDB.fallback_font
	for item in menu_items:
		var label_text = item.get("label", "Item")
		if item.has("submenu"):
			label_text += " >"
		var text_width = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		max_label_width = max(max_label_width, text_width)
	var menu_width = max(140, int(max_label_width) + content_padding)

	var ap_label_height = 14 if (is_root_menu and battle_mode) else 0  # Only show AP in battle
	var menu_height = MENU_PADDING * 2 + menu_items.size() * ITEM_HEIGHT + TILE_SIZE * 2 + ap_label_height

	# Create the menu texture with pixel borders
	var menu_panel = _create_retro_panel(menu_width, menu_height)
	add_child(menu_panel)

	# AP label at top for root menu in battle mode (compact, right-aligned)
	if is_root_menu and battle_mode:
		_ap_label = Label.new()
		_ap_label.name = "APLabel"
		_ap_label.position = Vector2(MENU_PADDING + TILE_SIZE, MENU_PADDING)
		_ap_label.size = Vector2(menu_width - MENU_PADDING * 2 - TILE_SIZE * 2, 12)
		_ap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_ap_label.add_theme_font_size_override("font_size", 9)
		_update_ap_label()
		menu_panel.add_child(_ap_label)

	# Store content width for item rows
	var item_content_width = menu_width - MENU_PADDING * 2 - TILE_SIZE * 2

	# Items container (offset by AP label if present)
	var items_container = VBoxContainer.new()
	items_container.position = Vector2(MENU_PADDING + TILE_SIZE, MENU_PADDING + TILE_SIZE + ap_label_height)
	items_container.add_theme_constant_override("separation", 0)
	menu_panel.add_child(items_container)

	# Create menu items
	for i in range(menu_items.size()):
		var item = menu_items[i]
		var item_row = _create_menu_item(i, item, item_content_width)
		items_container.add_child(item_row)

	# Set size and position
	custom_minimum_size = Vector2(menu_width, menu_height)
	size = Vector2(menu_width, menu_height)
	position = anchor_position

	# Ensure menu stays on screen
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	_clamp_to_screen()

	# Highlight first item and auto-expand if it has submenu
	_update_selection()

	# Apply command memory to pre-select remembered item
	_apply_command_memory()

	_auto_expand_submenu()

	# Allow input after a short delay to prevent stray key presses
	# Use ignore_time_scale=true to keep consistent regardless of battle speed
	await get_tree().create_timer(0.08, true, false, true).timeout  # Reduced from 0.15 for faster response
	if not is_instance_valid(self):
		return
	_can_accept_input = true
	await get_tree().create_timer(0.05, true, false, true).timeout  # Reduced from 0.1 for faster response
	if not is_instance_valid(self):
		return
	_can_close_on_click = true


func _create_retro_panel(w: int, h: int) -> Control:
	"""Create a retro-style panel with pixel tile borders"""
	var panel = Control.new()
	panel.custom_minimum_size = Vector2(w, h)
	panel.size = Vector2(w, h)

	# Background
	var bg = ColorRect.new()
	bg.color = style.bg
	bg.position = Vector2(TILE_SIZE, TILE_SIZE)
	bg.size = Vector2(w - TILE_SIZE * 2, h - TILE_SIZE * 2)
	panel.add_child(bg)

	# Draw pixel borders using ColorRects for crisp pixels
	# Top border
	var top = ColorRect.new()
	top.color = style.border
	top.position = Vector2(TILE_SIZE, 0)
	top.size = Vector2(w - TILE_SIZE * 2, TILE_SIZE)
	panel.add_child(top)

	# Bottom border
	var bottom = ColorRect.new()
	bottom.color = style.border_shadow
	bottom.position = Vector2(TILE_SIZE, h - TILE_SIZE)
	bottom.size = Vector2(w - TILE_SIZE * 2, TILE_SIZE)
	panel.add_child(bottom)

	# Left border
	var left = ColorRect.new()
	left.color = style.border
	left.position = Vector2(0, TILE_SIZE)
	left.size = Vector2(TILE_SIZE, h - TILE_SIZE * 2)
	panel.add_child(left)

	# Right border
	var right = ColorRect.new()
	right.color = style.border_shadow
	right.position = Vector2(w - TILE_SIZE, TILE_SIZE)
	right.size = Vector2(TILE_SIZE, h - TILE_SIZE * 2)
	panel.add_child(right)

	# Corner tiles (top-left bright, bottom-right dark)
	var tl = ColorRect.new()
	tl.color = style.border
	tl.position = Vector2(0, 0)
	tl.size = Vector2(TILE_SIZE, TILE_SIZE)
	panel.add_child(tl)

	var tr = ColorRect.new()
	tr.color = style.border
	tr.position = Vector2(w - TILE_SIZE, 0)
	tr.size = Vector2(TILE_SIZE, TILE_SIZE)
	panel.add_child(tr)

	var bl = ColorRect.new()
	bl.color = style.border_shadow
	bl.position = Vector2(0, h - TILE_SIZE)
	bl.size = Vector2(TILE_SIZE, TILE_SIZE)
	panel.add_child(bl)

	var br = ColorRect.new()
	br.color = style.border_shadow
	br.position = Vector2(w - TILE_SIZE, h - TILE_SIZE)
	br.size = Vector2(TILE_SIZE, TILE_SIZE)
	panel.add_child(br)

	return panel


func _create_menu_item(index: int, item: Dictionary, content_width: int = 120) -> Control:
	"""Create a single menu item row"""
	var row = Control.new()
	row.custom_minimum_size = Vector2(content_width, ITEM_HEIGHT)
	row.name = "Item%d" % index

	# Selection highlight border (top line)
	var highlight_top = ColorRect.new()
	highlight_top.name = "HighlightTop"
	highlight_top.color = style.cursor.lightened(0.3)
	highlight_top.position = Vector2(-4, 0)
	highlight_top.size = Vector2(content_width + 8, 1)
	highlight_top.visible = false
	row.add_child(highlight_top)

	# Selection highlight background (hidden by default)
	var highlight = ColorRect.new()
	highlight.name = "Highlight"
	highlight.color = style.highlight_bg.lightened(0.1)
	highlight.position = Vector2(-4, 1)
	highlight.size = Vector2(content_width + 8, ITEM_HEIGHT - 2)
	highlight.visible = false
	row.add_child(highlight)

	# Selection highlight border (bottom line)
	var highlight_bottom = ColorRect.new()
	highlight_bottom.name = "HighlightBottom"
	highlight_bottom.color = style.cursor.darkened(0.2)
	highlight_bottom.position = Vector2(-4, ITEM_HEIGHT - 1)
	highlight_bottom.size = Vector2(content_width + 8, 1)
	highlight_bottom.visible = false
	row.add_child(highlight_bottom)

	# Cursor arrow (animated)
	var cursor = Label.new()
	cursor.name = "Cursor"
	cursor.text = "▶"  # Filled triangle for better visibility
	cursor.position = Vector2(-4, 0)
	cursor.add_theme_color_override("font_color", style.cursor)
	cursor.add_theme_font_size_override("font_size", 10)
	cursor.visible = false
	row.add_child(cursor)

	# Item label
	var label = item.get("label", "Item")
	var has_submenu = item.has("submenu")
	var disabled = item.get("disabled", false)

	var text_label = Label.new()
	text_label.name = "Label"
	text_label.position = Vector2(10, 0)
	if has_submenu:
		text_label.text = label + " >"
	else:
		text_label.text = label

	if disabled:
		text_label.add_theme_color_override("font_color", style.text.darkened(0.5))
	else:
		text_label.add_theme_color_override("font_color", style.text)

	text_label.add_theme_font_size_override("font_size", 11)
	row.add_child(text_label)

	# Make clickable
	var button = Button.new()
	button.flat = true
	button.position = Vector2(0, 0)
	button.size = Vector2(content_width, ITEM_HEIGHT)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(_on_item_pressed.bind(index))
	button.mouse_entered.connect(_on_item_hover.bind(index))
	row.add_child(button)

	return row


func _update_selection() -> void:
	"""Update visual selection state"""
	var container = _get_items_container()
	if not container:
		return

	for i in range(container.get_child_count()):
		var row = container.get_child(i)
		var is_selected = (i == selected_index)

		# Update highlight background and borders
		var highlight = row.get_node_or_null("Highlight")
		var highlight_top = row.get_node_or_null("HighlightTop")
		var highlight_bottom = row.get_node_or_null("HighlightBottom")
		var cursor = row.get_node_or_null("Cursor")
		var label = row.get_node_or_null("Label")

		if highlight:
			highlight.visible = is_selected
		if highlight_top:
			highlight_top.visible = is_selected
		if highlight_bottom:
			highlight_bottom.visible = is_selected
		if cursor:
			cursor.visible = is_selected and _cursor_visible

		if label and is_selected:
			label.add_theme_color_override("font_color", style.highlight_text)
		elif label:
			var item = menu_items[i] if i < menu_items.size() else {}
			var disabled = item.get("disabled", false)
			if disabled:
				label.add_theme_color_override("font_color", style.text.darkened(0.5))
			else:
				label.add_theme_color_override("font_color", style.text)

	# Update target highlight to show selected enemy/ally
	_update_target_highlight()


func _on_item_pressed(index: int) -> void:
	"""Handle menu item selection (mouse click)"""
	# Guard against accidental clicks during setup
	if not _can_accept_input:
		return

	if index >= menu_items.size():
		return

	var item = menu_items[index]

	if item.get("disabled", false):
		return

	if item.has("submenu"):
		# Already showing submenu from hover
		return

	# Update selection and submit (handles queued actions)
	selected_index = index
	_submit_actions()


func _close_entire_tree() -> void:
	"""Close the entire menu tree by finding root and force closing"""
	var root = self
	while root.parent_menu:
		root = root.parent_menu
	root.force_close()


func _on_item_hover(index: int) -> void:
	"""Handle hovering over menu item"""
	if index != selected_index:
		_play_move_sound()
		selected_index = index
		_update_selection()

	# Use delayed expansion for submenus
	_auto_expand_submenu()


func _auto_expand_submenu() -> void:
	"""Auto-expand submenu for current selection if it has one (with delay)"""
	# Stop any pending submenu timer
	if _submenu_timer and is_instance_valid(_submenu_timer):
		_submenu_timer.stop()

	# Close existing submenu first
	if submenu:
		submenu.queue_free()
		submenu = null

	if selected_index < 0 or selected_index >= menu_items.size():
		return

	var item = menu_items[selected_index]
	if item.has("submenu") and not item.get("disabled", false):
		# Start delay timer before expanding
		if _submenu_timer:
			_submenu_timer.wait_time = SUBMENU_DELAY
			_submenu_timer.start()


func _get_items_container() -> VBoxContainer:
	"""Get the items container node"""
	var container = get_node_or_null("Control/VBoxContainer")
	if not container:
		for child in get_children():
			if child is Control:
				for subchild in child.get_children():
					if subchild is VBoxContainer:
						return subchild
	return container


func _do_open_submenu(parent_index: int, item: Dictionary) -> void:
	"""Actually open the submenu with animation"""
	_play_expand_sound()
	_open_submenu(parent_index, item)


func _open_submenu(parent_index: int, item: Dictionary) -> void:
	"""Open a submenu with slide animation - expands UP and LEFT (tree style)"""
	var submenu_items = item.get("submenu", [])
	var submenu_height = MENU_PADDING * 2 + submenu_items.size() * ITEM_HEIGHT + TILE_SIZE * 2

	var submenu_pos: Vector2
	var start_offset: Vector2

	# Calculate position - expand LEFT and UP from the selected item
	var item_y = parent_index * ITEM_HEIGHT + TILE_SIZE + MENU_PADDING
	if expand_left:
		# Position to the left of current menu
		submenu_pos.x = global_position.x - size.x - 4  # Menu width + gap
	else:
		submenu_pos.x = global_position.x + size.x + 4

	if expand_up:
		# Align bottom of submenu with current item, expand upward
		submenu_pos.y = global_position.y + item_y - submenu_height + ITEM_HEIGHT
	else:
		submenu_pos.y = global_position.y + item_y

	# Animation offset
	start_offset = Vector2(20 if expand_left else -20, 10 if expand_up else -10)

	submenu = Win98Menu.new()
	submenu.parent_menu = self
	submenu.expand_left = expand_left
	submenu.expand_up = expand_up
	submenu.z_index = z_index + 1

	# Start with offset and transparent for animation
	submenu.modulate.a = 0.0
	get_parent().add_child(submenu)
	submenu.setup(
		item.get("label", "Submenu"),
		submenu_items,
		submenu_pos + start_offset,
		_get_character_class_from_style()
	)

	# Pass submenu memory for nested command memory
	var item_id = item.get("id", "")
	var root = _get_root_menu()
	if root._submenu_memory.has(item_id):
		var remembered_item = root._submenu_memory[item_id]
		submenu.set_command_memory(remembered_item, root._submenu_memory)

	# Animate slide and fade in - multiply by time_scale for consistent speed
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(submenu, "position", submenu_pos, 0.1 * Engine.time_scale).set_ease(Tween.EASE_OUT)
	tween.tween_property(submenu, "modulate:a", 1.0, 0.08 * Engine.time_scale)

	# Forward submenu selection to parent
	submenu.item_selected.connect(func(id, data): item_selected.emit(id, data))


func _get_character_class_from_style() -> String:
	"""Get character class name from current style"""
	for job_class in CHARACTER_STYLES:
		if CHARACTER_STYLES[job_class] == style:
			return job_class
	return "fighter"


func _clamp_to_screen() -> void:
	"""Keep menu on screen"""
	var viewport_size = get_viewport_rect().size
	if position.x + size.x > viewport_size.x:
		position.x = viewport_size.x - size.x - 10
	if position.y + size.y > viewport_size.y:
		position.y = viewport_size.y - size.y - 10
	if position.x < 0:
		position.x = 10
	if position.y < 0:
		position.y = 10


func close_all() -> void:
	"""Close this menu and all parent menus"""
	# Clean up our own target highlight
	_cleanup_target_highlight()

	if submenu and is_instance_valid(submenu):
		submenu.queue_free()
		submenu = null

	if parent_menu and is_instance_valid(parent_menu):
		parent_menu.close_all()
	else:
		# Only close if not the root menu, or if forced
		if not is_root_menu:
			menu_closed.emit()
			queue_free()


func force_close() -> void:
	"""Force close this menu and all submenus immediately"""
	# Prevent double-close
	if _is_closing:
		return
	_is_closing = true

	# Reset L button state to prevent stale state
	_l_button_pressed = false

	# Hide immediately (queue_free happens at end of frame)
	hide()

	# Clean up target highlight
	_cleanup_target_highlight()

	# Recursively close submenus first
	if submenu and is_instance_valid(submenu):
		submenu.force_close()
		submenu = null

	# If we're root, emit signal
	if is_root_menu:
		menu_closed.emit()

	# Free this menu
	queue_free()


func _cleanup_target_highlight() -> void:
	"""Remove target highlight from scene"""
	if _target_highlight and is_instance_valid(_target_highlight):
		_target_highlight.queue_free()
		_target_highlight = null


## Advance Mode Functions

func _handle_advance_input() -> void:
	"""Handle R button / Shift+Enter - queue current action or confirm if at limit"""
	var current_item = menu_items[selected_index] if selected_index >= 0 and selected_index < menu_items.size() else {}

	if current_item.has("submenu"):
		# Has submenu - expand it to select target
		_play_expand_sound()
		if not submenu:
			_do_open_submenu(selected_index, current_item)
		return

	if current_item.get("disabled", false):
		return

	# Check if we're at the queue limit - if so, act as confirm
	var root = _get_root_menu()
	if root._queued_actions.size() >= root._max_queue_size - 1:
		# At or near limit - this will be the last action, so submit
		_play_advance_sound()  # Consistent advance sound even when auto-submitting
		_submit_actions()
		return

	# Queue the current action (menu stays open for more)
	_queue_current_action(current_item)


func _handle_defer_input() -> void:
	"""Handle L button release - undo last queued action, or defer if no queue"""
	var root = _get_root_menu()
	if root._queued_actions.size() > 0:
		# Undo last queued action (from any menu depth)
		_undo_last_action()
	else:
		# No actions queued - emit defer signal from root (where it's connected)
		_play_defer_sound()
		root.defer_requested.emit()
		root._close_entire_tree()


func _confirm_turn_with_queue() -> void:
	"""L button held for 2 seconds - confirm current queue and end turn"""
	var root = _get_root_menu()
	if root._queued_actions.size() > 0:
		# Submit queued actions as advance
		SoundManager.play_ui("menu_select")
		root.actions_submitted.emit(root._queued_actions.duplicate())
		root._queued_actions.clear()
		root._close_entire_tree()
	else:
		# No queue - just defer
		_play_defer_sound()
		root.defer_requested.emit()
		root._close_entire_tree()


func _queue_current_action(item: Dictionary) -> void:
	"""Add action to queue (Advance mode) - menu stays FULLY open for more actions"""
	# Always queue to root menu
	var root = _get_root_menu()

	if root._queued_actions.size() >= root._max_queue_size:
		# Queue full - play error sound or ignore
		return

	var action = {
		"id": item.get("id", ""),
		"data": item.get("data", null),
		"label": item.get("label", "")
	}
	root._queued_actions.append(action)
	_play_advance_sound()

	# Update AP display to show pending cost
	root._update_ap_label()

	# DON'T close menus or clear highlights - keep everything visible for more selections
	# The highlight stays on the current target until player moves to another


func _close_submenu_to_root() -> void:
	"""Close this submenu chain but keep root menu open"""
	# Clean up our target highlight
	_cleanup_target_highlight()

	if submenu and is_instance_valid(submenu):
		submenu.queue_free()
		submenu = null

	if parent_menu:
		parent_menu.submenu = null
		# If parent is not root, recurse
		if parent_menu.parent_menu:
			parent_menu._close_submenu_to_root()

	queue_free()


func _get_root_menu() -> Win98Menu:
	"""Get the root menu of this menu tree"""
	var root = self
	while root.parent_menu:
		root = root.parent_menu
	return root




func _undo_last_action() -> void:
	"""Remove last action from queue (always from root)"""
	var root = _get_root_menu()
	if root._queued_actions.size() > 0:
		root._queued_actions.pop_back()
		_play_undo_sound()
		root._update_ap_label()


func _cancel_all_queued() -> void:
	"""Clear entire action queue (always from root)"""
	var root = _get_root_menu()
	root._queued_actions.clear()
	_play_cancel_sound()
	root._update_ap_label()


func _submit_actions() -> void:
	"""Submit all queued actions + current selection"""
	var current_item = menu_items[selected_index] if selected_index >= 0 and selected_index < menu_items.size() else {}

	if current_item.get("disabled", false):
		return

	if current_item.has("submenu"):
		# Can't submit a submenu item directly
		return

	# Get root menu for queued actions
	var root = _get_root_menu()

	# Build final action list from root's queue
	var all_actions = root._queued_actions.duplicate()
	all_actions.append({
		"id": current_item.get("id", ""),
		"data": current_item.get("data", null),
		"label": current_item.get("label", "")
	})

	root._queued_actions.clear()

	# Emit signals immediately, then close
	_play_select_sound()

	# Hide target highlight immediately
	if _target_highlight and is_instance_valid(_target_highlight):
		_target_highlight.visible = false

	# Emit signal from root
	if all_actions.size() == 1:
		root.item_selected.emit(all_actions[0].id, all_actions[0].data)
	else:
		root.actions_submitted.emit(all_actions)

	# Close the entire menu tree immediately
	root.force_close()


func get_queue_count() -> int:
	"""Get number of queued actions"""
	return _queued_actions.size()


func set_max_queue_size(max_size: int) -> void:
	"""Set max queue size based on available AP"""
	_max_queue_size = max_size


func set_current_ap(ap: int) -> void:
	"""Set current AP for display"""
	_current_ap = ap
	_update_ap_label()


func set_can_go_back(can_go: bool) -> void:
	"""Set whether B button can go back to previous player"""
	_can_go_back = can_go


func set_command_memory(menu_selection: String, submenu_memory: Dictionary = {}) -> void:
	"""Set command memory to pre-select items when menu opens"""
	_initial_selection_id = menu_selection
	_submenu_memory = submenu_memory
	# Apply the selection immediately if menu is already built
	if menu_items.size() > 0 and menu_selection != "":
		_apply_command_memory()


func _apply_command_memory() -> void:
	"""Apply command memory to pre-select remembered item"""
	if _initial_selection_id == "":
		return

	# Find the item with matching id
	for i in range(menu_items.size()):
		var item = menu_items[i]
		if item.get("id", "") == _initial_selection_id:
			selected_index = i
			_update_selection()
			break

	# Clear so it only applies once
	_initial_selection_id = ""


func _update_ap_label() -> void:
	"""Update the AP display label showing current and pending cost"""
	if not _ap_label or not is_instance_valid(_ap_label):
		return

	var root = _get_root_menu()
	var queued_count = root._queued_actions.size()

	if queued_count == 0:
		# No actions queued, just show current AP
		_ap_label.text = "%+d AP" % _current_ap
		_ap_label.add_theme_color_override("font_color", Color.WHITE)
	else:
		# Show AP change preview: "+1→-2" (compact)
		var new_ap = _current_ap - queued_count
		var color = Color.YELLOW if new_ap >= 0 else Color.ORANGE_RED
		_ap_label.text = "%+d→%+d [%d]" % [_current_ap, new_ap, queued_count]
		_ap_label.add_theme_color_override("font_color", color)


func _input(event: InputEvent) -> void:
	"""Handle input for menu navigation"""
	# Wait for input delay to prevent accidental selection
	if not _can_accept_input:
		return

	# If submenu is open, let it handle input instead
	if submenu and is_instance_valid(submenu):
		return

	# DON'T consume battle_toggle_auto - let it pass through to BattleScene
	if event.is_action_pressed("battle_toggle_auto"):
		return

	# Handle input actions (gamepad + keyboard unified) - only in battle mode
	if battle_mode:
		if event.is_action_pressed("battle_advance"):
			# R button / Shift+Enter: Queue action (Advance mode)
			_handle_advance_input()
			get_viewport().set_input_as_handled()
			return

		# L button: Track press/release for hold-to-confirm
		if event.is_action_pressed("battle_defer"):
			var root = _get_root_menu()
			if root._queued_actions.size() == 0:
				# No queue — immediate defer, no timer needed
				_handle_defer_input()
				get_viewport().set_input_as_handled()
				return
			# Has queue — start hold timer for undo vs confirm
			root._l_button_pressed = true
			root._l_button_press_time = Time.get_ticks_msec() / 1000.0
			get_viewport().set_input_as_handled()
			return

		if event.is_action_released("battle_defer"):
			# L button released - check if it was a quick press
			var root = _get_root_menu()
			if root._l_button_pressed:
				root._l_button_pressed = false
				var hold_time = Time.get_ticks_msec() / 1000.0 - root._l_button_press_time
				if hold_time < L_HOLD_CONFIRM_TIME:
					# Quick press - do normal defer/undo behavior
					_handle_defer_input()
				# If hold_time >= L_HOLD_CONFIRM_TIME, it was already handled in _process
			get_viewport().set_input_as_handled()
			return

	# Keyboard navigation
	if event is InputEventKey and event.pressed and not event.echo:
		# Check for Shift+Enter/Z (also triggers Advance) - only in battle mode
		if battle_mode and event.keycode in [KEY_Z, KEY_ENTER, KEY_SPACE] and event.shift_pressed:
			_handle_advance_input()
			get_viewport().set_input_as_handled()
			return

		match event.keycode:
			KEY_UP:
				selected_index = (selected_index - 1) if selected_index > 0 else menu_items.size() - 1
				_play_move_sound()
				_update_selection()
				_auto_expand_submenu()
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				selected_index = (selected_index + 1) % menu_items.size()
				_play_move_sound()
				_update_selection()
				_auto_expand_submenu()
				get_viewport().set_input_as_handled()
			KEY_Z, KEY_ENTER, KEY_SPACE:
				var current_item = menu_items[selected_index] if selected_index >= 0 and selected_index < menu_items.size() else {}
				if current_item.has("submenu"):
					# Has submenu - expand it immediately
					_play_expand_sound()
					if not submenu:
						_do_open_submenu(selected_index, current_item)
				else:
					# No submenu - submit all queued actions + current
					_play_select_sound()
					_submit_actions()
				get_viewport().set_input_as_handled()
			KEY_X, KEY_ESCAPE:
				# Priority: close submenu first, then unadvance (undo one, battle mode only), then go back
				var root = _get_root_menu()
				if parent_menu:
					# We're in a submenu - close it and return to parent
					_play_move_sound()
					_cleanup_target_highlight()
					parent_menu.submenu = null
					queue_free()
				elif battle_mode and root._queued_actions.size() > 0:
					# At root with queue - undo ONE queued action (unadvance) - battle mode only
					_undo_last_action()
					# Also close any open submenu
					if submenu and is_instance_valid(submenu):
						submenu.queue_free()
						submenu = null
				elif is_root_menu and _can_go_back:
					# At root with no queue - go back to previous player
					_play_cancel_sound()
					go_back_requested.emit()
					force_close()
				elif is_root_menu and not battle_mode:
					# Non-battle root menu (shops, etc) - close on cancel
					_play_cancel_sound()
					force_close()
				# In battle mode at root with no queue and can't go back: B is a no-op
				get_viewport().set_input_as_handled()
			KEY_RIGHT:
				# For left-expanding: RIGHT goes back to parent
				# For right-expanding: RIGHT goes into submenu
				if expand_left:
					if parent_menu:
						_play_move_sound()
						queue_free()
					elif is_root_menu and not battle_mode:
						# Non-battle root menu - close on back
						_play_cancel_sound()
						force_close()
				else:
					if submenu:
						_play_move_sound()
						submenu.grab_focus()
				get_viewport().set_input_as_handled()
			KEY_LEFT:
				# For left-expanding: LEFT confirms selection or enters submenu
				# For right-expanding: LEFT goes back to parent
				if expand_left:
					var current_item = menu_items[selected_index] if selected_index >= 0 and selected_index < menu_items.size() else {}
					if current_item.has("submenu"):
						# Item has submenu - let auto-expand handle it
						_play_move_sound()
						_auto_expand_submenu()
					else:
						# No submenu - submit all queued + current
						_play_select_sound()
						_submit_actions()
				else:
					if parent_menu:
						_play_move_sound()
						queue_free()
				get_viewport().set_input_as_handled()

	# Handle gamepad navigation via input actions
	# Note: Check echo to prevent rapid-fire when holding d-pad
	if event.is_action_pressed("ui_up") and not event.is_echo():
		selected_index = (selected_index - 1) if selected_index > 0 else menu_items.size() - 1
		_play_move_sound()
		_update_selection()
		_auto_expand_submenu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") and not event.is_echo():
		selected_index = (selected_index + 1) % menu_items.size()
		_play_move_sound()
		_update_selection()
		_auto_expand_submenu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		var current_item = menu_items[selected_index] if selected_index >= 0 and selected_index < menu_items.size() else {}
		if current_item.has("submenu"):
			_play_expand_sound()
			if not submenu:
				_do_open_submenu(selected_index, current_item)
		else:
			_play_select_sound()
			_submit_actions()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		# Priority: close submenu first, then unadvance (undo one, battle mode only), then go back
		var root = _get_root_menu()
		if parent_menu:
			# We're in a submenu - close it and return to parent
			_play_move_sound()
			_cleanup_target_highlight()
			parent_menu.submenu = null
			queue_free()
		elif battle_mode and root._queued_actions.size() > 0:
			# At root with queue - undo ONE queued action (unadvance) - battle mode only
			_undo_last_action()
			# Also close any open submenu
			if submenu and is_instance_valid(submenu):
				submenu.queue_free()
				submenu = null
		elif is_root_menu and _can_go_back:
			# At root with no queue - go back to previous player
			_play_cancel_sound()
			go_back_requested.emit()
			force_close()
		elif is_root_menu and not battle_mode:
			# Non-battle root menu (shops, etc) - close on cancel
			_play_cancel_sound()
			force_close()
		# In battle mode at root with no queue and can't go back: B is a no-op
		get_viewport().set_input_as_handled()

	# D-pad LEFT = confirm/accept (for left-expanding menus), back (for right-expanding)
	elif event.is_action_pressed("ui_left") and not event.is_echo():
		if expand_left:
			var current_item = menu_items[selected_index] if selected_index >= 0 and selected_index < menu_items.size() else {}
			if current_item.has("submenu"):
				# Item has submenu - expand it
				_play_expand_sound()
				if not submenu:
					_do_open_submenu(selected_index, current_item)
			else:
				# No submenu - submit all queued + current
				_play_select_sound()
				_submit_actions()
		else:
			if parent_menu:
				_play_move_sound()
				_cleanup_target_highlight()
				parent_menu.submenu = null
				queue_free()
		get_viewport().set_input_as_handled()

	# D-pad RIGHT = back/cancel (for left-expanding menus), confirm (for right-expanding)
	elif event.is_action_pressed("ui_right") and not event.is_echo():
		if expand_left:
			# RIGHT = back for left-expanding menus
			if parent_menu:
				_play_move_sound()
				_cleanup_target_highlight()
				parent_menu.submenu = null
				queue_free()
			elif is_root_menu:
				# At root - same as cancel
				var root = _get_root_menu()
				if root._queued_actions.size() > 0:
					_undo_last_action()
					if submenu and is_instance_valid(submenu):
						submenu.queue_free()
						submenu = null
				elif _can_go_back:
					_play_cancel_sound()
					go_back_requested.emit()
					force_close()
				elif not battle_mode:
					# Non-battle root menu - close on back
					_play_cancel_sound()
					force_close()
		else:
			# RIGHT = confirm for right-expanding menus
			var current_item = menu_items[selected_index] if selected_index >= 0 and selected_index < menu_items.size() else {}
			if current_item.has("submenu"):
				_play_expand_sound()
				if not submenu:
					_do_open_submenu(selected_index, current_item)
			else:
				_play_select_sound()
				_submit_actions()
		get_viewport().set_input_as_handled()

	# Root menus don't close on click outside
	if is_root_menu:
		return

	# Mouse click outside menu (only after delay to prevent stray clicks)
	if event is InputEventMouseButton and _can_close_on_click:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var local_pos = get_local_mouse_position()
			if not Rect2(Vector2.ZERO, size).has_point(local_pos):
				# Check submenus
				if submenu:
					var sub_local = submenu.get_local_mouse_position()
					if Rect2(Vector2.ZERO, submenu.size).has_point(sub_local):
						return
				# Click outside - close submenu only
				if parent_menu:
					queue_free()
