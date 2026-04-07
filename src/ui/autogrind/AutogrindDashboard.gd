extends Control
class_name AutogrindDashboard

## AutogrindDashboard - Tier 2 full-screen analytics dashboard with mini battle view
## Shows sparkline charts, session stats, projections, and a SubViewport for battle rendering.

signal pause_requested()
signal adjust_rules_requested()
signal exit_requested()
signal tier_cycle_requested()

## Visual style (matches AutogrindMonitor)
const BG_COLOR = Color(0.08, 0.06, 0.12, 0.95)
const PANEL_BG = Color(0.06, 0.05, 0.10)
const BORDER_LIGHT = Color(0.5, 0.4, 0.6)
const BORDER_SHADOW = Color(0.2, 0.15, 0.25)
const TEXT_COLOR = Color(0.9, 0.9, 0.9)
const HEADER_COLOR = Color(1.0, 1.0, 0.4)
const LABEL_COLOR = Color(0.6, 0.6, 0.7)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)
const COLOR_GOOD = Color(0.4, 0.9, 0.4)
const COLOR_WARN = Color(0.9, 0.8, 0.2)
const COLOR_BAD = Color(0.9, 0.3, 0.3)
const COLOR_NEUTRAL = Color(0.7, 0.7, 0.8)

## Mini battle viewport
var _battle_viewport: SubViewport = null
var _battle_viewport_container: SubViewportContainer = null

## Corruption visual tinting
var _corruption_tint: ColorRect = null
const CORRUPTION_TINT_MAX_ALPHA: float = 0.22  # Max overlay opacity at full corruption
const CORRUPTION_THRESHOLD: float = 5.0        # corruption value considered "max" for visuals

## Sparkline charts
var _exp_sparkline: SparklineChart = null
var _gold_sparkline: SparklineChart = null
var _winrate_sparkline: SparklineChart = null

## Stats labels
var _stat_labels: Dictionary = {}
var _projection_labels: Dictionary = {}
var _elapsed_label: Label = null
var _permadeath_label: Label = null

## Stats strip
var _stats_strip: AutogrindStatsStrip = null

## Ludicrous speed indicator
var _ludicrous_label: Label = null

## Tracking for projections
var _session_start_time: float = 0.0
var _battles_completed: int = 0
var _total_exp: int = 0
var _total_gold: int = 0
var _wins: int = 0
var _party_levels: Array = []

## Rolling average state
var _exp_history: Array[int] = []
var _battle_times: Array[float] = []
const ROLLING_WINDOW = 10
var _last_total_exp: int = 0
var _last_total_gold: int = 0
var _last_battle_count: int = 0
var _last_refresh_time: float = 0.0

## Prediction accuracy tracking
var _predictions: Array[Dictionary] = []

## Battle log
var _battle_log_entries: Array = []
var _battle_log_container: VBoxContainer = null
var _battle_log_scroll: ScrollContainer = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_session_start_time = Time.get_ticks_msec() / 1000.0
	_last_refresh_time = _session_start_time
	call_deferred("_build_ui")


func get_battle_viewport() -> SubViewport:
	return _battle_viewport


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x == 0 or vp_size.y == 0:
		vp_size = Vector2(1280, 720)

	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	MenuMouseHelper.add_right_click_cancel(bg, func() -> void: exit_requested.emit())

	# Corruption tint overlay — sits above background, below all panels.
	# Color shifts from sickly purple toward red as corruption grows.
	_corruption_tint = ColorRect.new()
	_corruption_tint.color = Color(0.5, 0.0, 0.1, 0.0)  # starts transparent
	_corruption_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_corruption_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_corruption_tint)

	_build_header(vp_size)

	var content_y = 52.0
	var footer_h = 64.0
	var content_h = vp_size.y - content_y - footer_h

	var top_h = content_h * 0.55
	var mini_w = 296.0
	var chart_w = vp_size.x - mini_w - 32.0

	_build_mini_battle_panel(Vector2(mini_w, top_h), Vector2(8, content_y))
	_build_sparkline_panel(Vector2(chart_w, top_h), Vector2(mini_w + 16, content_y))

	content_y += top_h + 4

	var bottom_h = content_h * 0.45 - 50
	var stats_w = mini_w
	var proj_w = chart_w

	_build_session_stats_panel(Vector2(stats_w, bottom_h), Vector2(8, content_y))
	_build_projections_panel(Vector2(proj_w, bottom_h), Vector2(mini_w + 16, content_y))

	content_y += bottom_h + 4

	_stats_strip = AutogrindStatsStrip.new()
	_stats_strip.position = Vector2(8, content_y)
	_stats_strip.size = Vector2(stats_w, 42)
	add_child(_stats_strip)

	_build_battle_log_panel(Vector2(proj_w, 42), Vector2(mini_w + 16, content_y))

	_build_footer(vp_size)


