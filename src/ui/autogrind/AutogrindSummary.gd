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
const BADGE_NEW_COLOR = Color(1.0, 0.85, 0.2)
const BADGE_EARNED_COLOR = Color(0.55, 0.55, 0.65)
const BADGE_BG_NEW = Color(0.15, 0.13, 0.06)
const BADGE_BG_EARNED = Color(0.08, 0.08, 0.12)

const AutogrindAchievementsScript = preload("res://src/autogrind/AutogrindAchievements.gd")

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

	# Build stats data first to compute panel height
	var elapsed = _stats.get("elapsed_seconds", 0.0)
	var dur_min = int(elapsed) / 60
	var dur_sec = int(elapsed) % 60
	var bpm = _stats.get("battles_won", 0) / maxf(elapsed / 60.0, 0.01)

	var stats_data = [
		{"label": "Battles Won", "value": str(_stats.get("battles_won", 0)), "color": VALUE_COLOR},
		{"label": "Total EXP", "value": str(_stats.get("total_exp", 0)), "color": VALUE_COLOR},
		{"label": "Total Gold", "value": str(_stats.get("total_gold", 0)), "color": VALUE_COLOR},
		{"label": "Time Elapsed", "value": "%d:%02d" % [dur_min, dur_sec], "color": VALUE_COLOR},
		{"label": "Battles/Min", "value": "%.1f" % bpm, "color": VALUE_COLOR},
		{"label": "Consecutive Wins", "value": str(_stats.get("consecutive_wins", 0)), "color": VALUE_COLOR},
		{"label": "Efficiency", "value": "%.1fx" % _stats.get("efficiency", 1.0), "color": VALUE_COLOR},
		{"label": "Corruption", "value": "%.2f" % _stats.get("corruption", 0.0), "color": BAD_COLOR if _stats.get("corruption", 0.0) > 2.0 else VALUE_COLOR},
		{"label": "Adaptation", "value": "%.2f" % _stats.get("adaptation", 0.0), "color": LABEL_COLOR},
		{"label": "Collapses", "value": str(_stats.get("collapse_count", 0)), "color": BAD_COLOR if _stats.get("collapse_count", 0) > 0 else VALUE_COLOR},
	]

	# Per-character EXP breakdown
	var char_exp = _stats.get("per_character_exp", {})
	if not char_exp.is_empty():
		for char_name in char_exp:
			stats_data.append({"label": "  %s EXP" % char_name, "value": "+%d" % char_exp[char_name], "color": Color(0.5, 0.8, 1.0)})

	# Items consumed breakdown
	var items_consumed = _stats.get("items_consumed", {})
	if not items_consumed.is_empty():
		var item_parts: Array = []
		for item_id in items_consumed:
			item_parts.append("%s x%d" % [_resolve_item_display_name(item_id), items_consumed[item_id]])
		stats_data.append({"label": "Items Used", "value": ", ".join(item_parts), "color": LABEL_COLOR})
	else:
		stats_data.append({"label": "Items Used", "value": "None", "color": LABEL_COLOR})

	stats_data.append({"label": "Fatigue Events", "value": str(_stats.get("fatigue_events_triggered", 0)), "color": LABEL_COLOR})
	var time_mult = _stats.get("time_multiplier", 1.0)
	stats_data.append({"label": "Time Bonus", "value": "%.1fx" % time_mult, "color": VALUE_COLOR})

	var grade = _compute_grade()
	stats_data.append({"label": "SESSION GRADE", "value": grade["letter"], "color": grade["color"]})

	var permadead = _stats.get("permadead", [])
	if permadead.size() > 0:
		stats_data.append({"label": "PERMADEAD", "value": ", ".join(permadead), "color": BAD_COLOR})

	# newly earned this run render gold; already-unlocked render dim.
	var gs := _get_game_state()
	var split := AutogrindAchievementsScript.check_and_award(_stats, gs)
	var newly: Array = split[0]
	var previously: Array = split[1]
	var all_badges: Array = newly + previously

	# Compute panel height from row count
	var row_h = 26.0
	var badge_row_h := 40.0 if all_badges.size() > 0 else 0.0
	var badge_header_h := 20.0 if all_badges.size() > 0 else 0.0
	var panel_w = 520.0
	var panel_h = 68.0 + stats_data.size() * row_h + badge_header_h + badge_row_h + 50.0
	panel_h = min(panel_h, vp_size.y - 40)

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

	var y = 68.0
	for s in stats_data:
		var lbl = Label.new()
		lbl.text = s["label"]
		lbl.position = Vector2(30, y)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", LABEL_COLOR)
		panel.add_child(lbl)

		var val = Label.new()
		val.text = s["value"]
		val.position = Vector2(panel_w - 200, y)
		val.size = Vector2(170, 20)
		val.add_theme_font_size_override("font_size", 13)
		val.add_theme_color_override("font_color", s["color"])
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		panel.add_child(val)

		y += row_h

	if all_badges.size() > 0:
		var badge_header = Label.new()
		badge_header.text = "ACHIEVEMENTS  (%d new)" % newly.size() if newly.size() > 0 else "ACHIEVEMENTS"
		badge_header.position = Vector2(20, y)
		badge_header.add_theme_font_size_override("font_size", 12)
		badge_header.add_theme_color_override("font_color", BADGE_NEW_COLOR if newly.size() > 0 else LABEL_COLOR)
		panel.add_child(badge_header)
		y += badge_header_h

		var badges_x = 20.0
		var chip_h = 30.0
		var chip_pad = 8.0
		for a in all_badges:
			var is_new := a in newly
			var chip_w := _measure_badge_width(a)
			var chip_bg = ColorRect.new()
			chip_bg.color = BADGE_BG_NEW if is_new else BADGE_BG_EARNED
			chip_bg.position = Vector2(badges_x, y)
			chip_bg.size = Vector2(chip_w, chip_h)
			panel.add_child(chip_bg)

			var chip_lbl = Label.new()
			chip_lbl.text = "%s %s" % [a.get("icon", "*"), a.get("name", a.get("id", "?"))]
			chip_lbl.position = Vector2(badges_x + 6, y + 6)
			chip_lbl.add_theme_font_size_override("font_size", 12)
			chip_lbl.add_theme_color_override("font_color", BADGE_NEW_COLOR if is_new else BADGE_EARNED_COLOR)
			chip_lbl.tooltip_text = a.get("description", "")
			panel.add_child(chip_lbl)

			badges_x += chip_w + chip_pad
			if badges_x > panel_w - 40:
				break

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


