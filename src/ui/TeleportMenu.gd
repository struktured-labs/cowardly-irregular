extends Control
class_name TeleportMenu

## TeleportMenu — debug-only teleport destination picker.
## Reusable from OverworldMenu and SettingsMenu (and any future entry point).
## Supports gamepad, keyboard, AND mouse — fully accessible per project rule.
##
## Emits `teleport_requested(map_id, spawn_point)` when the user picks a
## destination. Caller should connect, close us via `closed` (or directly
## emit it), and route the request to GameLoop._on_teleport_requested.

signal teleport_requested(map_id: String, spawn_point: String)
signal closed()

const DESTINATIONS: Array = [
	# --- World 1: Medieval ---
	{"id": "overworld",              "label": "Medieval Overworld",   "spawn": "default",     "section": "World 1: Medieval"},
	{"id": "harmonia_village",       "label": "Harmonia Village",     "spawn": "default",     "section": ""},
	{"id": "whispering_cave",        "label": "Whispering Cave",      "spawn": "default",     "section": ""},
	{"id": "castle_harmonia",        "label": "Castle Harmonia (Mordaine)", "spawn": "castle_entrance", "section": ""},
	# --- World 2: Suburban ---
	{"id": "suburban_overworld",     "label": "Suburban Sprawl",      "spawn": "entrance",    "section": "World 2: Suburban"},
	{"id": "maple_heights_village",  "label": "Maple Heights",        "spawn": "default",     "section": ""},
	{"id": "suburban_underground",   "label": "Suburban Underground", "spawn": "default",     "section": ""},
	# --- World 3: Steampunk ---
	{"id": "steampunk_overworld",    "label": "Steampunk Region",     "spawn": "default",     "section": "World 3: Steampunk"},
	{"id": "brasston_village",       "label": "Brasston",             "spawn": "default",     "section": ""},
	{"id": "steampunk_mechanism",    "label": "Steampunk Mechanism",  "spawn": "default",     "section": ""},
	# --- World 4: Industrial ---
	{"id": "industrial_overworld",   "label": "Industrial Zone",      "spawn": "entrance",    "section": "World 4: Industrial"},
	{"id": "rivet_row_village",      "label": "Rivet Row",            "spawn": "default",     "section": ""},
	{"id": "assembly_core",          "label": "Assembly Core",        "spawn": "default",     "section": ""},
	# --- World 5: Futuristic ---
	{"id": "futuristic_overworld",   "label": "Futuristic Plane",     "spawn": "entrance",    "section": "World 5: Futuristic"},
	{"id": "node_prime_village",     "label": "Node Prime",           "spawn": "default",     "section": ""},
	{"id": "root_process",           "label": "Root Process",         "spawn": "default",     "section": ""},
	# --- World 6: Abstract ---
	{"id": "abstract_overworld",     "label": "Abstract Domain",      "spawn": "entrance",    "section": "World 6: Abstract"},
	{"id": "vertex_village",         "label": "The Vertex",           "spawn": "default",     "section": ""},
	{"id": "null_chamber",           "label": "Null Chamber",         "spawn": "default",     "section": ""},
	# --- Dragon caves (W2 sub-dungeons) ---
	{"id": "ice_dragon_cave",        "label": "Ice Dragon Cave",      "spawn": "default",     "section": "Dragon Caves"},
	{"id": "fire_dragon_cave",       "label": "Fire Dragon Cave",     "spawn": "default",     "section": ""},
	{"id": "shadow_dragon_cave",     "label": "Shadow Dragon Cave",   "spawn": "default",     "section": ""},
	{"id": "lightning_dragon_cave",  "label": "Lightning Dragon Cave","spawn": "default",     "section": ""},
	# --- Other villages ---
	{"id": "frosthold_village",      "label": "Frosthold Village",    "spawn": "default",     "section": "More Villages"},
	{"id": "eldertree_village",      "label": "Eldertree Village",    "spawn": "default",     "section": ""},
	{"id": "grimhollow_village",     "label": "Grimhollow Village",   "spawn": "default",     "section": ""},
	{"id": "sandrift_village",       "label": "Sandrift Village",     "spawn": "default",     "section": ""},
	{"id": "ironhaven_village",      "label": "Ironhaven Village",    "spawn": "default",     "section": ""},
	# --- Interiors ---
	{"id": "tavern_interior",        "label": "Tavern (Harmonia)",    "spawn": "default",     "section": "Interiors"},
]