func _build_header(vp_size: Vector2) -> void:
	var header = ColorRect.new()
	header.color = PANEL_BG
	header.position = Vector2(8, 6)
	header.size = Vector2(vp_size.x - 16, 38)
	add_child(header)
	_add_border(header, header.size)

	var title = Label.new()
	title.text = "AUTOGRIND DASHBOARD"
	title.position = Vector2(16, 14)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	add_child(title)

	var tier_lbl = Label.new()
	tier_lbl.text = "[Tier 2]"
	tier_lbl.position = Vector2(vp_size.x - 200, 14)
	tier_lbl.add_theme_font_size_override("font_size", 13)
	tier_lbl.add_theme_color_override("font_color", COLOR_WARN)
	add_child(tier_lbl)

	_ludicrous_label = Label.new()
	_ludicrous_label.text = ""
	_ludicrous_label.position = Vector2(vp_size.x - 380, 14)
	_ludicrous_label.add_theme_font_size_override("font_size", 13)
	_ludicrous_label.add_theme_color_override("font_color", Color(0.8, 0.4, 1.0))
	_ludicrous_label.visible = false
	add_child(_ludicrous_label)

	_elapsed_label = Label.new()
	_elapsed_label.text = "00:00:00"
	_elapsed_label.position = Vector2(vp_size.x - 120, 14)
	_elapsed_label.add_theme_font_size_override("font_size", 13)
	_elapsed_label.add_theme_color_override("font_color", LABEL_COLOR)
	add_child(_elapsed_label)


func _build_mini_battle_panel(panel_size: Vector2, pos: Vector2) -> void:
	var panel = Control.new()
	panel.position = pos
	panel.size = panel_size
	add_child(panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_BG
	panel_bg.size = panel_size
	panel.add_child(panel_bg)
	_add_border(panel, panel_size)

	var title = Label.new()
	title.text = "BATTLE VIEW"
	title.position = Vector2(8, 2)
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(title)

	_battle_viewport_container = SubViewportContainer.new()
	_battle_viewport_container.position = Vector2(8, 18)
	_battle_viewport_container.size = Vector2(panel_size.x - 16, panel_size.y - 22)
	_battle_viewport_container.stretch = true
	panel.add_child(_battle_viewport_container)

	_battle_viewport = SubViewport.new()
	_battle_viewport.size = Vector2i(640, 360)
	_battle_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_battle_viewport.transparent_bg = false
	_battle_viewport_container.add_child(_battle_viewport)

	# CRT scanline overlay — alternating semi-transparent dark bars every 3 pixels
	var scan_overlay = Control.new()
	scan_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	scan_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp_h := int(_battle_viewport_container.size.y)
	var vp_w := _battle_viewport_container.size.x
	var scan_y := 0
	while scan_y < vp_h:
		var line = ColorRect.new()
		line.color = Color(0.0, 0.0, 0.0, 0.18)
		line.position = Vector2(0.0, float(scan_y))
		line.size = Vector2(vp_w, 1.0)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scan_overlay.add_child(line)
		scan_y += 3  # every third row = subtle but visible
	panel.add_child(scan_overlay)

	# CRT bezel frame — a colored inner border around the viewport to mimic a monitor bezel
	var bezel_pos = _battle_viewport_container.position - Vector2(2, 2)
	var bezel_size = _battle_viewport_container.size + Vector2(4, 4)
	var bezel_color := Color(0.2, 0.35, 0.5, 0.85)  # dim blue-steel

	var bezel_top = ColorRect.new()
	bezel_top.color = bezel_color
	bezel_top.position = bezel_pos
	bezel_top.size = Vector2(bezel_size.x, 2)
	bezel_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bezel_top)

	var bezel_bottom = ColorRect.new()
	bezel_bottom.color = bezel_color
	bezel_bottom.position = Vector2(bezel_pos.x, bezel_pos.y + bezel_size.y - 2)
	bezel_bottom.size = Vector2(bezel_size.x, 2)
	bezel_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bezel_bottom)

	var bezel_left = ColorRect.new()
	bezel_left.color = bezel_color
	bezel_left.position = bezel_pos
	bezel_left.size = Vector2(2, bezel_size.y)
	bezel_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bezel_left)

	var bezel_right = ColorRect.new()
	bezel_right.color = bezel_color
	bezel_right.position = Vector2(bezel_pos.x + bezel_size.x - 2, bezel_pos.y)
	bezel_right.size = Vector2(2, bezel_size.y)
	bezel_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bezel_right)

	# Screen-edge vignette: a darker inner-corner overlay using a semi-transparent screen-edge strip
	var vignette = ColorRect.new()
	vignette.color = Color(0.0, 0.0, 0.0, 0.12)
	vignette.position = _battle_viewport_container.position
	vignette.size = _battle_viewport_container.size
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vignette)