## Tick 135: thin wrapper around ItemNameResolver.
func _resolve_item_display_name(item_id: String) -> String:
	return ItemNameResolver.resolve(item_id)


func _get_game_state() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		return tree.root.get_node_or_null("GameState")
	return null


func _measure_badge_width(a: Dictionary) -> float:
	# ~6.5 px per char at font_size 12; icon + space + name.
	var text := "%s %s" % [a.get("icon", "*"), a.get("name", a.get("id", "?"))]
	return maxf(72.0, text.length() * 6.5 + 16.0)


func _compute_grade() -> Dictionary:
	var battles = _stats.get("battles_won", 0)
	var collapses = _stats.get("collapse_count", 0)
	if battles >= 50 and collapses == 0:
		return {"letter": "S", "color": Color(1.0, 0.85, 0.0)}  # Gold
	elif battles >= 30 and collapses <= 1:
		return {"letter": "A", "color": Color(0.4, 0.9, 0.4)}  # Green
	elif battles >= 15:
		return {"letter": "B", "color": Color(0.4, 0.7, 1.0)}  # Blue
	elif battles > 0:
		return {"letter": "C", "color": Color(0.7, 0.7, 0.7)}  # Gray
	else:
		return {"letter": "F", "color": Color(0.9, 0.3, 0.3)}  # Red


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
