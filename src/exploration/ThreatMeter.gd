extends Node
class_name ThreatMeter

## ThreatMeter — subtle danger indicator showing proximity to roaming monsters.
## Small pulsing icon at bottom-center that intensifies as monsters approach.

var _canvas: CanvasLayer
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _icon_label: Label
var _player_ref: Node2D
var _spawner_ref: Node  # MonsterSpawner

const DETECTION_RANGE: float = 300.0  # Start showing when monster within this range
const BAR_WIDTH: float = 80.0
const BAR_HEIGHT: float = 6.0
const ICON_FONT_SIZE := 12
const ICON_BOX := 16  ## the authored "!" width; it grows by the Text Size factor
const ICON_TOP: float = 36.0  ## the authored label top above the screen's bottom edge, at 100%

var _vp_size := Vector2(1280, 720)


func setup(parent: Node, player: Node2D, spawner: Node) -> void:
	_player_ref = player
	_spawner_ref = spawner

	_canvas = CanvasLayer.new()
	_canvas.name = "ThreatMeter"
	_canvas.layer = 81
	parent.add_child(_canvas)

	var vp_size = parent.get_viewport().get_visible_rect().size
	if vp_size.x == 0:
		vp_size = Vector2(1280, 720)
	_vp_size = vp_size

	var cx = vp_size.x / 2.0

	# "!" icon
	_icon_label = Label.new()
	_icon_label.text = "!"
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.add_theme_font_size_override("font_size", ICON_FONT_SIZE)
	TextScale.apply(_icon_label)
	_layout_icon()
	_icon_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.2, 0.0))
	_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_icon_label)

	# Background bar
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.15, 0.1, 0.1, 0.0)
	_bar_bg.position = Vector2(cx - BAR_WIDTH / 2.0, vp_size.y - 22)
	_bar_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_bar_bg)

	# Fill bar
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(0.9, 0.2, 0.1, 0.0)
	_bar_fill.position = _bar_bg.position
	_bar_fill.size = Vector2(0, BAR_HEIGHT)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_bar_fill)
	if not GameState.text_size_scale_changed.is_connected(_on_text_size_changed):
		GameState.text_size_scale_changed.connect(_on_text_size_changed)


## The glyph's BASELINE stays where it was authored at every size, so a larger "!" grows UPWARD, never onto the bar.
## (A Label clamps up to its line height, 23 px for 12 px in this theme, so the box was never the thing to anchor.)
func _layout_icon() -> void:
	var box := float(TextScale.scaled(ICON_BOX))
	var font: Font = _icon_label.get_theme_font("font")
	var asc: float = font.get_ascent(_icon_label.get_theme_font_size("font_size")) if font else 0.0
	var baseline: float = authored_baseline()
	_icon_label.size = Vector2(box, box)
	_icon_label.position = Vector2(_vp_size.x / 2.0 - box / 2.0, baseline - asc)


func authored_baseline() -> float:
	var font: Font = _icon_label.get_theme_font("font") if _icon_label else null
	return _vp_size.y - ICON_TOP + (font.get_ascent(ICON_FONT_SIZE) if font else 0.0)


func _on_text_size_changed(_scale: float) -> void:
	if _icon_label == null:
		return
	TextScale.apply(_icon_label)
	_layout_icon()

func _exit_tree() -> void:
	if GameState.text_size_scale_changed.is_connected(_on_text_size_changed):
		GameState.text_size_scale_changed.disconnect(_on_text_size_changed)


func update(player_pos: Vector2) -> void:
	if not _spawner_ref or not _bar_fill:
		return

	# Find nearest monster distance
	var nearest_dist = DETECTION_RANGE + 1.0
	var seen: Vector2 = player_pos + RoamingMonster.seen_offset()
	var roamers: Array = _spawner_ref.live_monsters() if _spawner_ref.has_method("live_monsters") else _spawner_ref.get_children()
	for child in roamers:
		if child is Node2D and child.get("_active") != false:
			var dist = seen.distance_to(child.global_position)
			nearest_dist = minf(nearest_dist, dist)

	if nearest_dist > DETECTION_RANGE:
		# No threat — fade out
		_bar_bg.color.a = maxf(_bar_bg.color.a - 0.05, 0.0)
		_bar_fill.color.a = _bar_bg.color.a
		_icon_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.2, _bar_bg.color.a))
		_bar_fill.size.x = 0
		return

	# Threat level: 0 (far) to 1 (chase range)
	var threat = 1.0 - clampf(nearest_dist / DETECTION_RANGE, 0.0, 1.0)
	var alpha = 0.3 + threat * 0.5

	_bar_bg.color.a = alpha * 0.5
	_bar_fill.size.x = BAR_WIDTH * threat
	_bar_fill.color = Color(
		lerpf(0.8, 1.0, threat),
		lerpf(0.6, 0.1, threat),
		0.1,
		alpha
	)
	_icon_label.add_theme_color_override("font_color", Color(
		lerpf(0.8, 1.0, threat),
		lerpf(0.5, 0.15, threat),
		0.1,
		alpha
	))