func _build_sparkline_panel(panel_size: Vector2, pos: Vector2) -> void:
	var panel = Control.new()
	panel.position = pos
	panel.size = panel_size
	add_child(panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_BG
	panel_bg.size = panel_size
	panel.add_child(panel_bg)
	_add_border(panel, panel_size)

	var title = Label.new()
	title.text = "PERFORMANCE GRAPHS"
	title.position = Vector2(8, 2)
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(title)

	var chart_h = (panel_size.y - 24) / 3.0
	var chart_w = panel_size.x - 80

	var charts_data = [
		{"label": "EXP/min", "color": COLOR_GOOD, "field": "exp"},
		{"label": "Gold/min", "color": Color(1.0, 0.85, 0.2), "field": "gold"},
		{"label": "Win Rate", "color": Color(0.4, 0.7, 1.0), "field": "winrate"},
	]

	for i in range(charts_data.size()):
		var data = charts_data[i]
		var y = 18 + i * chart_h

		var lbl = Label.new()
		lbl.text = data["label"]
		lbl.position = Vector2(8, y + chart_h * 0.3)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", LABEL_COLOR)
		panel.add_child(lbl)

		var spark = SparklineChart.new(60, data["color"])
		spark.position = Vector2(72, y + 2)
		spark.size = Vector2(chart_w, chart_h - 6)
		panel.add_child(spark)

		if i < 2:
			var sep = ColorRect.new()
			sep.color = Color(0.15, 0.12, 0.2)
			sep.position = Vector2(8, y + chart_h - 1)
			sep.size = Vector2(panel_size.x - 16, 1)
			panel.add_child(sep)

		match data["field"]:
			"exp": _exp_sparkline = spark
			"gold": _gold_sparkline = spark
			"winrate": _winrate_sparkline = spark


func _build_session_stats_panel(panel_size: Vector2, pos: Vector2) -> void:
	var panel = Control.new()
	panel.position = pos
	panel.size = panel_size
	add_child(panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_BG
	panel_bg.size = panel_size
	panel.add_child(panel_bg)
	_add_border(panel, panel_size)

	var title = Label.new()
	title.text = "SESSION STATS"
	title.position = Vector2(8, 2)
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(title)

	var stats = [
		{"key": "battles", "label": "Battles:", "default": "0"},
		{"key": "total_exp", "label": "Total EXP:", "default": "0"},
		{"key": "win_rate", "label": "Win Rate:", "default": "100%"},
		{"key": "total_gold", "label": "Total Gold:", "default": "0"},
		{"key": "collapses", "label": "Collapses:", "default": "0"},
		{"key": "time_mult", "label": "Time Bonus:", "default": "1.0x"},
	]

	var row_h = (panel_size.y - 20) / stats.size()
	for i in range(stats.size()):
		var s = stats[i]
		var y = 18 + i * row_h

		var lbl = Label.new()
		lbl.text = s["label"]
		lbl.position = Vector2(12, y)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", LABEL_COLOR)
		panel.add_child(lbl)

		var val = Label.new()
		val.text = s["default"]
		val.position = Vector2(panel_size.x * 0.55, y)
		val.add_theme_font_size_override("font_size", 11)
		val.add_theme_color_override("font_color", TEXT_COLOR)
		panel.add_child(val)

		_stat_labels[s["key"]] = val

	var last_y = 18 + stats.size() * row_h
	_permadeath_label = Label.new()
	_permadeath_label.text = "PERMADEATH: OFF"
	_permadeath_label.position = Vector2(12, last_y + 4)
	_permadeath_label.add_theme_font_size_override("font_size", 12)
	_permadeath_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	panel.add_child(_permadeath_label)


func _build_projections_panel(panel_size: Vector2, pos: Vector2) -> void:
	var panel = Control.new()
	panel.position = pos
	panel.size = panel_size
	add_child(panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_BG
	panel_bg.size = panel_size
	panel.add_child(panel_bg)
	_add_border(panel, panel_size)

	var title = Label.new()
	title.text = "PROJECTIONS"
	title.position = Vector2(8, 2)
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(title)

	var projs = [
		{"key": "avg_exp_battle", "label": "Avg EXP/battle:", "default": "--"},
		{"key": "battles_per_min", "label": "Battles/min:", "default": "--"},
		{"key": "projected_exp_10m", "label": "EXP in 10min:", "default": "--"},
		{"key": "projected_gold_10m", "label": "Gold in 10min:", "default": "--"},
		{"key": "accuracy", "label": "Accuracy:", "default": "--"},
	]

	var row_h = (panel_size.y - 20) / projs.size()
	for i in range(projs.size()):
		var p = projs[i]
		var y = 18 + i * row_h

		var lbl = Label.new()
		lbl.text = p["label"]
		lbl.position = Vector2(12, y)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", LABEL_COLOR)
		panel.add_child(lbl)

		var val = Label.new()
		val.text = p["default"]
		val.position = Vector2(panel_size.x * 0.55, y)
		val.add_theme_font_size_override("font_size", 11)
		val.add_theme_color_override("font_color", COLOR_GOOD)
		panel.add_child(val)

		_projection_labels[p["key"]] = val


func _build_footer(vp_size: Vector2) -> void:
	var footer = Control.new()
	footer.position = Vector2(8, vp_size.y - 32)
	footer.size = Vector2(vp_size.x - 16, 28)
	add_child(footer)

	var footer_bg = ColorRect.new()
	footer_bg.color = PANEL_BG
	footer_bg.size = footer.size
	footer.add_child(footer_bg)

	var btn_data = [
		{"text": "Select: Pause", "x": 0},
		{"text": "Start: Rules", "x": 1},
		{"text": "L+R: Tier", "x": 2},
		{"text": "B: Exit", "x": 3},
	]

	var btn_w = (footer.size.x - 16) / btn_data.size()
	for i in range(btn_data.size()):
		var bx = 4 + i * btn_w
		var lbl = Label.new()
		lbl.text = btn_data[i]["text"]
		lbl.position = Vector2(bx, 6)
		lbl.size = Vector2(btn_w - 4, 16)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", TEXT_COLOR)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		footer.add_child(lbl)


func _build_battle_log_panel(panel_size: Vector2, pos: Vector2) -> void:
	var panel = Control.new()
	panel.position = pos
	panel.size = panel_size
	add_child(panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_BG
	panel_bg.size = panel_size
	panel.add_child(panel_bg)
	_add_border(panel, panel_size)

	var title = Label.new()
	title.text = "BATTLE LOG"
	title.position = Vector2(8, 2)
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", DISABLED_COLOR)
	panel.add_child(title)

	_battle_log_scroll = ScrollContainer.new()
	_battle_log_scroll.position = Vector2(4, 18)
	_battle_log_scroll.size = Vector2(panel_size.x - 8, panel_size.y - 22)
	_battle_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_battle_log_scroll)

	_battle_log_container = VBoxContainer.new()
	_battle_log_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_log_container.add_theme_constant_override("separation", 2)
	_battle_log_scroll.add_child(_battle_log_container)


func add_battle_result(victory: bool, turns: int, exp_gained: int) -> void:
	_battle_log_entries.append({"victory": victory, "turns": turns, "exp": exp_gained})
	if _battle_log_entries.size() > 10:
		_battle_log_entries.remove_at(0)
	_refresh_battle_log()


func _refresh_battle_log() -> void:
	if not _battle_log_container or not is_instance_valid(_battle_log_container):
		return
	for child in _battle_log_container.get_children():
		child.queue_free()
	for entry in _battle_log_entries:
		var lbl = Label.new()
		lbl.text = "%s  %d turns  +%d EXP" % ["WIN" if entry["victory"] else "LOSS", entry["turns"], entry["exp"]]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if entry["victory"] else Color(0.9, 0.3, 0.3))
		_battle_log_container.add_child(lbl)


## ═══════════════════════════════════════════════════════════════════════
## PUBLIC API
## ═══════════════════════════════════════════════════════════════════════

func refresh(stats: Dictionary, region_id: String) -> void:
	if not is_inside_tree():
		return

	var current_battles = stats.get("battles_won", _battles_completed)
	var current_exp = stats.get("total_exp", _total_exp)
	var current_gold = stats.get("total_gold", _total_gold)
	_wins = stats.get("consecutive_wins", _wins)

	var now = Time.get_ticks_msec() / 1000.0
	var elapsed = now - _session_start_time

	if _elapsed_label:
		var hours = int(elapsed) / 3600
		var mins = (int(elapsed) % 3600) / 60
		var secs = int(elapsed) % 60
		_elapsed_label.text = "%02d:%02d:%02d" % [hours, mins, secs]

	# Track per-battle EXP delta for rolling average
	if current_battles > _last_battle_count and _last_battle_count > 0:
		var new_battles = current_battles - _last_battle_count
		var delta_exp = current_exp - _last_total_exp
		var time_delta = now - _last_refresh_time
		var time_per_battle = time_delta / float(new_battles) if new_battles > 0 else 0.0
		var exp_per_new_battle = delta_exp / new_battles if new_battles > 0 else 0

		for _i in range(new_battles):
			_exp_history.append(exp_per_new_battle)
			_battle_times.append(time_per_battle)
			if _exp_history.size() > ROLLING_WINDOW:
				_exp_history.remove_at(0)
			if _battle_times.size() > ROLLING_WINDOW:
				_battle_times.remove_at(0)

	_last_refresh_time = now
	_last_battle_count = current_battles
	_last_total_exp = current_exp
	_last_total_gold = current_gold
	_battles_completed = current_battles
	_total_exp = current_exp
	_total_gold = current_gold

	# Rolling average EXP per battle
	var avg_exp_per_battle := 0.0
	if _exp_history.size() > 0:
		var exp_sum := 0
		for e in _exp_history:
			exp_sum += e
		avg_exp_per_battle = float(exp_sum) / _exp_history.size()
	elif _battles_completed > 0:
		avg_exp_per_battle = float(_total_exp) / _battles_completed

	# Rolling average seconds per battle → battles per minute
	var avg_secs_per_battle := 0.0
	if _battle_times.size() > 0:
		var time_sum := 0.0
		for t in _battle_times:
			time_sum += t
		avg_secs_per_battle = time_sum / _battle_times.size()
	var battles_per_min := 0.0
	if avg_secs_per_battle > 0.0:
		battles_per_min = 60.0 / avg_secs_per_battle
	else:
		var elapsed_min = max(elapsed / 60.0, 0.01)
		battles_per_min = _battles_completed / elapsed_min

	# Rolling gold per battle
	var avg_gold_per_battle := 0.0
	if _battles_completed > 0:
		avg_gold_per_battle = float(_total_gold) / _battles_completed

	var exp_per_min = avg_exp_per_battle * battles_per_min
	var gold_per_min = avg_gold_per_battle * battles_per_min
	var win_rate = 100.0 * _battles_completed / max(_battles_completed + stats.get("collapse_count", 0), 1)

	if _exp_sparkline:
		_exp_sparkline.push_value(exp_per_min)
	if _gold_sparkline:
		_gold_sparkline.push_value(gold_per_min)
	if _winrate_sparkline:
		_winrate_sparkline.push_value(win_rate)

	_update_stat("battles", str(_battles_completed))
	_update_stat("total_exp", str(_total_exp))
	_update_stat("win_rate", "%.0f%%" % win_rate)
	_update_stat("total_gold", str(_total_gold))
	_update_stat("collapses", str(stats.get("collapse_count", 0)))
	var time_mult = stats.get("time_multiplier", 1.0)
	_update_stat("time_mult", "%.1fx" % time_mult)

	if _permadeath_label and is_instance_valid(_permadeath_label):
		var staking = AutogrindSystem.permadeath_staking_enabled
		_permadeath_label.text = "PERMADEATH: %s (3x EXP)" % ("ON" if staking else "OFF")
		_permadeath_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2) if staking else Color(0.5, 0.5, 0.6))

	var avg_label := "~%d" % int(avg_exp_per_battle) if _exp_history.size() > 0 else ("~%d" % int(avg_exp_per_battle) if _battles_completed >= 3 else "--")
	_update_projection("avg_exp_battle", avg_label)
	_update_projection("battles_per_min", "%.1f" % battles_per_min if battles_per_min > 0 else "--")
	_update_projection("projected_exp_10m", "~%d" % int(avg_exp_per_battle * battles_per_min * 10) if battles_per_min > 0 else "--")
	_update_projection("projected_gold_10m", "~%d" % int(gold_per_min * 10) if battles_per_min > 0 else "--")

	# Record a prediction every 5 battles
	if _battles_completed > 0 and _battles_completed % 5 == 0 and avg_exp_per_battle > 0:
		var already_recorded := false
		for pred in _predictions:
			if pred["at_battle"] == _battles_completed:
				already_recorded = true
				break
		if not already_recorded:
			var predicted_5 = _total_exp + int(avg_exp_per_battle * 5)
			_predictions.append({"predicted": predicted_5, "at_battle": _battles_completed, "target_battle": _battles_completed + 5})

	# Check old predictions for accuracy
	for pred in _predictions.duplicate():
		if _battles_completed >= pred["target_battle"]:
			var actual = _total_exp
			var predicted = pred["predicted"]
			var error_pct = abs(actual - predicted) / max(float(predicted), 1.0) * 100.0
			var accuracy = max(0.0, 100.0 - error_pct)
			_update_projection("accuracy", "%.0f%%" % accuracy)
			_predictions.erase(pred)

	if _stats_strip and is_instance_valid(_stats_strip):
		_stats_strip.refresh(stats, region_id)

	_update_corruption_tint(stats)


