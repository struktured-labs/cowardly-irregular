extends Control
class_name AutogrindStatsStrip

## AutogrindStatsStrip - Reusable CSI/yield/corruption/adaptation/region-crack bar
## Used by AutogrindMonitor and AutogrindDashboard for consistent stats display.

const PANEL_BG = Color(0.06, 0.05, 0.10)
const BORDER_LIGHT = Color(0.5, 0.4, 0.6)
const BORDER_SHADOW = Color(0.2, 0.15, 0.25)
const TEXT_COLOR = Color(0.9, 0.9, 0.9)
const LABEL_COLOR = Color(0.6, 0.6, 0.7)

const COLOR_GOOD = Color(0.4, 0.9, 0.4)
const COLOR_WARN = Color(0.9, 0.8, 0.2)
const COLOR_BAD = Color(0.9, 0.3, 0.3)
const COLOR_NEUTRAL = Color(0.7, 0.7, 0.8)

const CSI_COLOR_LOW = Color(0.3, 0.8, 0.3)
const CSI_COLOR_MID = Color(0.8, 0.8, 0.2)
const CSI_COLOR_HIGH = Color(0.8, 0.2, 0.2)

var _csi_bar_fill: ColorRect
var _csi_label: Label
var _yield_label: Label
var _aa_label: Label
var _corruption_label: Label
var _adaptation_label: Label
var _crack_label: Label


func _ready() -> void:
	call_deferred("_build_strip")


func _build_strip() -> void:
	for child in get_children():
		child.queue_free()

	var strip_size = size
	if strip_size.x < 10:
		strip_size = Vector2(get_viewport().get_visible_rect().size.x - 16, 42)

	var bg = ColorRect.new()
	bg.color = PANEL_BG
	bg.size = strip_size
	add_child(bg)
	_add_border(strip_size)

	var csi_title = Label.new()
	csi_title.text = "CSI"
	csi_title.position = Vector2(8, 4)
	csi_title.add_theme_font_size_override("font_size", 9)
	csi_title.add_theme_color_override("font_color", LABEL_COLOR)
	add_child(csi_title)

	var bar_bg = ColorRect.new()
	bar_bg.color = Color(0.1, 0.1, 0.15)
	bar_bg.position = Vector2(30, 4)
	bar_bg.size = Vector2(140, 12)
	add_child(bar_bg)

	_csi_bar_fill = ColorRect.new()
	_csi_bar_fill.color = CSI_COLOR_LOW
	_csi_bar_fill.position = Vector2(30, 4)
	_csi_bar_fill.size = Vector2(0, 12)
	add_child(_csi_bar_fill)

	_csi_label = Label.new()
	_csi_label.text = "0.000"
	_csi_label.position = Vector2(176, 2)
	_csi_label.add_theme_font_size_override("font_size", 10)
	_csi_label.add_theme_color_override("font_color", TEXT_COLOR)
	add_child(_csi_label)

	var yield_title = Label.new()
	yield_title.text = "Yield:"
	yield_title.position = Vector2(240, 4)
	yield_title.add_theme_font_size_override("font_size", 10)
	yield_title.add_theme_color_override("font_color", LABEL_COLOR)
	add_child(yield_title)

	_yield_label = Label.new()
	_yield_label.text = "100%"
	_yield_label.position = Vector2(280, 4)
	_yield_label.add_theme_font_size_override("font_size", 10)
	_yield_label.add_theme_color_override("font_color", COLOR_GOOD)
	add_child(_yield_label)

	var aa_title = Label.new()
	aa_title.text = "Affinity:"
	aa_title.position = Vector2(340, 4)
	aa_title.add_theme_font_size_override("font_size", 10)
	aa_title.add_theme_color_override("font_color", LABEL_COLOR)
	add_child(aa_title)

	_aa_label = Label.new()
	_aa_label.text = "0.000"
	_aa_label.position = Vector2(396, 4)
	_aa_label.add_theme_font_size_override("font_size", 10)
	_aa_label.add_theme_color_override("font_color", COLOR_NEUTRAL)
	add_child(_aa_label)

	var corr_title = Label.new()
	corr_title.text = "Corruption:"
	corr_title.position = Vector2(8, 22)
	corr_title.add_theme_font_size_override("font_size", 9)
	corr_title.add_theme_color_override("font_color", LABEL_COLOR)
	add_child(corr_title)

	_corruption_label = Label.new()
	_corruption_label.text = "0.00"
	_corruption_label.position = Vector2(76, 22)
	_corruption_label.add_theme_font_size_override("font_size", 9)
	_corruption_label.add_theme_color_override("font_color", COLOR_GOOD)
	add_child(_corruption_label)

	var adapt_title = Label.new()
	adapt_title.text = "Adaptation:"
	adapt_title.position = Vector2(140, 22)
	adapt_title.add_theme_font_size_override("font_size", 9)
	adapt_title.add_theme_color_override("font_color", LABEL_COLOR)
	add_child(adapt_title)

	_adaptation_label = Label.new()
	_adaptation_label.text = "0.00"
	_adaptation_label.position = Vector2(210, 22)
	_adaptation_label.add_theme_font_size_override("font_size", 9)
	_adaptation_label.add_theme_color_override("font_color", COLOR_NEUTRAL)
	add_child(_adaptation_label)

	var crack_title = Label.new()
	crack_title.text = "Region Crack:"
	crack_title.position = Vector2(280, 22)
	crack_title.add_theme_font_size_override("font_size", 9)
	crack_title.add_theme_color_override("font_color", LABEL_COLOR)
	add_child(crack_title)

	_crack_label = Label.new()
	_crack_label.text = "Lv.0"
	_crack_label.position = Vector2(360, 22)
	_crack_label.add_theme_font_size_override("font_size", 9)
	_crack_label.add_theme_color_override("font_color", COLOR_NEUTRAL)
	add_child(_crack_label)


