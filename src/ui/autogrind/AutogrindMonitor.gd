extends Control
class_name AutogrindMonitor

## AutogrindMonitor - Real-time grinding analytics dashboard
## Displays during active autogrind: performance metrics, event log,
## rule trigger tracking, CSI/yield visualization, and interrupt controls.
## Style: calm, analytical, tactical. "Battle analytics terminal" in retro Win98 aesthetic.

signal pause_requested()
signal adjust_rules_requested()
signal exit_requested()
signal tier_cycle_requested()

## Visual style (matches AutogrindUI dark theme)
const BG_COLOR = Color(0.08, 0.06, 0.12, 0.95)
const PANEL_BG = Color(0.06, 0.05, 0.10)
const BORDER_LIGHT = Color(0.5, 0.4, 0.6)
const BORDER_SHADOW = Color(0.2, 0.15, 0.25)
const TEXT_COLOR = Color(0.9, 0.9, 0.9)
const HEADER_COLOR = Color(1.0, 1.0, 0.4)
const LABEL_COLOR = Color(0.6, 0.6, 0.7)
const DISABLED_COLOR = Color(0.4, 0.4, 0.4)

## Metric colors
const COLOR_GOOD = Color(0.4, 0.9, 0.4)
const COLOR_WARN = Color(0.9, 0.8, 0.2)
const COLOR_BAD = Color(0.9, 0.3, 0.3)
const COLOR_NEUTRAL = Color(0.7, 0.7, 0.8)

## Severity colors for highlight window
const SEVERITY_COLORS = {
	"info": Color(0.85, 0.85, 0.9),
	"warning": Color(1.0, 0.85, 0.2),
	"danger": Color(1.0, 0.3, 0.3),
	"success": Color(0.4, 1.0, 0.4),
}

## Bar colors for CSI gradient (green -> yellow -> red)
const CSI_COLOR_LOW = Color(0.3, 0.8, 0.3)
const CSI_COLOR_MID = Color(0.8, 0.8, 0.2)
const CSI_COLOR_HIGH = Color(0.8, 0.2, 0.2)

## Layout
const METRIC_CELL_W = 180
const METRIC_CELL_H = 52
const MAX_HIGHLIGHTS = 50
const VISIBLE_HIGHLIGHTS = 8

## State for trend tracking
var _prev_stats: Dictionary = {}
var _trend_history: Dictionary = {}  # metric_name -> Array of last N values
const TREND_WINDOW = 5

## Highlight entries
var _highlights: Array = []  # Array of {text, severity, timestamp}

## Rule trigger data
var _rule_triggers: Dictionary = {}  # rule_desc -> count

## UI node references
var _metrics_panel: Control
var _highlight_panel: Control
var _highlight_container: VBoxContainer
var _highlight_scroll: ScrollContainer
var _rule_panel: Control
var _rule_container: VBoxContainer
var _csi_panel: Control
var _footer_panel: Control

## Metric value labels (for real-time updating without rebuild)
var _metric_labels: Dictionary = {}  # metric_key -> {value: Label, trend: Label, bar: ColorRect}

## CSI bar references
var _csi_bar_fill: ColorRect
var _csi_label: Label
var _yield_label: Label
var _aa_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	call_deferred("_build_ui")


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x == 0 or vp_size.y == 0:
		vp_size = Vector2(1280, 720)

	# Background
	var bg = ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Right-click to exit
	MenuMouseHelper.add_right_click_cancel(bg, func() -> void: exit_requested.emit())

	# Header bar
	_build_header(vp_size)

	# Layout:
	# Top area: Performance Dashboard (full width, 2 rows of 3 metrics)
	# Middle: Rule Monitor (left ~45%) | Highlight Window (right ~55%)
	# Bottom strip: CSI/Yield bar + Footer controls

	var content_y = 52.0
	var content_h = vp_size.y - content_y - 64.0  # leave room for footer

	# Performance Dashboard (top)
	var dash_h = METRIC_CELL_H * 2 + 20
	_build_performance_dashboard(vp_size, content_y, dash_h)
	content_y += dash_h + 4

	var mid_h = content_h - dash_h - 52  # remaining height minus CSI strip

	# Rule Monitor (middle-left)
	var rule_w = int(vp_size.x * 0.42)
	_build_rule_monitor(Vector2(rule_w, mid_h), Vector2(8, content_y))

	# Highlight Window (middle-right)
	var hl_w = int(vp_size.x - rule_w - 24)
	_build_highlight_window(Vector2(hl_w, mid_h), Vector2(rule_w + 16, content_y))
	content_y += mid_h + 4

	# CSI / Yield strip
	_build_csi_strip(vp_size, content_y)

	# Footer
	_build_footer(vp_size)