func set_ludicrous_mode(enabled: bool) -> void:
	if _ludicrous_label and is_instance_valid(_ludicrous_label):
		_ludicrous_label.text = "LUDICROUS SPEED" if enabled else ""
		_ludicrous_label.visible = enabled


func add_highlight(_text: String, _severity: String = "info") -> void:
	pass


func update_rule_triggers(_triggers: Dictionary) -> void:
	pass


func _update_stat(key: String, value: String) -> void:
	if key in _stat_labels and is_instance_valid(_stat_labels[key]):
		_stat_labels[key].text = value


func _update_projection(key: String, value: String) -> void:
	if key in _projection_labels and is_instance_valid(_projection_labels[key]):
		_projection_labels[key].text = value


## ═══════════════════════════════════════════════════════════════════════
## INPUT HANDLING
## ═══════════════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK:
		pause_requested.emit()
		get_viewport().set_input_as_handled()

	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		adjust_rules_requested.emit()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		exit_requested.emit()
		get_viewport().set_input_as_handled()

	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER or event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			if Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER) and Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER):
				tier_cycle_requested.emit()
				get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_P:
				pause_requested.emit()
				get_viewport().set_input_as_handled()
			KEY_R:
				adjust_rules_requested.emit()
				get_viewport().set_input_as_handled()
			KEY_T:
				tier_cycle_requested.emit()
				get_viewport().set_input_as_handled()


## ═══════════════════════════════════════════════════════════════════════
## UTILITY
## ═══════════════════════════════════════════════════════════════════════

func _update_corruption_tint(stats: Dictionary) -> void:
	if not _corruption_tint or not is_instance_valid(_corruption_tint):
		return
	var corruption := stats.get("corruption", 0.0) as float
	var t := clampf(corruption / CORRUPTION_THRESHOLD, 0.0, 1.0)
	# Lerp hue: low corruption = purple-red tint, high = saturated red
	var r := lerpf(0.5, 0.85, t)
	var g := lerpf(0.0, 0.0, t)
	var b := lerpf(0.1, 0.0, t)
	var a := t * CORRUPTION_TINT_MAX_ALPHA
	_corruption_tint.color = Color(r, g, b, a)


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
