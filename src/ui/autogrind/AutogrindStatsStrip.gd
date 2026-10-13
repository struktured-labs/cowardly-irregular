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


## ⛔ Every field used to sit at an ABSOLUTE x, authored for GameLoop's full-width consumer
## (vp_size.x - 8, ~1272). AutogrindDashboard:242 gives the same component stats_w = mini_w = 296,
## where the authored row needs ~422 -- so "Region Crack:" drew cut off mid-word. The strip now lays
## itself out from the width it is GIVEN: authored positions while a group fits, flow-and-wrap when
## it does not, and it reports the height it used so a caller can reserve it.
const PAD := 8.0
const ROW_H := 18.0
const GAP := 16.0
const BAR_W := 140.0
const BAR_GAP := 6.0

## group -> [title, sample value, title font, value font, authored title x, authored value x, has bar]
const FIELDS := [
	[["CSI", "0.000", 9, 10, 8.0, 176.0, true],
	 ["Yield:", "100%", 10, 10, 240.0, 280.0, false],
	 ["Affinity:", "0.000", 10, 10, 340.0, 396.0, false]],
	[["Corruption:", "0.00", 9, 9, 8.0, 76.0, false],
	 ["Adaptation:", "0.00", 9, 9, 140.0, 210.0, false],
	 ["Region Crack:", "Lv.0", 9, 9, 280.0, 360.0, false]],
]

var _used_height: float = 42.0


static func _text_w(t: String, fs: int) -> float:
	return ThemeDB.fallback_font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


## The single layout computation. Both the builder and height_for_width() read it, so a caller's
## reserved height cannot disagree with what is drawn.
static func compute_layout(strip_w: float) -> Dictionary:
	var rows: Array = []
	var y: float = 4.0
	for g in FIELDS.size():
		var group: Array = FIELDS[g]
		var authored_right: float = 0.0
		for f in group:
			authored_right = maxf(authored_right, float(f[5]) + _text_w(str(f[1]), int(f[3])))
		var placed: Array = []
		if authored_right <= strip_w - PAD:
			for f in group:
				placed.append({"title_x": float(f[4]), "value_x": float(f[5]), "y": y, "bar": bool(f[6])})
		else:
			var cx: float = PAD
			for f in group:
				var tw: float = _text_w(str(f[0]), int(f[2]))
				var vw: float = _text_w(str(f[1]), int(f[3]))
				var bar: float = (BAR_W + BAR_GAP) if bool(f[6]) else 0.0
				var fw: float = tw + 4.0 + bar + vw
				if cx > PAD and cx + fw > strip_w - PAD:
					cx = PAD
					y += ROW_H
				placed.append({"title_x": cx, "value_x": cx + tw + 4.0 + bar, "y": y, "bar": bool(f[6])})
				cx += fw + GAP
		rows.append(placed)
		y += ROW_H
	return {"rows": rows, "height": y + 2.0}


## What a caller must reserve. AutogrindDashboard used a literal 42 and cut the strip off.
static func height_for_width(strip_w: float) -> float:
	return float(compute_layout(strip_w)["height"])


func get_used_height() -> float:
	return _used_height


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

	var lay: Dictionary = compute_layout(strip_size.x)
	_used_height = float(lay["height"])
	var rows: Array = lay["rows"]
	var colors: Array = [[LABEL_COLOR, TEXT_COLOR], [LABEL_COLOR, COLOR_GOOD], [LABEL_COLOR, COLOR_NEUTRAL]]
	var value_sink: Array = []
	for g in FIELDS.size():
		for i in (FIELDS[g] as Array).size():
			var f: Array = FIELDS[g][i]
			var at: Dictionary = rows[g][i]
			var title := Label.new()
			title.text = str(f[0])
			title.position = Vector2(float(at["title_x"]), float(at["y"]))
			title.add_theme_font_size_override("font_size", int(f[2]))
			title.add_theme_color_override("font_color", LABEL_COLOR)
			add_child(title)
			if bool(at["bar"]):
				var bar_bg := ColorRect.new()
				bar_bg.color = Color(0.1, 0.1, 0.15)
				bar_bg.position = Vector2(float(at["title_x"]) + 22.0, float(at["y"]))
				bar_bg.size = Vector2(BAR_W, 12)
				add_child(bar_bg)
				_csi_bar_fill = ColorRect.new()
				_csi_bar_fill.color = CSI_COLOR_LOW
				_csi_bar_fill.position = bar_bg.position
				_csi_bar_fill.size = Vector2(0, 12)
				add_child(_csi_bar_fill)
			var val := Label.new()
			val.text = str(f[1])
			val.position = Vector2(float(at["value_x"]), float(at["y"]) - (2.0 if g == 0 and i == 0 else 0.0))
			val.add_theme_font_size_override("font_size", int(f[3]))
			val.add_theme_color_override("font_color", colors[i][1] if g == 0 else (COLOR_GOOD if i == 0 else COLOR_NEUTRAL))
			add_child(val)
			value_sink.append(val)
	_csi_label = value_sink[0]
	_yield_label = value_sink[1]
	_aa_label = value_sink[2]
	_corruption_label = value_sink[3]
	_adaptation_label = value_sink[4]
	_crack_label = value_sink[5]


func refresh(stats: Dictionary, region_id: String) -> void:
	if not is_inside_tree():
		return

	# CSI is now 0.0-1.0 range (from get_csi or stats dict)
	var csi = stats.get("csi", AutogrindSystem.get_csi(region_id) if region_id != "" else 0.0)
	if _csi_label:
		_csi_label.text = "%.0f%%" % (csi * 100.0)
	if _csi_bar_fill:
		var bar_pct = clampf(csi, 0.0, 1.0)
		_csi_bar_fill.size.x = bar_pct * 140.0
		if csi < 0.4:
			_csi_bar_fill.color = CSI_COLOR_LOW
		elif csi < 0.7:
			_csi_bar_fill.color = CSI_COLOR_MID
		else:
			_csi_bar_fill.color = CSI_COLOR_HIGH

	## ⛔ THE FALLBACK SHOWED `efficiency` UNDER THE YIELD LABEL — a different quantity, not a
	## default, so an absent key rendered a plausible wrong number instead of nothing. Mirrors the
	## CSI line above: ask the system, which is the same source the stats dict is built from.
	var yield_mult = stats.get("yield_multiplier",
		AutogrindSystem.get_yield_multiplier(region_id) if region_id != "" else 1.0)
	if _yield_label:
		_yield_label.text = "%.0f%%" % (yield_mult * 100.0)
		if yield_mult >= 0.8:
			_yield_label.add_theme_color_override("font_color", COLOR_GOOD)
		elif yield_mult >= 0.5:
			_yield_label.add_theme_color_override("font_color", COLOR_WARN)
		else:
			_yield_label.add_theme_color_override("font_color", COLOR_BAD)

	var aa = stats.get("automation_affinity", 0.0)
	if _aa_label:
		_aa_label.text = "%.3f" % aa

	var corruption = stats.get("corruption", 0.0)
	## Derived, not 5.0 typed again — this fallback and the Summary's both restated the shipped default.
	var corruption_max = stats.get("corruption_threshold", AutogrindSystem.DEFAULT_CORRUPTION_THRESHOLD)
	if _corruption_label:
		# Show current / max so the player sees proximity to collapse at a glance.
		_corruption_label.text = "%.2f / %.1f" % [corruption, corruption_max]
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
