extends Control
class_name BossSelectorMenu

## Boss Selector - Debug-mode boss battle launcher submenu for SettingsMenu.
## Follows RetroPanel border style and JukeboxMenu patterns.

signal closed()
signal boss_selected(boss_id: String)

## Every boss + miniboss, DERIVED from monsters.json at runtime (struktured 2026-07-25:
## "should be able to fight mordaine in the fight boss debug menu, and any boss for that matter").
## Hardcoded, this listed only the 20 Masterites — Mordaine, all four dragons, the Rat King and every
## spotlight duelist were unreachable, and nothing flagged the drift. Deriving it means a boss added to
## the data is fightable the same day.
var BOSSES: Array = []

## Group order. Story first (that's what playtesting reaches for), Masterites last (there are 20).
const GROUP_ORDER := ["Story", "Spotlight Duels", "Minibosses", "Medieval", "Suburban", "Industrial", "Futuristic", "Abstract"]
const DUEL_PREFIXES := ["fighter_", "cleric_", "rogue_", "mage_", "bard_"]


## Reads monsters.json and returns [{id, name, world}], grouped then sorted by level.
static func load_boss_roster() -> Array:
	var src := FileAccess.get_file_as_string("res://data/monsters.json")
	if src == "":
		push_warning("[BossSelector] monsters.json unreadable — boss list will be empty")
		return []
	var parsed = JSON.parse_string(src)
	if not (parsed is Dictionary):
		push_warning("[BossSelector] monsters.json did not parse to a Dictionary — boss list will be empty")
		return []
	var monsters = parsed.get("monsters", parsed)
	if not (monsters is Dictionary):
		return []

	var rows: Array = []
	for mid in monsters:
		var m = monsters[mid]
		if not (m is Dictionary):
			continue
		var is_boss: bool = bool(m.get("boss", false))
		var is_mini: bool = bool(m.get("miniboss", false))
		if not is_boss and not is_mini:
			continue
		rows.append({
			"id": str(mid),
			"name": str(m.get("name", mid)),
			"world": _group_for(str(mid), is_boss, is_mini),
			"level": int(m.get("level", 0)),
		})

	rows.sort_custom(func(a, b):
		var ga: int = GROUP_ORDER.find(a["world"])
		var gb: int = GROUP_ORDER.find(b["world"])
		if ga != gb:
			return ga < gb
		if a["level"] != b["level"]:
			return a["level"] < b["level"]
		return a["id"] < b["id"])
	return rows


static func _group_for(mid: String, is_boss: bool, is_mini: bool) -> String:
	if mid.begins_with("masterite_"):
		var parts := mid.split("_")
		return parts[parts.size() - 1].capitalize()
	for prefix in DUEL_PREFIXES:
		if mid.begins_with(prefix):
			return "Spotlight Duels"
	if is_mini and not is_boss:
		return "Minibosses"
	return "Story"

## How many rows to show at once in the scroll window
const VISIBLE_ROWS = 14
const ROW_HEIGHT = 32

## Style (matches SettingsMenu / JukeboxMenu)
const BG_COLOR = Color(0.05, 0.05, 0.1, 0.95)
const PANEL_COLOR = Color(0.1, 0.1, 0.15)
const BORDER_LIGHT = RetroPanel.BORDER_LIGHT
const BORDER_SHADOW = RetroPanel.BORDER_SHADOW
const SELECTED_COLOR = Color(0.2, 0.3, 0.5)
const TEXT_COLOR = Color(1.0, 1.0, 1.0)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const WORLD_HEADER_COLOR = Color(1.0, 0.8, 0.3)
const BOSS_NAME_COLOR = Color(0.9, 0.6, 0.6)

## UI State
var selected_index: int = 0
var scroll_offset: int = 0

## Node references
var _panel: Control
var _row_highlights: Array = []
var _row_labels: Array = []
var _row_world_labels: Array = []

## Flat display list: entries are either {"type": "header", "world": String}
## or {"type": "boss", "index": int} indexing into BOSSES
var _display_list: Array = []
## Indices in _display_list that are selectable boss entries
var _selectable_indices: Array = []


func _ready() -> void:
	_build_display_list()
	_build_ui()


