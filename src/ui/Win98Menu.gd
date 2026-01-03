extends Control
class_name Win98Menu

## Retro RPG Style Cascading Menu System
## Classic pixel-tile borders like FF/DQ style

signal item_selected(item_id: String, item_data: Variant)
signal menu_closed()
signal actions_submitted(actions: Array)  # For Advance mode - multiple actions
signal defer_requested()  # L button with no queue - defer turn

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
var _target_line: Line2D = null  # Line connecting to target
var _pending_target_pos: Vector2 = Vector2.ZERO  # Target position for line
var _queued_actions: Array = []  # Actions queued via Advance mode
var _max_queue_size: int = 4  # Max actions (limited by AP)

## Signals for target selection with position
signal target_selected(item_id: String, item_data: Variant, target_pos: Vector2)

## Pixel tile size
const TILE_SIZE = 4
const ITEM_HEIGHT = 16
const MENU_PADDING = 8
const SUBMENU_DELAY = 0.12  # Delay before submenu expands


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_setup_timers()
	_setup_audio()
	_build_menu()


func _setup_timers() -> void:
	"""Setup timers for animations"""
	# Submenu delay timer
	_submenu_timer = Timer.new()
	_submenu_timer.one_shot = true
	_submenu_timer.timeout.connect(_on_submenu_timer_timeout)
	add_child(_submenu_timer)

	# Cursor blink timer
	_cursor_blink_timer = Timer.new()
	_cursor_blink_timer.wait_time = 0.3
	_cursor_blink_timer.timeout.connect(_on_cursor_blink)
	add_child(_cursor_blink_timer)
	_cursor_blink_timer.start()

	# Target line (drawn at Control layer, not as child)
	_setup_target_line()


func _setup_target_line() -> void:
	"""Create the target line that connects menu to enemy/ally sprites"""
	_target_line = Line2D.new()
	_target_line.width = 3.0
	_target_line.default_color = Color(1.0, 1.0, 0.3, 0.9)  # Bright yellow
	_target_line.z_index = 99  # Just below menu
	_target_line.visible = false

	# Make it stand out
	_target_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_target_line.end_cap_mode = Line2D.LINE_CAP_ROUND

	# Add as sibling so it's not clipped by menu bounds
	call_deferred("_add_target_line_to_parent")


func _add_target_line_to_parent() -> void:
	"""Add target line as sibling for proper rendering"""
	if _target_line and get_parent():
		get_parent().add_child(_target_line)


func _update_target_line() -> void:
	"""Update target line to connect current selection to target"""
	if not _target_line or not is_instance_valid(_target_line):
		return

	# Get current item data
	if selected_index >= menu_items.size():
		_target_line.visible = false
		return

	var item = menu_items[selected_index]
	var item_data = item.get("data", null)

	# Check if item has target position
	var target_pos = Vector2.ZERO
	if item_data is Dictionary and item_data.has("target_pos"):
		target_pos = item_data.get("target_pos", Vector2.ZERO)

	if target_pos == Vector2.ZERO:
		_target_line.visible = false
		_pending_target_pos = Vector2.ZERO
		return

	# Calculate line start point (from menu item)
	var item_y = selected_index * ITEM_HEIGHT + TILE_SIZE + MENU_PADDING + ITEM_HEIGHT / 2
	var start_pos: Vector2
	if expand_left:
		# Line starts from left edge of menu
		start_pos = global_position + Vector2(0, item_y)
	else:
		# Line starts from right edge
		start_pos = global_position + Vector2(size.x, item_y)

	# Store for animation fade
	_pending_target_pos = target_pos

	# Draw the line - straight with arrow-like indicator at target
	_target_line.clear_points()
	_target_line.add_point(start_pos)

	# Add midpoint for slight curve
	var midpoint = (start_pos + target_pos) / 2
	midpoint.y -= 20  # Slight upward curve
	_target_line.add_point(midpoint)

	# Add a few points near target to create arrow effect
	var dir_to_target = (target_pos - midpoint).normalized()
	var arrow_base = target_pos - dir_to_target * 12
	_target_line.add_point(arrow_base)
	_target_line.add_point(target_pos)

	_target_line.visible = true


