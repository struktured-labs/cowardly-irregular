class_name CastleVista
extends Node2D
## Distant Castle Harmonia skyline for the after_cave "look east" pan.
## Origin sits ON the horizon; EVERYTHING draws above it (negative y), in the
## void beyond the map's top edge, so the village tilemap can never occlude it.
## Pinned by test_castle_vista_visibility_regression.

const SPAN_X := 1500.0
const SKY_HEIGHT := 440.0
const SKY_BANDS := 44
const CASTLE_BASE := -34.0
const CASTLE_SCALE := 1.35
const RIDGE_HEIGHT := 58.0
const TREE_SPACING := 26.0
const HAZE := 0.22

const SKY_TOP_DAY := Color(0.36, 0.58, 0.85)
const SKY_HORIZON_DAY := Color(0.83, 0.87, 0.88)
const SKY_TOP_NIGHT := Color(0.04, 0.05, 0.16)
const SKY_HORIZON_NIGHT := Color(0.19, 0.20, 0.35)
const RIDGE_DAY := Color(0.57, 0.66, 0.73)
const RIDGE_NIGHT := Color(0.11, 0.13, 0.25)
const TREE_DAY := Color(0.15, 0.30, 0.19)
const TREE_NIGHT := Color(0.04, 0.08, 0.11)

const STONE := Color(0.52, 0.54, 0.66)
const STONE_DARK := Color(0.42, 0.44, 0.56)
const ROOF := Color(0.30, 0.34, 0.58)
const BANNER := Color(0.72, 0.16, 0.20)
const WINDOW_DAY := Color(0.25, 0.27, 0.38)
const WINDOW_NIGHT := Color(1.0, 0.82, 0.45)

var _night: bool = false
var _poll: float = 0.0


func _ready() -> void:
	z_index = -2


func _process(delta: float) -> void:
	_poll += delta
	if _poll < 0.5:
		return
	_poll = 0.0
	var gs = get_node_or_null("/root/GameState")
	var night_now: bool = gs != null and gs.has_method("is_night") and bool(gs.is_night())
	if night_now != _night:
		_night = night_now
		queue_redraw()


func _horizon_color() -> Color:
	return SKY_HORIZON_NIGHT if _night else SKY_HORIZON_DAY


## Distance haze — pulls a colour toward the horizon so the castle reads as far off.
func _hazed(c: Color) -> Color:
	return c.lerp(_horizon_color(), HAZE)


func _draw() -> void:
	_draw_sky()
	_draw_ridge()
	_draw_castle()
	_draw_treeline()


func _draw_sky() -> void:
	var top: Color = SKY_TOP_NIGHT if _night else SKY_TOP_DAY
	var horizon: Color = _horizon_color()
	var band_h: float = SKY_HEIGHT / float(SKY_BANDS)
	for i in SKY_BANDS:
		var t: float = float(i) / float(SKY_BANDS - 1)
		var y: float = -SKY_HEIGHT + float(i) * band_h
		# Overdraw by 1px so seams can't show between bands.
		draw_rect(Rect2(-SPAN_X * 0.5, y, SPAN_X, band_h + 1.0), top.lerp(horizon, t))


func _draw_ridge() -> void:
	var ridge: Color = RIDGE_NIGHT if _night else RIDGE_DAY
	var pts := PackedVector2Array()
	var half: float = SPAN_X * 0.5
	pts.append(Vector2(-half, 0))
	var x: float = -half
	while x <= half:
		var h: float = RIDGE_HEIGHT * (0.55 + 0.45 * sin(x * 0.011) * cos(x * 0.004))
		pts.append(Vector2(x, -h))
		x += 24.0
	pts.append(Vector2(half, 0))
	draw_colored_polygon(pts, ridge)


func _draw_treeline() -> void:
	var tree: Color = TREE_NIGHT if _night else TREE_DAY
	var half: float = SPAN_X * 0.5
	var x: float = -half
	while x <= half:
		# Two incommensurate frequencies so the ridge doesn't read as a comb.
		var h: float = 20.0 + 14.0 * abs(sin(x * 0.037)) + 6.0 * sin(x * 0.0091)
		var w: float = 9.0 + 4.0 * abs(cos(x * 0.023))
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - w, 2), Vector2(x + w, 2), Vector2(x, -h)]), tree)
		x += TREE_SPACING


func _draw_castle() -> void:
	var win: Color = _hazed(WINDOW_NIGHT if _night else WINDOW_DAY)
	var stone: Color = _hazed(STONE)
	var stone_dark: Color = _hazed(STONE_DARK)
	var roof: Color = _hazed(ROOF)
	var banner: Color = _hazed(BANNER)
	draw_set_transform(Vector2(0, CASTLE_BASE), 0.0, Vector2(CASTLE_SCALE, CASTLE_SCALE))
	# Flanking towers
	for side in [-1, 1]:
		var tx: float = side * 92.0
		draw_rect(Rect2(tx - 16, -76, 32, 76), stone_dark)
		draw_colored_polygon(PackedVector2Array([
			Vector2(tx - 20, -76), Vector2(tx + 20, -76), Vector2(tx, -104)]), roof)
		draw_rect(Rect2(tx - 4, -58, 8, 12), win)
		draw_rect(Rect2(tx - 4, -34, 8, 12), win)
	# Curtain wall linking towers to the keep
	draw_rect(Rect2(-92, -34, 184, 34), stone_dark)
	for i in range(-4, 5):
		draw_rect(Rect2(i * 20 - 5, -42, 10, 8), stone_dark)
	# Central keep
	draw_rect(Rect2(-52, -70, 104, 70), stone)
	for i in range(-2, 3):
		draw_rect(Rect2(i * 19 - 6, -78, 12, 8), stone)
	# Keep windows + gate
	for i in [-1, 0, 1]:
		draw_rect(Rect2(i * 30 - 5, -56, 10, 14), win)
	draw_rect(Rect2(-12, -22, 24, 22), stone_dark)
	draw_circle(Vector2(0, -22), 12.0, stone_dark)
	# Banner spire
	draw_line(Vector2(0, -78), Vector2(0, -100), stone_dark, 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -100), Vector2(22, -94), Vector2(0, -88)]), banner)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