func _build_header(vp_size: Vector2) -> void:
	var header = ColorRect.new()
	header.color = PANEL_BG
	header.position = Vector2(8, 6)
	header.size = Vector2(vp_size.x - 16, 38)
	add_child(header)
	_add_border(header, header.size)

	var title = Label.new()
	title.text = "AUTOGRIND MONITOR"
	title.position = Vector2(16, 14)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	add_child(title)

	# Elapsed time (updated in refresh)
	var elapsed_lbl = Label.new()
	elapsed_lbl.name = "ElapsedLabel"
	elapsed_lbl.text = "00:00:00"
	elapsed_lbl.position = Vector2(vp_size.x - 120, 14)
	elapsed_lbl.add_theme_font_size_override("font_size", 13)
	elapsed_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	add_child(elapsed_lbl)

	var tier_lbl = Label.new()
	tier_lbl.name = "TierLabel"
	tier_lbl.text = "[Tier 1]"
	tier_lbl.position = Vector2(vp_size.x - 220, 14)
	tier_lbl.add_theme_font_size_override("font_size", 13)
	tier_lbl.add_theme_color_override("font_color", COLOR_WARN)
	add_child(tier_lbl)


func _build_performance_dashboard(vp_size: Vector2, y_start: float, dash_h: float) -> void:
	_metrics_panel = Control.new()
	_metrics_panel.position = Vector2(8, y_start)
	_metrics_panel.size = Vector2(vp_size.x - 16, dash_h)
	add_child(_metrics_panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_BG
	panel_bg.size = _metrics_panel.size
	_metrics_panel.add_child(panel_bg)
	_add_border(_metrics_panel, _metrics_panel.size)

	var dash_title = Label.new()
	dash_title.text = "PERFORMANCE"
	dash_title.position = Vector2(8, 2)
	dash_title.add_theme_font_size_override("font_size", 10)
	dash_title.add_theme_color_override("font_color", DISABLED_COLOR)
	_metrics_panel.add_child(dash_title)

	# 3x2 grid of metrics
	var metrics = [
		{"key": "exp_per_min", "label": "EXP/min", "format": "%.0f", "row": 0, "col": 0},
		{"key": "jp_per_min", "label": "JP/min", "format": "%.0f", "row": 0, "col": 1},
		{"key": "gold_per_min", "label": "Gold/min", "format": "%.0f", "row": 0, "col": 2},
		{"key": "encounters_per_min", "label": "Enc/min", "format": "%.1f", "row": 1, "col": 0},
		{"key": "stability", "label": "Stability", "format": "%.0f%%", "row": 1, "col": 1},
		{"key": "yield_pct", "label": "Yield", "format": "%.0f%%", "row": 1, "col": 2},
	]

	var cell_w = (_metrics_panel.size.x - 24) / 3.0
	var cell_h = METRIC_CELL_H

	for m in metrics:
		var cell_x = 8 + m["col"] * cell_w
		var cell_y = 16 + m["row"] * cell_h
		_build_metric_cell(m["key"], m["label"], m["format"], Vector2(cell_x, cell_y), Vector2(cell_w - 4, cell_h - 4))


func _build_metric_cell(key: String, label_text: String, _fmt: String,
		pos: Vector2, cell_size: Vector2) -> void:
	var cell = Control.new()
	cell.position = pos
	cell.size = cell_size
	_metrics_panel.add_child(cell)

	# Cell background
	var cell_bg = ColorRect.new()
	cell_bg.color = Color(0.05, 0.04, 0.09)
	cell_bg.size = cell_size
	cell.add_child(cell_bg)

	# Metric label
	var lbl = Label.new()
	lbl.text = label_text
	lbl.position = Vector2(6, 2)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", LABEL_COLOR)
	cell.add_child(lbl)

	# Metric value
	var val_lbl = Label.new()
	val_lbl.text = "--"
	val_lbl.position = Vector2(6, 16)
	val_lbl.add_theme_font_size_override("font_size", 16)
	val_lbl.add_theme_color_override("font_color", COLOR_GOOD)
	cell.add_child(val_lbl)

	# Trend indicator
	var trend_lbl = Label.new()
	trend_lbl.text = ""
	trend_lbl.position = Vector2(cell_size.x - 24, 16)
	trend_lbl.add_theme_font_size_override("font_size", 14)
	trend_lbl.add_theme_color_override("font_color", COLOR_NEUTRAL)
	cell.add_child(trend_lbl)

	# Thin bottom bar (shows relative performance)
	var bar_bg = ColorRect.new()
	bar_bg.color = Color(0.1, 0.1, 0.15)
	bar_bg.position = Vector2(6, cell_size.y - 6)
	bar_bg.size = Vector2(cell_size.x - 12, 3)
	cell.add_child(bar_bg)

	var bar_fill = ColorRect.new()
	bar_fill.color = COLOR_GOOD
	bar_fill.position = Vector2(6, cell_size.y - 6)
	bar_fill.size = Vector2(0, 3)
	cell.add_child(bar_fill)

	_metric_labels[key] = {
		"value": val_lbl,
		"trend": trend_lbl,
		"bar": bar_fill,
		"bar_max_w": cell_size.x - 12,
		"format": _fmt,
	}


func _build_highlight_window(panel_size: Vector2, pos: Vector2) -> void:
	_highlight_panel = Control.new()
	_highlight_panel.position = pos
	_highlight_panel.size = panel_size
	add_child(_highlight_panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_BG
	panel_bg.size = panel_size
	_highlight_panel.add_child(panel_bg)
	_add_border(_highlight_panel, panel_size)

	var title = Label.new()
	title.text = "EVENT LOG"
	title.position = Vector2(8, 2)
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", DISABLED_COLOR)
	_highlight_panel.add_child(title)

	_highlight_scroll = ScrollContainer.new()
	_highlight_scroll.position = Vector2(4, 18)
	_highlight_scroll.size = Vector2(panel_size.x - 8, panel_size.y - 22)
	_highlight_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_highlight_panel.add_child(_highlight_scroll)

	_highlight_container = VBoxContainer.new()
	_highlight_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_highlight_scroll.add_child(_highlight_container)

	# Add a separator theme to keep entries compact
	_highlight_container.add_theme_constant_override("separation", 1)


func _build_rule_monitor(panel_size: Vector2, pos: Vector2) -> void:
	_rule_panel = Control.new()
	_rule_panel.position = pos
	_rule_panel.size = panel_size
	add_child(_rule_panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_BG
	panel_bg.size = panel_size
	_rule_panel.add_child(panel_bg)
	_add_border(_rule_panel, panel_size)

	var title = Label.new()
	title.text = "RULE TRIGGERS"
	title.position = Vector2(8, 2)
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", DISABLED_COLOR)
	_rule_panel.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(4, 18)
	scroll.size = Vector2(panel_size.x - 8, panel_size.y - 22)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rule_panel.add_child(scroll)

	_rule_container = VBoxContainer.new()
	_rule_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rule_container)
	_rule_container.add_theme_constant_override("separation", 2)


func _build_csi_strip(vp_size: Vector2, y_pos: float) -> void:
	_csi_panel = Control.new()
	_csi_panel.position = Vector2(8, y_pos)
	_csi_panel.size = Vector2(vp_size.x - 16, 42)
	add_child(_csi_panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = PANEL_BG
	panel_bg.size = _csi_panel.size
	_csi_panel.add_child(panel_bg)
	_add_border(_csi_panel, _csi_panel.size)

	# CSI label and bar
	var csi_title = Label.new()
	csi_title.text = "CSI"
	csi_title.position = Vector2(8, 4)
	csi_title.add_theme_font_size_override("font_size", 9)
	csi_title.add_theme_color_override("font_color", LABEL_COLOR)
	_csi_panel.add_child(csi_title)

	# CSI bar background
	var bar_bg = ColorRect.new()
	bar_bg.color = Color(0.1, 0.1, 0.15)
	bar_bg.position = Vector2(30, 4)
	bar_bg.size = Vector2(140, 12)
	_csi_panel.add_child(bar_bg)

	# CSI bar fill
	_csi_bar_fill = ColorRect.new()
	_csi_bar_fill.color = CSI_COLOR_LOW
	_csi_bar_fill.position = Vector2(30, 4)
	_csi_bar_fill.size = Vector2(0, 12)
	_csi_panel.add_child(_csi_bar_fill)

	# CSI numeric
	_csi_label = Label.new()
	_csi_label.text = "0.000"
	_csi_label.position = Vector2(176, 2)
	_csi_label.add_theme_font_size_override("font_size", 10)
	_csi_label.add_theme_color_override("font_color", TEXT_COLOR)
	_csi_panel.add_child(_csi_label)

	# Yield multiplier
	var yield_title = Label.new()
	yield_title.text = "Yield:"
	yield_title.position = Vector2(240, 4)
	yield_title.add_theme_font_size_override("font_size", 10)
	yield_title.add_theme_color_override("font_color", LABEL_COLOR)
	_csi_panel.add_child(yield_title)

	_yield_label = Label.new()
	_yield_label.text = "100%"
	_yield_label.position = Vector2(280, 4)
	_yield_label.add_theme_font_size_override("font_size", 10)
	_yield_label.add_theme_color_override("font_color", COLOR_GOOD)
	_csi_panel.add_child(_yield_label)

	# Automation Affinity
	var aa_title = Label.new()
	aa_title.text = "Affinity:"
	aa_title.position = Vector2(340, 4)
	aa_title.add_theme_font_size_override("font_size", 10)
	aa_title.add_theme_color_override("font_color", LABEL_COLOR)
	_csi_panel.add_child(aa_title)

	_aa_label = Label.new()
	_aa_label.text = "0.000"
	_aa_label.position = Vector2(396, 4)
	_aa_label.add_theme_font_size_override("font_size", 10)
	_aa_label.add_theme_color_override("font_color", COLOR_NEUTRAL)
	_csi_panel.add_child(_aa_label)

	# Second row: corruption + adaptation + region crack
	var corr_title = Label.new()
	corr_title.text = "Corruption:"
	corr_title.position = Vector2(8, 22)
	corr_title.add_theme_font_size_override("font_size", 9)
	corr_title.add_theme_color_override("font_color", LABEL_COLOR)
	_csi_panel.add_child(corr_title)

	var corr_val = Label.new()
	corr_val.name = "CorruptionVal"
	corr_val.text = "0.00"
	corr_val.position = Vector2(76, 22)
	corr_val.add_theme_font_size_override("font_size", 9)
	corr_val.add_theme_color_override("font_color", COLOR_GOOD)
	_csi_panel.add_child(corr_val)

	var adapt_title = Label.new()
	adapt_title.text = "Adaptation:"
	adapt_title.position = Vector2(140, 22)
	adapt_title.add_theme_font_size_override("font_size", 9)
	adapt_title.add_theme_color_override("font_color", LABEL_COLOR)
	_csi_panel.add_child(adapt_title)

	var adapt_val = Label.new()
	adapt_val.name = "AdaptationVal"
	adapt_val.text = "0.00"
	adapt_val.position = Vector2(210, 22)
	adapt_val.add_theme_font_size_override("font_size", 9)
	adapt_val.add_theme_color_override("font_color", COLOR_NEUTRAL)
	_csi_panel.add_child(adapt_val)

	var crack_title = Label.new()
	crack_title.text = "Region Crack:"
	crack_title.position = Vector2(280, 22)
	crack_title.add_theme_font_size_override("font_size", 9)
	crack_title.add_theme_color_override("font_color", LABEL_COLOR)
	_csi_panel.add_child(crack_title)

	var crack_val = Label.new()
	crack_val.name = "CrackVal"
	crack_val.text = "Lv.0"
	crack_val.position = Vector2(360, 22)
	crack_val.add_theme_font_size_override("font_size", 9)
	crack_val.add_theme_color_override("font_color", COLOR_NEUTRAL)
	_csi_panel.add_child(crack_val)


func _build_footer(vp_size: Vector2) -> void:
	_footer_panel = Control.new()
	_footer_panel.position = Vector2(8, vp_size.y - 32)
	_footer_panel.size = Vector2(vp_size.x - 16, 28)
	add_child(_footer_panel)

	var footer_bg = ColorRect.new()
	footer_bg.color = PANEL_BG
	footer_bg.size = _footer_panel.size
	_footer_panel.add_child(footer_bg)

	# Four action buttons spaced across footer
	var btn_data = [
		{"text": "Select: Pause", "action": "pause", "x": 0},
		{"text": "Start: Adjust Rules", "action": "adjust", "x": 1},
		{"text": "L+R: Tier", "action": "tier", "x": 2},
		{"text": "B: Exit", "action": "exit", "x": 3},
	]

	var btn_w = (_footer_panel.size.x - 16) / 4.0
	for i in range(btn_data.size()):
		var data = btn_data[i]
		var bx = 4 + i * btn_w
		var btn_ctrl = _create_footer_button(data["text"], data["action"], bx, btn_w - 4)
		_footer_panel.add_child(btn_ctrl)


func _create_footer_button(text: String, action_name: String,
		x_pos: float, width: float) -> Control:
	var ctrl = Control.new()
	ctrl.position = Vector2(x_pos, 2)
	ctrl.size = Vector2(width, 24)

	var bg = ColorRect.new()
	bg.color = Color(0.12, 0.10, 0.18)
	bg.size = ctrl.size
	ctrl.add_child(bg)

	# Simple 1px border
	var top_b = ColorRect.new()
	top_b.color = BORDER_LIGHT
	top_b.size = Vector2(width, 1)
	ctrl.add_child(top_b)

	var bot_b = ColorRect.new()
	bot_b.color = BORDER_SHADOW
	bot_b.position = Vector2(0, 23)
	bot_b.size = Vector2(width, 1)
	ctrl.add_child(bot_b)

	var lbl = Label.new()
	lbl.text = text
	lbl.position = Vector2(4, 4)
	lbl.size = Vector2(width - 8, 16)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", TEXT_COLOR)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ctrl.add_child(lbl)

	# Mouse click support
	var callback = func() -> void:
		match action_name:
			"pause":
				pause_requested.emit()
			"adjust":
				adjust_rules_requested.emit()
			"tier":
				tier_cycle_requested.emit()
			"exit":
				exit_requested.emit()

	MenuMouseHelper.make_clickable(ctrl, 0, width, 24, callback, func() -> void: pass)

	return ctrl


## ═══════════════════════════════════════════════════════════════════════
## PUBLIC API - Called by AutogrindUI during active grinding
## ═══════════════════════════════════════════════════════════════════════

func refresh(stats: Dictionary, region_id: String) -> void:
	"""Update all dashboard metrics with latest data.
	stats: from AutogrindController.get_grind_stats() merged with AutogrindSystem data.
	region_id: current grinding region for CSI lookup."""
	if not is_inside_tree():
		return

	# Update elapsed time display
	var elapsed_seconds = stats.get("elapsed_seconds", 0.0)
	if elapsed_seconds == 0.0:
		# Fallback: compute from AutogrindSystem directly
		var sys_stats = AutogrindSystem.get_grind_stats()
		elapsed_seconds = sys_stats.get("elapsed_seconds", 0.0)

	var elapsed_label = get_node_or_null("ElapsedLabel")
	if elapsed_label:
		var hours = int(elapsed_seconds) / 3600
		var minutes = (int(elapsed_seconds) % 3600) / 60
		var seconds = int(elapsed_seconds) % 60
		elapsed_label.text = "%02d:%02d:%02d" % [hours, minutes, seconds]

	# Get system-level stats for per-minute rates
	var sys_stats = AutogrindSystem.get_grind_stats()

	# Merge controller stats with system stats for display
	var exp_per_min = sys_stats.get("exp_per_min", 0.0)
	var jp_per_min = sys_stats.get("jp_per_min", 0.0)
	var gold_per_min = sys_stats.get("gold_per_min", 0.0)
	var enc_per_min = sys_stats.get("encounters_per_min", 0.0)

	# Compute stability from party HP and alive count
	var stability = _compute_stability(stats)

	# Get yield from CSI
	var yield_pct = AutogrindSystem.get_yield_multiplier(region_id) * 100.0

	# Update each metric
	_update_metric("exp_per_min", exp_per_min)
	_update_metric("jp_per_min", jp_per_min)
	_update_metric("gold_per_min", gold_per_min)
	_update_metric("encounters_per_min", enc_per_min)
	_update_metric("stability", stability)
	_update_metric("yield_pct", yield_pct)

	# Update CSI strip
	_update_csi_strip(region_id, stats)

	# Save current stats for next trend comparison
	_prev_stats = stats.duplicate()


func _compute_stability(stats: Dictionary) -> float:
	"""Compute party stability as a percentage.
	Based on corruption, efficiency safety margin, and party alive status."""
	var corruption = stats.get("corruption", AutogrindSystem.meta_corruption_level)
	var efficiency = stats.get("efficiency", AutogrindSystem.efficiency_multiplier)

	# Stability decreases with corruption and extreme efficiency
	var corr_factor = 1.0 - clampf(corruption / AutogrindSystem.corruption_threshold, 0.0, 1.0)
	var eff_factor = 1.0 - clampf((efficiency - 5.0) / 5.0, 0.0, 0.5)

	return clampf(corr_factor * eff_factor * 100.0, 0.0, 100.0)


func _update_metric(key: String, value: float) -> void:
	"""Update a single metric display with value, trend, and color."""
	if not _metric_labels.has(key):
		return

	var refs = _metric_labels[key]
	var val_label: Label = refs["value"]
	var trend_label: Label = refs["trend"]
	var bar: ColorRect = refs["bar"]
	var bar_max_w: float = refs["bar_max_w"]
	var fmt: String = refs["format"]

	# Format value
	val_label.text = fmt % value

	# Track trend
	if not _trend_history.has(key):
		_trend_history[key] = []
	_trend_history[key].append(value)
	if _trend_history[key].size() > TREND_WINDOW:
		_trend_history[key].pop_front()

	# Compute trend
	var trend = _get_trend(key)
	var trend_color = COLOR_NEUTRAL

	match trend:
		1:  # Rising
			trend_label.text = "^"
			trend_color = COLOR_GOOD if key != "stability" or value > 50 else COLOR_WARN
		-1:  # Falling
			trend_label.text = "v"
			trend_color = COLOR_BAD if key in ["exp_per_min", "gold_per_min", "stability", "yield_pct"] else COLOR_WARN
		_:  # Stable
			trend_label.text = "-"
			trend_color = COLOR_NEUTRAL

	trend_label.add_theme_color_override("font_color", trend_color)

	# Determine value color
	var val_color = _get_metric_color(key, value)
	val_label.add_theme_color_override("font_color", val_color)

	# Update bar width (normalized 0-1 based on metric type)
	var bar_pct = _get_bar_percentage(key, value)
	bar.size.x = bar_max_w * bar_pct
	bar.color = val_color


func _get_trend(key: String) -> int:
	"""Return 1 for rising, -1 for falling, 0 for stable."""
	var history = _trend_history.get(key, [])
	if history.size() < 2:
		return 0

	var recent = history[history.size() - 1]
	var older = history[0]
	var delta = recent - older

	# Use a threshold to avoid noise
	var threshold = maxf(absf(older) * 0.05, 0.01)

	if delta > threshold:
		return 1
	elif delta < -threshold:
		return -1
	return 0


func _get_metric_color(key: String, value: float) -> Color:
	"""Get color for a metric value based on its health."""
	match key:
		"exp_per_min", "jp_per_min", "gold_per_min":
			if value <= 0:
				return COLOR_BAD
			return COLOR_GOOD
		"encounters_per_min":
			if value <= 0:
				return COLOR_BAD
			return COLOR_GOOD
		"stability":
			if value >= 70:
				return COLOR_GOOD
			elif value >= 40:
				return COLOR_WARN
			return COLOR_BAD
		"yield_pct":
			if value >= 80:
				return COLOR_GOOD
			elif value >= 55:
				return COLOR_WARN
			return COLOR_BAD
	return COLOR_NEUTRAL


func _get_bar_percentage(key: String, value: float) -> float:
	"""Normalize a metric value to 0.0-1.0 for the bar display."""
	match key:
		"exp_per_min":
			return clampf(value / 500.0, 0.0, 1.0)  # 500 EXP/min = full bar
		"jp_per_min":
			return clampf(value / 200.0, 0.0, 1.0)
		"gold_per_min":
			return clampf(value / 300.0, 0.0, 1.0)
		"encounters_per_min":
			return clampf(value / 10.0, 0.0, 1.0)
		"stability":
			return clampf(value / 100.0, 0.0, 1.0)
		"yield_pct":
			return clampf(value / 100.0, 0.0, 1.0)
	return 0.0


func _update_csi_strip(region_id: String, stats: Dictionary) -> void:
	"""Update CSI bar, yield label, affinity, corruption, adaptation, crack."""
	var csi = AutogrindSystem.get_csi(region_id)
	var yield_mult = AutogrindSystem.get_yield_multiplier(region_id)
	var aa = AutogrindSystem.get_automation_affinity()

	# CSI bar fill
	if _csi_bar_fill:
		_csi_bar_fill.size.x = 140.0 * clampf(csi, 0.0, 1.0)
		# Color gradient: green at low CSI, yellow mid, red high
		if csi < 0.33:
			_csi_bar_fill.color = CSI_COLOR_LOW.lerp(CSI_COLOR_MID, csi / 0.33)
		elif csi < 0.66:
			_csi_bar_fill.color = CSI_COLOR_MID.lerp(CSI_COLOR_HIGH, (csi - 0.33) / 0.33)
		else:
			_csi_bar_fill.color = CSI_COLOR_HIGH

	# CSI numeric
	if _csi_label:
		_csi_label.text = "%.3f" % csi

	# Yield
	if _yield_label:
		_yield_label.text = "%.0f%%" % (yield_mult * 100.0)
		if yield_mult >= 0.8:
			_yield_label.add_theme_color_override("font_color", COLOR_GOOD)
		elif yield_mult >= 0.55:
			_yield_label.add_theme_color_override("font_color", COLOR_WARN)
		else:
			_yield_label.add_theme_color_override("font_color", COLOR_BAD)

	# Automation Affinity
	if _aa_label:
		_aa_label.text = "%.3f" % aa
		if aa < 0.3:
			_aa_label.add_theme_color_override("font_color", COLOR_NEUTRAL)
		elif aa < 0.7:
			_aa_label.add_theme_color_override("font_color", COLOR_WARN)
		else:
			_aa_label.add_theme_color_override("font_color", Color(0.7, 0.3, 0.9))  # Purple for high AA

	# Corruption
	var corruption = stats.get("corruption", AutogrindSystem.meta_corruption_level)
	var corr_node = _csi_panel.get_node_or_null("CorruptionVal") if _csi_panel else null
	if corr_node:
		corr_node.text = "%.2f" % corruption
		if corruption < 1.5:
			corr_node.add_theme_color_override("font_color", COLOR_GOOD)
		elif corruption < 3.0:
			corr_node.add_theme_color_override("font_color", COLOR_WARN)
		else:
			corr_node.add_theme_color_override("font_color", COLOR_BAD)

	# Adaptation
	var adaptation = stats.get("adaptation", AutogrindSystem.monster_adaptation_level)
	var adapt_node = _csi_panel.get_node_or_null("AdaptationVal") if _csi_panel else null
	if adapt_node:
		adapt_node.text = "%.2f" % adaptation
		if adaptation < 1.0:
			adapt_node.add_theme_color_override("font_color", COLOR_NEUTRAL)
		elif adaptation < 3.0:
			adapt_node.add_theme_color_override("font_color", COLOR_WARN)
		else:
			adapt_node.add_theme_color_override("font_color", COLOR_BAD)

	# Region crack level
	var crack = stats.get("region_crack", AutogrindSystem.region_crack_levels.get(region_id, 0))
	var crack_node = _csi_panel.get_node_or_null("CrackVal") if _csi_panel else null
	if crack_node:
		crack_node.text = "Lv.%d" % crack
		if crack == 0:
			crack_node.add_theme_color_override("font_color", COLOR_NEUTRAL)
		elif crack <= 2:
			crack_node.add_theme_color_override("font_color", COLOR_WARN)
		else:
			crack_node.add_theme_color_override("font_color", COLOR_BAD)


func add_highlight(text: String, severity: String = "info") -> void:
	"""Add an event to the highlight window.
	severity: 'info', 'warning', 'danger', 'success'"""
	if not is_inside_tree() or not _highlight_container:
		return

	var color = SEVERITY_COLORS.get(severity, SEVERITY_COLORS["info"])
	var timestamp = Time.get_time_string_from_system().substr(0, 8)  # HH:MM:SS

	# Add entry
	var entry = Label.new()
	entry.text = "[%s] %s" % [timestamp, text]
	entry.add_theme_font_size_override("font_size", 9)
	entry.add_theme_color_override("font_color", color)
	entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_highlight_container.add_child(entry)

	_highlights.append({"text": text, "severity": severity, "node": entry})

	# Prune old entries
	while _highlights.size() > MAX_HIGHLIGHTS:
		var old = _highlights.pop_front()
		if old["node"] and is_instance_valid(old["node"]):
			old["node"].queue_free()

	# Auto-scroll to bottom
	call_deferred("_scroll_highlights_to_bottom")


func _scroll_highlights_to_bottom() -> void:
	if _highlight_scroll and is_instance_valid(_highlight_scroll):
		_highlight_scroll.scroll_vertical = _highlight_scroll.get_v_scroll_bar().max_value


func update_rule_triggers(triggers: Dictionary) -> void:
	"""Update the rule monitor with trigger frequency data.
	triggers: {rule_description: trigger_count, ...}"""
	_rule_triggers = triggers.duplicate()
	_rebuild_rule_display()


func _rebuild_rule_display() -> void:
	"""Rebuild the rule trigger visualization."""
	if not _rule_container:
		return

	for child in _rule_container.get_children():
		child.queue_free()

	if _rule_triggers.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No rules triggered yet"
		empty_lbl.add_theme_font_size_override("font_size", 9)
		empty_lbl.add_theme_color_override("font_color", DISABLED_COLOR)
		_rule_container.add_child(empty_lbl)
		return

	# Sort by frequency descending
	var sorted_rules: Array = []
	for rule_desc in _rule_triggers:
		sorted_rules.append({"desc": rule_desc, "count": _rule_triggers[rule_desc]})
	sorted_rules.sort_custom(func(a, b): return a["count"] > b["count"])

	# Find max for bar scaling
	var max_count = 1
	for r in sorted_rules:
		if r["count"] > max_count:
			max_count = r["count"]

	# Determine available width for bars
	var bar_area_w = 0.0
	if _rule_panel:
		bar_area_w = _rule_panel.size.x - 24

	for r in sorted_rules:
		var row = _create_rule_trigger_row(r["desc"], r["count"], max_count, bar_area_w)
		_rule_container.add_child(row)


func _create_rule_trigger_row(desc: String, count: int, max_count: int,
		bar_area_w: float) -> Control:
	"""Create a single rule trigger row with label, count, and frequency bar."""
	var row = Control.new()
	row.custom_minimum_size = Vector2(bar_area_w, 22)
	row.size = Vector2(bar_area_w, 22)

	# Rule description
	var lbl = Label.new()
	lbl.text = desc
	lbl.position = Vector2(0, 0)
	lbl.size = Vector2(bar_area_w * 0.55, 12)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", TEXT_COLOR)
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(lbl)

	# Count label
	var count_lbl = Label.new()
	count_lbl.text = "x%d" % count
	count_lbl.position = Vector2(bar_area_w * 0.56, 0)
	count_lbl.add_theme_font_size_override("font_size", 9)
	count_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	row.add_child(count_lbl)

	# Frequency bar background
	var bar_x = bar_area_w * 0.65
	var bar_w = bar_area_w * 0.34

	var bar_bg = ColorRect.new()
	bar_bg.color = Color(0.08, 0.08, 0.12)
	bar_bg.position = Vector2(bar_x, 12)
	bar_bg.size = Vector2(bar_w, 6)
	row.add_child(bar_bg)

	# Frequency bar fill
	var fill_pct = float(count) / float(max_count) if max_count > 0 else 0.0
	var bar_fill = ColorRect.new()
	bar_fill.color = Color(0.3, 0.6, 0.9) if fill_pct < 0.7 else Color(0.9, 0.6, 0.2)
	bar_fill.position = Vector2(bar_x, 12)
	bar_fill.size = Vector2(bar_w * fill_pct, 6)
	row.add_child(bar_fill)

	return row


## ═══════════════════════════════════════════════════════════════════════
## INPUT HANDLING
## ═══════════════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var action = AutogrindInputHelper.classify_event(event)
	match action:
		"pause":
			pause_requested.emit()
		"adjust_rules":
			adjust_rules_requested.emit()
		"exit":
			exit_requested.emit()
		"tier_cycle":
			tier_cycle_requested.emit()
		_:
			return
	get_viewport().set_input_as_handled()


## ═══════════════════════════════════════════════════════════════════════
## UTILITY
## ═══════════════════════════════════════════════════════════════════════

func _add_border(parent: Control, panel_size: Vector2) -> void:
	"""Add Win98-style pixel border matching RetroPanel aesthetic."""
	# Top (bright)
	var top = ColorRect.new()
	top.color = BORDER_LIGHT
	top.size = Vector2(panel_size.x, 2)
	parent.add_child(top)

	# Left (bright)
	var left = ColorRect.new()
	left.color = BORDER_LIGHT
	left.size = Vector2(2, panel_size.y)
	parent.add_child(left)

	# Bottom (shadow)
	var bottom = ColorRect.new()
	bottom.color = BORDER_SHADOW
	bottom.position = Vector2(0, panel_size.y - 2)
	bottom.size = Vector2(panel_size.x, 2)
	parent.add_child(bottom)

	# Right (shadow)
	var right = ColorRect.new()
	right.color = BORDER_SHADOW
	right.position = Vector2(panel_size.x - 2, 0)
	right.size = Vector2(2, panel_size.y)
	parent.add_child(right)