func _fade_target_line(on_complete: Callable = Callable()) -> void:
	"""Fade out the target line with animation"""
	if not _target_line or not is_instance_valid(_target_line):
		if on_complete.is_valid():
			on_complete.call()
		return

	if not _target_line.visible:
		if on_complete.is_valid():
			on_complete.call()
		return

	var tween = create_tween()
	tween.tween_property(_target_line, "modulate:a", 0.0, 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		if is_instance_valid(_target_line):
			_target_line.visible = false
			_target_line.modulate.a = 1.0  # Reset for next use
		if on_complete.is_valid():
			on_complete.call()
	)


func _setup_audio() -> void:
	"""Setup audio for menu sounds"""
	_audio_player = AudioStreamPlayer.new()
	_audio_player.volume_db = -10.0
	add_child(_audio_player)


func _play_move_sound() -> void:
	"""Play sound when moving between menu items"""
	if not is_instance_valid(_audio_player):
		return

	# Generate a simple blip sound
	var sample_rate = 22050
	var duration = 0.03
	var frequency = 800.0

	var generator = AudioStreamGenerator.new()
	generator.mix_rate = sample_rate

	_audio_player.stream = generator
	_audio_player.play()

	var playback = _audio_player.get_stream_playback()
	if not playback:
		return
	var samples = int(sample_rate * duration)
	for i in range(samples):
		var t = float(i) / sample_rate
		var sample = sin(t * frequency * TAU) * (1.0 - t / duration)
		playback.push_frame(Vector2(sample, sample) * 0.3)


func _play_select_sound() -> void:
	"""Play sound when selecting an item"""
	if not is_instance_valid(_audio_player):
		return

	var sample_rate = 22050
	var duration = 0.06
	var frequency = 1200.0

	var generator = AudioStreamGenerator.new()
	generator.mix_rate = sample_rate

	_audio_player.stream = generator
	_audio_player.play()

	var playback = _audio_player.get_stream_playback()
	if not playback:
		return
	var samples = int(sample_rate * duration)
	for i in range(samples):
		var t = float(i) / sample_rate
		# Rising pitch for select
		var freq = frequency + (t * 400.0)
		var sample = sin(t * freq * TAU) * (1.0 - t / duration)
		playback.push_frame(Vector2(sample, sample) * 0.3)


func _play_expand_sound() -> void:
	"""Play sound when submenu expands"""
	if not is_instance_valid(_audio_player):
		return

	var sample_rate = 22050
	var duration = 0.05
	var frequency = 600.0

	var generator = AudioStreamGenerator.new()
	generator.mix_rate = sample_rate

	_audio_player.stream = generator
	_audio_player.play()

	var playback = _audio_player.get_stream_playback()
	if not playback:
		return
	var samples = int(sample_rate * duration)
	for i in range(samples):
		var t = float(i) / sample_rate
		var sample = sin(t * frequency * TAU) * (1.0 - t / duration) * 0.5
		sample += sin(t * frequency * 1.5 * TAU) * (1.0 - t / duration) * 0.3
		playback.push_frame(Vector2(sample, sample) * 0.25)


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
	if selected_index >= menu_items.size():
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

	# Calculate menu size
	var menu_width = 140
	var menu_height = MENU_PADDING * 2 + menu_items.size() * ITEM_HEIGHT + TILE_SIZE * 2

	# Create the menu texture with pixel borders
	var menu_panel = _create_retro_panel(menu_width, menu_height)
	add_child(menu_panel)

	# Items container
	var items_container = VBoxContainer.new()
	items_container.position = Vector2(MENU_PADDING + TILE_SIZE, MENU_PADDING + TILE_SIZE)
	items_container.add_theme_constant_override("separation", 0)
	menu_panel.add_child(items_container)

	# Create menu items
	for i in range(menu_items.size()):
		var item = menu_items[i]
		var item_row = _create_menu_item(i, item)
		items_container.add_child(item_row)

	# Set size and position
	custom_minimum_size = Vector2(menu_width, menu_height)
	size = Vector2(menu_width, menu_height)
	position = anchor_position

	# Ensure menu stays on screen
	await get_tree().process_frame
	_clamp_to_screen()

	# Highlight first item and auto-expand if it has submenu
	_update_selection()
	_auto_expand_submenu()

	# Allow input after a short delay to prevent stray key presses
	await get_tree().create_timer(0.15).timeout
	_can_accept_input = true
	await get_tree().create_timer(0.1).timeout
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