func _build_display_list() -> void:
	if BOSSES.is_empty():
		BOSSES = load_boss_roster()
	_display_list.clear()
	_selectable_indices.clear()
	var last_world = ""
	for i in range(BOSSES.size()):
		var boss = BOSSES[i]
		if boss["world"] != last_world:
			_display_list.append({"type": "header", "world": boss["world"]})
			last_world = boss["world"]
		_selectable_indices.append(_display_list.size())
		_display_list.append({"type": "boss", "index": i})


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()
	_row_highlights.clear()
	_row_labels.clear()
	_row_world_labels.clear()

	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_panel = Control.new()
	_panel.position = Vector2(size.x * 0.15, size.y * 0.06)
	_panel.size = Vector2(size.x * 0.7, size.y * 0.88)
	add_child(_panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_COLOR
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(panel_bg)

	RetroPanel.add_border(_panel, _panel.size, BORDER_LIGHT, BORDER_SHADOW)

	var title = Label.new()
	title.text = "FIGHT BOSS"
	title.position = Vector2(16, 8)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	_panel.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "[DEBUG] Select a boss to fight  ·  L1/R1 page"
	subtitle.position = Vector2(16, 30)
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", DISABLED_COLOR)
	_panel.add_child(subtitle)

	var list_y: float = 52.0
	for i in range(VISIBLE_ROWS):
		var highlight = ColorRect.new()
		highlight.position = Vector2(8, list_y + i * ROW_HEIGHT)
		highlight.size = Vector2(_panel.size.x - 16, ROW_HEIGHT - 2)
		highlight.color = Color.TRANSPARENT
		highlight.name = "Row_%d" % i
		_panel.add_child(highlight)
		_row_highlights.append(highlight)

		var world_lbl = Label.new()
		world_lbl.position = Vector2(10, 6)
		world_lbl.add_theme_font_size_override("font_size", 10)
		world_lbl.add_theme_color_override("font_color", WORLD_HEADER_COLOR)
		world_lbl.name = "WorldLabel_%d" % i
		highlight.add_child(world_lbl)
		_row_world_labels.append(world_lbl)

		var lbl = Label.new()
		lbl.position = Vector2(10, 10)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", BOSS_NAME_COLOR)
		highlight.add_child(lbl)
		_row_labels.append(lbl)

		MenuMouseHelper.make_clickable(highlight, i, _panel.size.x - 16, ROW_HEIGHT - 2,
			_on_row_click.bind(i), _on_row_hover.bind(i))

	var scroll_up_lbl = Label.new()
	scroll_up_lbl.name = "ScrollUp"
	scroll_up_lbl.text = ""
	scroll_up_lbl.position = Vector2(_panel.size.x - 24, 52)
	scroll_up_lbl.add_theme_font_size_override("font_size", 12)
	scroll_up_lbl.add_theme_color_override("font_color", DISABLED_COLOR)
	_panel.add_child(scroll_up_lbl)

	var scroll_dn_lbl = Label.new()
	scroll_dn_lbl.name = "ScrollDown"
	scroll_dn_lbl.text = ""
	scroll_dn_lbl.position = Vector2(_panel.size.x - 24, 52 + VISIBLE_ROWS * ROW_HEIGHT - ROW_HEIGHT)
	scroll_dn_lbl.add_theme_font_size_override("font_size", 12)
	scroll_dn_lbl.add_theme_color_override("font_color", DISABLED_COLOR)
	_panel.add_child(scroll_dn_lbl)

	var footer = Label.new()
	footer.text = "Up/Down: Navigate   A: Fight   B: Back"
	footer.position = Vector2(16, _panel.size.y - 28)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", DISABLED_COLOR)
	_panel.add_child(footer)

	MenuMouseHelper.add_right_click_cancel(bg, _close_menu)

	_refresh_list()
	_update_selection()


func _refresh_list() -> void:
	var total = _display_list.size()
	for i in range(VISIBLE_ROWS):
		var list_idx = scroll_offset + i
		var highlight = _row_highlights[i]
		var lbl = _row_labels[i]
		var world_lbl = _row_world_labels[i]

		if list_idx < total:
			var entry = _display_list[list_idx]
			highlight.modulate.a = 1.0
			if entry["type"] == "header":
				world_lbl.text = "-- %s --" % entry["world"]
				world_lbl.position = Vector2(10, 6)
				lbl.text = ""
				lbl.position = Vector2(10, 10)
				highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				var boss = BOSSES[entry["index"]]
				world_lbl.text = boss["world"]
				world_lbl.position = Vector2(_panel.size.x - 110, 8)
				lbl.text = boss["name"]
				lbl.position = Vector2(10, 8)
				highlight.mouse_filter = Control.MOUSE_FILTER_PASS
		else:
			world_lbl.text = ""
			lbl.text = ""
			highlight.modulate.a = 0.0
			highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var up_lbl = _panel.get_node_or_null("ScrollUp")
	var dn_lbl = _panel.get_node_or_null("ScrollDown")
	if up_lbl:
		up_lbl.text = "^" if scroll_offset > 0 else ""
	if dn_lbl:
		dn_lbl.text = "v" if (scroll_offset + VISIBLE_ROWS) < total else ""


func _update_selection() -> void:
	for i in range(VISIBLE_ROWS):
		var list_idx = scroll_offset + i
		var is_selected = (list_idx == _get_display_index_for_selected())
		_row_highlights[i].color = SELECTED_COLOR if is_selected else Color.TRANSPARENT


func _get_display_index_for_selected() -> int:
	if selected_index < 0 or selected_index >= _selectable_indices.size():
		return -1
	return _selectable_indices[selected_index]


func _confirm_selection() -> void:
	if selected_index < 0 or selected_index >= _selectable_indices.size():
		return
	var list_idx = _selectable_indices[selected_index]
	var entry = _display_list[list_idx]
	if entry["type"] != "boss":
		return
	var boss = BOSSES[entry["index"]]
	if SoundManager:
		SoundManager.play_ui("menu_select")
	boss_selected.emit(boss["id"])
	queue_free()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_close_menu()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_up") and not event.is_echo():
		if selected_index > 0:
			selected_index -= 1
			_clamp_scroll()
			_refresh_list()
			_update_selection()
			if SoundManager:
				SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_down") and not event.is_echo():
		if selected_index < _selectable_indices.size() - 1:
			selected_index += 1
			_clamp_scroll()
			_refresh_list()
			_update_selection()
			if SoundManager:
				SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif MenuPaging.page_delta(event) != 0:
		# 46 entries once the list came from data — one row at a time is unusable.
		selected_index = clampi(selected_index + MenuPaging.page_delta(event) * MenuPaging.PAGE_ROWS, 0, _selectable_indices.size() - 1)
		_clamp_scroll()
		_refresh_list()
		_update_selection()
		if SoundManager:
			SoundManager.play_ui("menu_move")
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_confirm_selection()
		get_viewport().set_input_as_handled()


func _clamp_scroll() -> void:
	var display_idx = _get_display_index_for_selected()
	if display_idx < scroll_offset:
		scroll_offset = display_idx
	elif display_idx >= scroll_offset + VISIBLE_ROWS:
		scroll_offset = display_idx - VISIBLE_ROWS + 1
	scroll_offset = clampi(scroll_offset, 0, max(0, _display_list.size() - VISIBLE_ROWS))


func _on_row_click(local_row: int) -> void:
	var list_idx = scroll_offset + local_row
	if list_idx >= _display_list.size():
		return
	var entry = _display_list[list_idx]
	if entry["type"] != "boss":
		return
	var sel = _selectable_indices.find(list_idx)
	if sel < 0:
		return
	selected_index = sel
	_update_selection()
	_confirm_selection()


func _on_row_hover(local_row: int) -> void:
	var list_idx = scroll_offset + local_row
	if list_idx >= _display_list.size():
		return
	var entry = _display_list[list_idx]
	if entry["type"] != "boss":
		return
	var sel = _selectable_indices.find(list_idx)
	if sel < 0 or sel == selected_index:
		return
	selected_index = sel
	_clamp_scroll()
	_update_selection()
	if SoundManager:
		SoundManager.play_ui("menu_move")


func _close_menu() -> void:
	if SoundManager:
		SoundManager.play_ui("menu_close")
	closed.emit()
	queue_free()