func refresh(stats: Dictionary, region_id: String) -> void:
	if not is_inside_tree():
		return

	var csi = AutogrindSystem.compute_csi(region_id) if region_id != "" else 0.0
	if _csi_label:
		_csi_label.text = "%.3f" % csi
	if _csi_bar_fill:
		var bar_pct = clampf(csi / 5.0, 0.0, 1.0)
		_csi_bar_fill.size.x = bar_pct * 140.0
		if csi < 1.5:
			_csi_bar_fill.color = CSI_COLOR_LOW
		elif csi < 3.0:
			_csi_bar_fill.color = CSI_COLOR_MID
		else:
			_csi_bar_fill.color = CSI_COLOR_HIGH

	var yield_mult = stats.get("efficiency", 1.0)
	if _yield_label:
		_yield_label.text = "%.0f%%" % (yield_mult * 100.0)
		if yield_mult >= 1.0:
			_yield_label.add_theme_color_override("font_color", COLOR_GOOD)
		elif yield_mult >= 0.5:
			_yield_label.add_theme_color_override("font_color", COLOR_WARN)
		else:
			_yield_label.add_theme_color_override("font_color", COLOR_BAD)

	var aa = AutogrindSystem.automation_affinity if "automation_affinity" in AutogrindSystem else 0.0
	if _aa_label:
		_aa_label.text = "%.3f" % aa

	var corruption = stats.get("corruption", 0.0)
	if _corruption_label:
		_corruption_label.text = "%.2f" % corruption
		if corruption < 1.5:
			_corruption_label.add_theme_color_override("font_color", COLOR_GOOD)
		elif corruption < 3.0:
			_corruption_label.add_theme_color_override("font_color", COLOR_WARN)
		else:
			_corruption_label.add_theme_color_override("font_color", COLOR_BAD)

	var adaptation = stats.get("adaptation", 0.0)
	if _adaptation_label:
		_adaptation_label.text = "%.2f" % adaptation
		if adaptation < 3.0:
			_adaptation_label.add_theme_color_override("font_color", COLOR_NEUTRAL)
		elif adaptation < 6.0:
			_adaptation_label.add_theme_color_override("font_color", COLOR_WARN)
		else:
			_adaptation_label.add_theme_color_override("font_color", COLOR_BAD)

	var crack = stats.get("region_crack", 0)
	if _crack_label:
		_crack_label.text = "Lv.%d" % crack
		if crack < 3:
			_crack_label.add_theme_color_override("font_color", COLOR_NEUTRAL)
		elif crack < 6:
			_crack_label.add_theme_color_override("font_color", COLOR_WARN)
		else:
			_crack_label.add_theme_color_override("font_color", COLOR_BAD)


func _add_border(panel_size: Vector2) -> void:
	var top = ColorRect.new()
	top.color = BORDER_LIGHT
	top.size = Vector2(panel_size.x, 2)
	add_child(top)

	var left = ColorRect.new()
	left.color = BORDER_LIGHT
	left.size = Vector2(2, panel_size.y)
	add_child(left)

	var bottom = ColorRect.new()
	bottom.color = BORDER_SHADOW
	bottom.position = Vector2(0, panel_size.y - 2)
	bottom.size = Vector2(panel_size.x, 2)
	add_child(bottom)

	var right_border = ColorRect.new()
	right_border.color = BORDER_SHADOW
	right_border.position = Vector2(panel_size.x - 2, 0)
	right_border.size = Vector2(2, panel_size.y)
	add_child(right_border)