func _create_menu_item(index: int, item: Dictionary) -> Control:
	"""Create a single menu item row"""
	var row = Control.new()
	row.custom_minimum_size = Vector2(120, ITEM_HEIGHT)
	row.name = "Item%d" % index

	# Selection highlight border (top line)
	var highlight_top = ColorRect.new()
	highlight_top.name = "HighlightTop"
	highlight_top.color = style.cursor.lightened(0.3)
	highlight_top.position = Vector2(-4, 0)
	highlight_top.size = Vector2(128, 1)
	highlight_top.visible = false
	row.add_child(highlight_top)

	# Selection highlight background (hidden by default)
	var highlight = ColorRect.new()
	highlight.name = "Highlight"
	highlight.color = style.highlight_bg.lightened(0.1)
	highlight.position = Vector2(-4, 1)
	highlight.size = Vector2(128, ITEM_HEIGHT - 2)
	highlight.visible = false
	row.add_child(highlight)

	# Selection highlight border (bottom line)
	var highlight_bottom = ColorRect.new()
	highlight_bottom.name = "HighlightBottom"
	highlight_bottom.color = style.cursor.darkened(0.2)
	highlight_bottom.position = Vector2(-4, ITEM_HEIGHT - 1)
	highlight_bottom.size = Vector2(128, 1)
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
	button.size = Vector2(120, ITEM_HEIGHT)
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

	# Update target line to point at selected enemy/ally
	_update_target_line()


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
	if _submenu_timer:
		_submenu_timer.stop()

	# Close existing submenu first
	if submenu:
		submenu.queue_free()
		submenu = null

	if selected_index >= menu_items.size():
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
		submenu_pos.x = global_position.x - 140 - 4  # Menu width + gap
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

	# Animate slide and fade in
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(submenu, "position", submenu_pos, 0.1).set_ease(Tween.EASE_OUT)
	tween.tween_property(submenu, "modulate:a", 1.0, 0.08)

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
	if submenu:
		submenu.queue_free()
		submenu = null

	if parent_menu:
		parent_menu.close_all()
	else:
		# Only close if not the root menu, or if forced
		if not is_root_menu:
			_cleanup_target_line()
			menu_closed.emit()
			queue_free()


func force_close() -> void:
	"""Force close the menu tree, even root menus"""
	if submenu:
		submenu.queue_free()
		submenu = null
	if parent_menu:
		parent_menu.force_close()
	else:
		_cleanup_target_line()
		menu_closed.emit()
		queue_free()


func _cleanup_target_line() -> void:
	"""Remove target line from scene"""
	if _target_line and is_instance_valid(_target_line):
		_target_line.queue_free()
		_target_line = null


## Advance Mode Functions

func _handle_advance_input() -> void:
	"""Handle R button / Shift+Enter - queue current action"""
	var current_item = menu_items[selected_index] if selected_index < menu_items.size() else {}

	if current_item.has("submenu"):
		# Has submenu - expand it to select target
		_play_expand_sound()
		if not submenu:
			_do_open_submenu(selected_index, current_item)
		return

	if current_item.get("disabled", false):
		return

	# Queue the current action
	_queue_current_action(current_item)


func _handle_defer_input() -> void:
	"""Handle L button - undo last queued action, or defer if no queue"""
	if _queued_actions.size() > 0:
		# Undo last queued action
		_undo_last_action()
	else:
		# No actions queued - emit defer signal
		_play_select_sound()
		defer_requested.emit()
		_close_entire_tree()


func _queue_current_action(item: Dictionary) -> void:
	"""Add action to queue (Advance mode)"""
	if _queued_actions.size() >= _max_queue_size:
		# Queue full - play error sound or ignore
		return

	var action = {
		"id": item.get("id", ""),
		"data": item.get("data", null),
		"label": item.get("label", "")
	}
	_queued_actions.append(action)
	_play_expand_sound()  # Distinct sound for queuing
	# TODO: Visual feedback - show queue count on menu