const ROW_HEIGHT: int = 26
const SECTION_HEADER_HEIGHT: int = 24
const ROW_FONT_SIZE: int = 13
const SECTION_FONT_SIZE: int = 12
const ITEM_PADDING_X: int = 24

const BG_COLOR = Color(0.05, 0.05, 0.10, 0.95)
const PANEL_COLOR = Color(0.10, 0.10, 0.15)
const BORDER_LIGHT = RetroPanel.BORDER_LIGHT
const BORDER_SHADOW = RetroPanel.BORDER_SHADOW
const SELECTED_COLOR = Color(0.20, 0.30, 0.50)
const TEXT_COLOR = Color(1.00, 1.00, 1.00)
const SECTION_COLOR = Color(0.85, 0.75, 0.30)
const DISABLED_COLOR = Color(0.40, 0.40, 0.40)

var _selected: int = 0
var _row_refs: Array = []          # Control nodes per destination
var _highlight_refs: Array = []    # ColorRect highlight per destination
var _cursor_refs: Array = []       # Cursor label per destination
var _row_global_y: Array = []      # Y position (panel-local) per destination, for scroll
var _scroll_offset: float = 0.0
var _content_height: float = 0.0
var _viewport_height: float = 0.0
var _scroll: ScrollContainer
var _content: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()
	_row_refs.clear()
	_highlight_refs.clear()
	_cursor_refs.clear()
	_row_global_y.clear()

	# Full-screen dim background; right-click to cancel.
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	MenuMouseHelper.add_right_click_cancel(bg, _close)

	# Panel — centered, slightly less than full screen for breathing room
	var panel = Control.new()
	panel.position = Vector2(size.x * 0.18, size.y * 0.06)
	panel.size = Vector2(size.x * 0.64, size.y * 0.88)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(panel_bg)
	RetroPanel.add_border(panel, panel.size, BORDER_LIGHT, BORDER_SHADOW)

	# Title
	var title = Label.new()
	title.text = "DEBUG TELEPORT"
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color.YELLOW)
	panel.add_child(title)

	# Subtitle / instructions (mention all input methods)
	var sub = Label.new()
	sub.text = "Pick a destination — ↑/↓ or Mouse-wheel/Click,  Enter/A/Click to warp,  Esc/B/RClick back"
	sub.position = Vector2(16, 32)
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(sub)

	# Scroll container (so list works at any vertical resolution)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(8, 56)
	_scroll.size = Vector2(panel.size.x - 16, panel.size.y - 80)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(_scroll)

	_content = Control.new()
	_content.custom_minimum_size = Vector2(panel.size.x - 32, 0)  # Width minus a bit for scrollbar
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_content)

	# Build rows + section headers
	var y: float = 4.0
	var current_section: String = ""
	for i in range(DESTINATIONS.size()):
		var dest = DESTINATIONS[i]
		var section: String = dest.get("section", "")
		if section != "" and section != current_section:
			# Section header
			var header = Label.new()
			header.text = "── %s ──" % section
			header.position = Vector2(8, y)
			header.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
			header.add_theme_color_override("font_color", SECTION_COLOR)
			_content.add_child(header)
			y += SECTION_HEADER_HEIGHT
			current_section = section
		_row_global_y.append(y)
		_add_row(i, y)
		y += ROW_HEIGHT

	_content.custom_minimum_size = Vector2(panel.size.x - 32, y + 8)
	_content_height = y + 8
	_viewport_height = _scroll.size.y

	_update_selection()


