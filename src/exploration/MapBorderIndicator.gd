extends Node
class_name MapBorderIndicator

## MapBorderIndicator — shows edge-of-map warnings when player approaches boundaries.
## Displays a subtle pulsing arrow + "Edge of map" text on the relevant screen edge.

var _canvas: CanvasLayer
var _labels: Dictionary = {}  # "north", "south", "east", "west" -> Label
var _player_ref: Node2D
var _map_width: float
var _map_height: float
var _pulse_time: float = 0.0

const EDGE_THRESHOLD: float = 128.0  # Pixels from map edge to start showing
const LABEL_COLOR = Color(0.8, 0.7, 0.5, 0.0)  # Starts invisible, alpha driven by proximity
const ARROW_FONT_SIZE: int = 14
const TEXT_FONT_SIZE: int = 10

const EDGE_CONFIG = {
	"north": {"arrow": "▲", "text": "Edge of world", "anchor_x": 0.5, "anchor_y": 0.0, "offset": Vector2(0, 50)},
	"south": {"arrow": "▼", "text": "Edge of world", "anchor_x": 0.5, "anchor_y": 1.0, "offset": Vector2(0, -30)},
	"west": {"arrow": "◄", "text": "Edge", "anchor_x": 0.0, "anchor_y": 0.5, "offset": Vector2(20, 0)},
	"east": {"arrow": "►", "text": "Edge", "anchor_x": 1.0, "anchor_y": 0.5, "offset": Vector2(-40, 0)},
}


func setup(parent: Node, player: Node2D, map_w: int, map_h: int, tile_size: int) -> void:
	_player_ref = player
	_map_width = float(map_w * tile_size)
	_map_height = float(map_h * tile_size)

	_canvas = CanvasLayer.new()
	_canvas.name = "MapBorderIndicators"
	_canvas.layer = 80
	parent.add_child(_canvas)

	var vp_size = parent.get_viewport().get_visible_rect().size
	if vp_size.x == 0:
		vp_size = Vector2(1280, 720)

	for dir in EDGE_CONFIG:
		var cfg = EDGE_CONFIG[dir]
		var lbl = Label.new()
		lbl.text = "%s %s" % [cfg["arrow"], cfg["text"]]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", TEXT_FONT_SIZE)
		lbl.add_theme_color_override("font_color", LABEL_COLOR)
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		lbl.position = Vector2(
			vp_size.x * cfg["anchor_x"] + cfg["offset"].x - 40,
			vp_size.y * cfg["anchor_y"] + cfg["offset"].y
		)
		lbl.size = Vector2(80, 20)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.visible = false
		_canvas.add_child(lbl)
		_labels[dir] = lbl


func update(player_pos: Vector2) -> void:
	if _labels.is_empty():
		return

	_pulse_time += 0.04
	var pulse = 0.5 + 0.5 * sin(_pulse_time * 3.0)

	# Check proximity to each edge
	var north_dist = player_pos.y
	var south_dist = _map_height - player_pos.y
	var west_dist = player_pos.x
	var east_dist = _map_width - player_pos.x

	_update_edge("north", north_dist, pulse)
	_update_edge("south", south_dist, pulse)
	_update_edge("west", west_dist, pulse)
	_update_edge("east", east_dist, pulse)


func _update_edge(dir: String, dist: float, pulse: float) -> void:
	var lbl: Label = _labels.get(dir)
	if not lbl:
		return
	if dist < EDGE_THRESHOLD:
		var alpha = (1.0 - dist / EDGE_THRESHOLD) * pulse
		lbl.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5, alpha))
		lbl.visible = true
	else:
		lbl.visible = false