func _undo_last_action() -> void:
	"""Remove last action from queue"""
	if _queued_actions.size() > 0:
		_queued_actions.pop_back()
		_play_move_sound()


func _cancel_all_queued() -> void:
	"""Clear entire action queue"""
	_queued_actions.clear()


func _submit_actions() -> void:
	"""Submit all queued actions + current selection"""
	var current_item = menu_items[selected_index] if selected_index < menu_items.size() else {}

	if current_item.get("disabled", false):
		return

	if current_item.has("submenu"):
		# Can't submit a submenu item directly
		return

	# Build final action list
	var all_actions = _queued_actions.duplicate()
	all_actions.append({
		"id": current_item.get("id", ""),
		"data": current_item.get("data", null),
		"label": current_item.get("label", "")
	})

	_queued_actions.clear()

	if all_actions.size() == 1:
		# Single action - use normal item_selected signal
		_fade_target_line(func():
			item_selected.emit(all_actions[0].id, all_actions[0].data)
			_close_entire_tree()
		)
	else:
		# Multiple actions - use actions_submitted signal for Brave
		_fade_target_line(func():
			actions_submitted.emit(all_actions)
			_close_entire_tree()
		)


func get_queue_count() -> int:
	"""Get number of queued actions"""
	return _queued_actions.size()


func set_max_queue_size(max_size: int) -> void:
	"""Set max queue size based on available AP"""
	_max_queue_size = max_size


func _input(event: InputEvent) -> void:
	"""Handle input for menu navigation"""
	# Wait for input delay to prevent accidental selection
	if not _can_accept_input:
		return

	# If submenu is open, let it handle input instead
	if submenu and is_instance_valid(submenu):
		return

	# Handle input actions (gamepad + keyboard unified)
	if event.is_action_pressed("battle_advance"):
		# R button / Shift+Enter: Queue action (Advance mode)
		_handle_advance_input()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("battle_defer"):
		# L button: Undo last queued action, or Defer if no queue
		_handle_defer_input()
		get_viewport().set_input_as_handled()
		return

	# Keyboard navigation
	if event is InputEventKey and event.pressed and not event.echo:
		# Check for Shift+Enter/Z (also triggers Advance)
		if event.keycode in [KEY_Z, KEY_ENTER, KEY_SPACE] and event.shift_pressed:
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
				var current_item = menu_items[selected_index] if selected_index < menu_items.size() else {}
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
				# Cancel all queued actions, close submenu if any
				if _queued_actions.size() > 0:
					_cancel_all_queued()
					_play_move_sound()
				elif parent_menu:
					_play_move_sound()
					queue_free()
				get_viewport().set_input_as_handled()
			KEY_RIGHT:
				# For left-expanding: RIGHT goes back to parent
				# For right-expanding: RIGHT goes into submenu
				if expand_left:
					if parent_menu:
						_play_move_sound()
						queue_free()
				else:
					if submenu:
						_play_move_sound()
						submenu.grab_focus()
				get_viewport().set_input_as_handled()
			KEY_LEFT:
				# For left-expanding: LEFT confirms selection or enters submenu
				# For right-expanding: LEFT goes back to parent
				if expand_left:
					var current_item = menu_items[selected_index] if selected_index < menu_items.size() else {}
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
	if event.is_action_pressed("ui_up"):
		selected_index = (selected_index - 1) if selected_index > 0 else menu_items.size() - 1
		_play_move_sound()
		_update_selection()
		_auto_expand_submenu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		selected_index = (selected_index + 1) % menu_items.size()
		_play_move_sound()
		_update_selection()
		_auto_expand_submenu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		var current_item = menu_items[selected_index] if selected_index < menu_items.size() else {}
		if current_item.has("submenu"):
			_play_expand_sound()
			if not submenu:
				_do_open_submenu(selected_index, current_item)
		else:
			_play_select_sound()
			_submit_actions()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if _queued_actions.size() > 0:
			_cancel_all_queued()
			_play_move_sound()
		elif parent_menu:
			_play_move_sound()
			queue_free()
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
