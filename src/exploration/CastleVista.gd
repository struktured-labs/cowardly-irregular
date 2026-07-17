class_name CastleVista
extends Node2D
## Distant Castle Harmonia skyline for the village's north edge (struktured
## 2026-07-16: the after_cave puppets "look up towards top of village to see
## the castle but its just the edge of the village, it looks dumb"). Drawn
## scenery, always present — the castle exists before its overworld reveal.
## Origin = center of the castle's baseline; silhouette rises ~88px above it.

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


func _draw() -> void:
	var win: Color = WINDOW_NIGHT if _night else WINDOW_DAY
	# Flanking towers
	for side in [-1, 1]:
		var tx: float = side * 92.0
		draw_rect(Rect2(tx - 16, -76, 32, 76), STONE_DARK)
		draw_colored_polygon(PackedVector2Array([
			Vector2(tx - 20, -76), Vector2(tx + 20, -76), Vector2(tx, -104)]), ROOF)
		draw_rect(Rect2(tx - 4, -58, 8, 12), win)
		draw_rect(Rect2(tx - 4, -34, 8, 12), win)
	# Curtain wall linking towers to the keep
	draw_rect(Rect2(-92, -34, 184, 34), STONE_DARK)
	for i in range(-4, 5):
		draw_rect(Rect2(i * 20 - 5, -42, 10, 8), STONE_DARK)
	# Central keep
	draw_rect(Rect2(-52, -70, 104, 70), STONE)
	for i in range(-2, 3):
		draw_rect(Rect2(i * 19 - 6, -78, 12, 8), STONE)
	# Keep windows + gate
	for i in [-1, 0, 1]:
		draw_rect(Rect2(i * 30 - 5, -56, 10, 14), win)
	draw_rect(Rect2(-12, -22, 24, 22), STONE_DARK)
	draw_circle(Vector2(0, -22), 12.0, STONE_DARK)
	# Banner spire
	draw_line(Vector2(0, -78), Vector2(0, -100), STONE_DARK, 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -100), Vector2(22, -94), Vector2(0, -88)]), BANNER)
