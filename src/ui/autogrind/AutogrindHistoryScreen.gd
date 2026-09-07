extends Control
class_name AutogrindHistoryScreen

## Session-history viewer — reads AutogrindSystem.get_session_history() and renders
## every persisted grind entry as a scrollable list. Selecting an entry opens a
## detail panel on the right. Data source: user://autogrind_history.json (already
## written per-session by AutogrindSystem._record_session).

signal closed()

const BG_COLOR = Color(0.05, 0.04, 0.08, 0.94)
const PANEL_BG = Color(0.06, 0.05, 0.10)
const BORDER_LIGHT = Color(0.5, 0.4, 0.6)
const BORDER_SHADOW = Color(0.2, 0.15, 0.25)
const HEADER_COLOR = Color(1.0, 1.0, 0.4)
const LABEL_COLOR = Color(0.6, 0.6, 0.7)
const VALUE_COLOR = Color(0.4, 0.9, 0.4)
const BAD_COLOR = Color(0.9, 0.3, 0.3)
const ACCENT_COLOR = Color(0.9, 0.7, 1.0)
const SELECTION_BG = Color(0.15, 0.12, 0.22)

var _entries: Array = []
var _selected_index: int = 0
var _list: ItemList = null
var _detail_container: VBoxContainer = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	# Newest-first for the UI (persistence stores oldest-first).
	var raw := AutogrindSystem.get_session_history() if AutogrindSystem else []
	_entries = raw.duplicate()
	_entries.reverse()
	_build_ui()


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x == 0 or vp_size.y == 0:
		vp_size = Vector2(1280, 720)

	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel_w = min(vp_size.x - 80.0, 900.0)
	var panel_h = min(vp_size.y - 80.0, 600.0)
	var panel = Control.new()
	panel.position = Vector2((vp_size.x - panel_w) / 2.0, (vp_size.y - panel_h) / 2.0)
	panel.size = Vector2(panel_w, panel_h)
	add_child(panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_BG
	panel_bg.size = panel.size
	panel.add_child(panel_bg)
	_add_border(panel, panel.size)

	var title = Label.new()
	title.text = "AUTOGRIND HISTORY"
	title.position = Vector2(20, 12)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	panel.add_child(title)

	var sub = Label.new()
	sub.text = "%d past sessions on record (newest first)" % _entries.size()
	sub.position = Vector2(20, 40)
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", LABEL_COLOR)
	panel.add_child(sub)

	var sep = ColorRect.new()
	sep.color = BORDER_LIGHT
	sep.position = Vector2(16, 62)
	sep.size = Vector2(panel_w - 32, 1)
	panel.add_child(sep)

	if _entries.is_empty():
		var empty = Label.new()
		empty.text = "No grind sessions yet.\nComplete an autogrind run to fill this list."
		empty.position = Vector2(0, panel_h / 2.0 - 20.0)
		empty.size = Vector2(panel_w, 40)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", LABEL_COLOR)
		panel.add_child(empty)
	else:
		_build_split_view(panel, Vector2(16, 70), Vector2(panel_w - 32, panel_h - 110))

	var dismiss_lbl = Label.new()
	dismiss_lbl.text = "Press B or Esc to return"
	dismiss_lbl.position = Vector2(0, panel_h - 26)
	dismiss_lbl.size = Vector2(panel_w, 20)
	dismiss_lbl.add_theme_font_size_override("font_size", 11)
	dismiss_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	dismiss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(dismiss_lbl)


func _build_split_view(parent: Control, pos: Vector2, box_size: Vector2) -> void:
	var list_w = box_size.x * 0.45
	var detail_w = box_size.x - list_w - 12.0

	_list = ItemList.new()
	_list.position = pos
	_list.size = Vector2(list_w, box_size.y)
	_list.add_theme_font_size_override("font_size", 12)
	_list.add_theme_color_override("font_color", VALUE_COLOR)
	_list.add_theme_color_override("font_selected_color", HEADER_COLOR)
	for entry in _entries:
		_list.add_item(_format_list_row(entry))
	if _list.item_count > 0:
		_list.select(0)
	_list.item_selected.connect(_on_item_selected)
	parent.add_child(_list)

	_detail_container = VBoxContainer.new()
	_detail_container.position = Vector2(pos.x + list_w + 12.0, pos.y)
	_detail_container.size = Vector2(detail_w, box_size.y)
	_detail_container.add_theme_constant_override("separation", 4)
	parent.add_child(_detail_container)

	_render_detail(0)


func _on_item_selected(idx: int) -> void:
	_selected_index = idx
	_render_detail(idx)


func _render_detail(idx: int) -> void:
	if _detail_container == null:
		return
	for child in _detail_container.get_children():
		child.queue_free()
	if idx < 0 or idx >= _entries.size():
		return

	var e: Dictionary = _entries[idx]
	_add_detail_header(str(e.get("timestamp", "?")))
	_add_detail_row("Region", str(e.get("region", "-")), ACCENT_COLOR)
	_add_detail_row("Stopped", str(e.get("reason", "-")), LABEL_COLOR)

	var duration_sec: float = float(e.get("duration_sec", 0.0))
	var dur_min: int = int(duration_sec) / 60
	var dur_sec: int = int(duration_sec) % 60
	_add_detail_row("Duration", "%d:%02d" % [dur_min, dur_sec], VALUE_COLOR)

	_add_detail_row("Battles", str(e.get("battles", 0)), VALUE_COLOR)
	_add_detail_row("Total EXP", str(e.get("total_exp", 0)), VALUE_COLOR)
	_add_detail_row("Total Gold", str(e.get("gold", 0)), VALUE_COLOR)
	_add_detail_row("EXP / Min", "%.1f" % float(e.get("exp_per_min", 0.0)), VALUE_COLOR)
	_add_detail_row("Efficiency", "%.1fx" % float(e.get("efficiency", 1.0)), VALUE_COLOR)

	var corruption: float = float(e.get("corruption", 0.0))
	var corruption_color: Color = BAD_COLOR if corruption > 2.0 else VALUE_COLOR
	_add_detail_row("Corruption", "%.2f" % corruption, corruption_color)

	var collapses: int = int(e.get("collapses", 0))
	var collapses_color: Color = BAD_COLOR if collapses > 0 else VALUE_COLOR
	_add_detail_row("Collapses", str(collapses), collapses_color)

	var permadeaths: int = int(e.get("permadeaths", 0))
	if permadeaths > 0:
		_add_detail_row("Permadeaths", str(permadeaths), BAD_COLOR)

	var items_consumed: Dictionary = e.get("items_consumed", {})
	if not items_consumed.is_empty():
		var parts: Array = []
		for item_id in items_consumed:
			parts.append("%s x%d" % [str(item_id), int(items_consumed[item_id])])
		_add_detail_row("Items Used", ", ".join(parts), LABEL_COLOR)


func _add_detail_header(text: String) -> void:
	var header = Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", HEADER_COLOR)
	_detail_container.add_child(header)
	var sep = ColorRect.new()
	sep.color = BORDER_LIGHT
	sep.custom_minimum_size = Vector2(_detail_container.size.x, 1)
	_detail_container.add_child(sep)


func _add_detail_row(label_text: String, value_text: String, value_color: Color) -> void:
	var row = HBoxContainer.new()
	row.custom_minimum_size = Vector2(_detail_container.size.x, 20)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(110, 20)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", LABEL_COLOR)
	row.add_child(lbl)

	var val = Label.new()
	val.text = value_text
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.autowrap_mode = TextServer.AUTOWRAP_WORD
	val.add_theme_font_size_override("font_size", 12)
	val.add_theme_color_override("font_color", value_color)
	row.add_child(val)

	_detail_container.add_child(row)


func _format_list_row(entry: Dictionary) -> String:
	var timestamp: String = str(entry.get("timestamp", "?"))
	var battles: int = int(entry.get("battles", 0))
	var exp_val: int = int(entry.get("total_exp", 0))
	var region: String = str(entry.get("region", "-"))
	# Trim ISO timestamps to date-only for the list row (detail shows the full stamp)
	var short_ts := timestamp.substr(0, 10) if timestamp.length() >= 10 else timestamp
	return "%s  %s  %d btls  %d EXP" % [short_ts, region, battles, exp_val]


func _add_border(parent: Control, panel_size: Vector2) -> void:
	var top = ColorRect.new()
	top.color = BORDER_LIGHT
	top.size = Vector2(panel_size.x, 2)
	parent.add_child(top)
	var left_b = ColorRect.new()
	left_b.color = BORDER_LIGHT
	left_b.size = Vector2(2, panel_size.y)
	parent.add_child(left_b)
	var bottom = ColorRect.new()
	bottom.color = BORDER_SHADOW
	bottom.position = Vector2(0, panel_size.y - 2)
	bottom.size = Vector2(panel_size.x, 2)
	parent.add_child(bottom)
	var right_b = ColorRect.new()
	right_b.color = BORDER_SHADOW
	right_b.position = Vector2(panel_size.x - 2, 0)
	right_b.size = Vector2(2, panel_size.y)
	parent.add_child(right_b)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_X, KEY_ESCAPE]:
			closed.emit()
			get_viewport().set_input_as_handled()
