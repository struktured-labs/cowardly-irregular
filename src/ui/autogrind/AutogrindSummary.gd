extends Control
class_name AutogrindSummary

signal dismissed()

const BG_COLOR = Color(0.05, 0.04, 0.08, 0.92)
const PANEL_BG = Color(0.06, 0.05, 0.10)
const BORDER_LIGHT = Color(0.5, 0.4, 0.6)
const BORDER_SHADOW = Color(0.2, 0.15, 0.25)
const TEXT_COLOR = Color(0.9, 0.9, 0.9)
const HEADER_COLOR = Color(1.0, 1.0, 0.4)
const LABEL_COLOR = Color(0.6, 0.6, 0.7)
const VALUE_COLOR = Color(0.4, 0.9, 0.4)
const BAD_COLOR = Color(0.9, 0.3, 0.3)

var _stats: Dictionary = {}
var _reason: String = ""


func setup(stats: Dictionary, reason: String) -> void:
	_stats = stats
	_reason = reason
	call_deferred("_build_ui")


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	mouse_filter = Control.MOUSE_FILTER_STOP

	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x == 0 or vp_size.y == 0:
		vp_size = Vector2(1280, 720)

	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel_w = 500.0
	var panel_h = 420.0
	var panel = Control.new()
	panel.position = Vector2((vp_size.x - panel_w) / 2, (vp_size.y - panel_h) / 2)
	panel.size = Vector2(panel_w, panel_h)
	add_child(panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_BG
	panel_bg.size = panel.size
	panel.add_child(panel_bg)
	_add_border(panel, panel.size)

	var title = Label.new()
	title.text = "AUTOGRIND COMPLETE"
	title.position = Vector2(20, 12)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	panel.add_child(title)

	var reason_lbl = Label.new()
	reason_lbl.text = "Stopped: %s" % _reason
	reason_lbl.position = Vector2(20, 38)
	reason_lbl.add_theme_font_size_override("font_size", 12)
	reason_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	panel.add_child(reason_lbl)

	var sep = ColorRect.new()
	sep.color = BORDER_LIGHT
	sep.position = Vector2(16, 58)
	sep.size = Vector2(panel_w - 32, 1)
	panel.add_child(sep)

	var stats_data = [
		{"label": "Battles Won", "value": str(_stats.get("battles_won", 0)), "color": VALUE_COLOR},
		{"label": "Total EXP", "value": str(_stats.get("total_exp", 0)), "color": VALUE_COLOR},
		{"label": "Total Gold", "value": str(_stats.get("total_gold", 0)), "color": VALUE_COLOR},
		{"label": "Consecutive Wins", "value": str(_stats.get("consecutive_wins", 0)), "color": VALUE_COLOR},
		{"label": "Efficiency", "value": "%.1fx" % _stats.get("efficiency", 1.0), "color": VALUE_COLOR},
		{"label": "Corruption", "value": "%.2f" % _stats.get("corruption", 0.0), "color": BAD_COLOR if _stats.get("corruption", 0.0) > 2.0 else VALUE_COLOR},
		{"label": "Adaptation", "value": "%.2f" % _stats.get("adaptation", 0.0), "color": LABEL_COLOR},
		{"label": "Collapses", "value": str(_stats.get("collapse_count", 0)), "color": BAD_COLOR if _stats.get("collapse_count", 0) > 0 else VALUE_COLOR},
		{"label": "Items Used", "value": str(_stats.get("total_items", 0)), "color": LABEL_COLOR},
	]

	var permadead = _stats.get("permadead", [])
	if permadead.size() > 0:
		stats_data.append({"label": "PERMADEAD", "value": ", ".join(permadead), "color": BAD_COLOR})

	var y = 68.0
	var row_h = 30.0
	for s in stats_data:
		var lbl = Label.new()
		lbl.text = s["label"]
		lbl.position = Vector2(30, y)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", LABEL_COLOR)
		panel.add_child(lbl)

		var val = Label.new()
		val.text = s["value"]
		val.position = Vector2(panel_w - 180, y)
		val.size = Vector2(150, 20)
		val.add_theme_font_size_override("font_size", 14)
		val.add_theme_color_override("font_color", s["color"])
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(val)

		y += row_h

	var footer_sep = ColorRect.new()
	footer_sep.color = BORDER_LIGHT
	footer_sep.position = Vector2(16, panel_h - 40)
	footer_sep.size = Vector2(panel_w - 32, 1)
	panel.add_child(footer_sep)

	var dismiss_lbl = Label.new()
	dismiss_lbl.text = "Press A or B to continue"
	dismiss_lbl.position = Vector2(0, panel_h - 30)
	dismiss_lbl.size = Vector2(panel_w, 20)
	dismiss_lbl.add_theme_font_size_override("font_size", 12)
	dismiss_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	dismiss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(dismiss_lbl)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		dismissed.emit()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_Z, KEY_X, KEY_ENTER, KEY_ESCAPE]:
			dismissed.emit()
			get_viewport().set_input_as_handled()


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