func _add_row(idx: int, y: float) -> void:
	var dest = DESTINATIONS[idx]
	var item = Control.new()
	item.position = Vector2(8, y)
	item.size = Vector2(_content.custom_minimum_size.x - 16, ROW_HEIGHT - 2)
	item.mouse_filter = Control.MOUSE_FILTER_STOP

	var hl = ColorRect.new()
	hl.color = Color.TRANSPARENT
	hl.size = item.size
	item.add_child(hl)

	var cursor = Label.new()
	cursor.text = "  "
	cursor.position = Vector2(4, 2)
	cursor.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	cursor.add_theme_color_override("font_color", Color.YELLOW)
	item.add_child(cursor)

	var label = Label.new()
	label.text = dest["label"]
	label.position = Vector2(ITEM_PADDING_X, 2)
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	item.add_child(label)

	# Show map_id in light gray, right-aligned, useful as debug reference
	var id_label = Label.new()
	id_label.text = dest["id"]
	id_label.position = Vector2(item.size.x - 220, 2)
	id_label.size = Vector2(216, ROW_HEIGHT - 4)
	id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	id_label.add_theme_font_size_override("font_size", 10)
	id_label.add_theme_color_override("font_color", DISABLED_COLOR)
	item.add_child(id_label)

	# Per-row mouse: hover + click both work
	MenuMouseHelper.make_clickable(item, idx, int(item.size.x), ROW_HEIGHT - 2,
		_on_row_click.bind(idx), _on_row_hover.bind(idx))

	_content.add_child(item)
	_row_refs.append(item)
	_highlight_refs.append(hl)
	_cursor_refs.append(cursor)


func _input(event: InputEvent) -> void:
	# Key + gamepad navigation; mouse handled per-row via MenuMouseHelper
	if event.is_action_pressed("ui_up") and not event.is_echo():
		_move(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") and not event.is_echo():
		_move(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_up") and not event.is_echo():
		_move(-8)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_down") and not event.is_echo():
		_move(8)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_home") and not event.is_echo():
		_selected = 0
		_update_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_end") and not event.is_echo():
		_selected = DESTINATIONS.size() - 1
		_update_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_pick()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close()
		get_viewport().set_input_as_handled()


func _move(delta: int) -> void:
	var n = DESTINATIONS.size()
	_selected = ((_selected + delta) % n + n) % n
	_update_selection()
	if SoundManager:
		SoundManager.play_ui("menu_move")


func _update_selection() -> void:
	for i in range(_highlight_refs.size()):
		_highlight_refs[i].color = SELECTED_COLOR if i == _selected else Color.TRANSPARENT
		_cursor_refs[i].text = "▶ " if i == _selected else "  "
	# Auto-scroll to keep selection visible
	if _scroll and _selected < _row_global_y.size():
		var row_y: float = _row_global_y[_selected]
		var view_top = _scroll.scroll_vertical
		var view_bot = view_top + _viewport_height - ROW_HEIGHT
		if row_y < view_top:
			_scroll.scroll_vertical = int(row_y - 8)
		elif row_y > view_bot:
			_scroll.scroll_vertical = int(row_y - _viewport_height + ROW_HEIGHT + 8)


func _pick() -> void:
	var dest = DESTINATIONS[_selected]
	print("[TELEPORT] Warping to: %s (%s)" % [dest["label"], dest["id"]])
	if SoundManager:
		SoundManager.play_ui("menu_select")
	teleport_requested.emit(dest["id"], dest["spawn"])
	closed.emit()
	queue_free()


func _on_row_click(idx: int) -> void:
	_selected = idx
	_update_selection()
	_pick()


func _on_row_hover(idx: int) -> void:
	if idx != _selected:
		_selected = idx
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")


func _close() -> void:
	if SoundManager:
		SoundManager.play_ui("menu_cancel")
	closed.emit()
	queue_free()
