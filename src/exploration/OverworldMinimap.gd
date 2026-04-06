extends Node
class_name OverworldMinimap

## OverworldMinimap — small corner minimap showing player position
## and transition points (villages, caves, portals) as colored dots.
## Helps with navigation on Mode 7 view where landmarks are hard to see.

const MAP_SIZE: float = 120.0  # Minimap display size in pixels
const DOT_SIZE: float = 4.0
const PLAYER_DOT_SIZE: float = 6.0

var _canvas: CanvasLayer
var _bg: ColorRect
var _player_dot: ColorRect
var _dots: Array[ColorRect] = []
var _player_ref: Node2D
var _map_width: float
var _map_height: float

## Objective pulse marker
var _objective_dot: ColorRect
var _objective_pos: Vector2 = Vector2.ZERO
var _pulse_time: float = 0.0
const OBJECTIVE_COLOR = Color(1.0, 0.85, 0.2)  # Gold
const OBJECTIVE_DOT_SIZE: float = 8.0

const DOT_COLORS: Dictionary = {
	"village": Color(0.2, 0.8, 0.2),   # Green
	"cave": Color(0.8, 0.4, 0.1),      # Orange
	"portal": Color(0.6, 0.3, 0.9),    # Purple
	"dragon": Color(1.0, 0.2, 0.2),    # Red
}

const SHORT_NAMES: Dictionary = {
	"village_entrance": "Harmonia",
	"cave_entrance": "Cave",
	"ice_dragon_cave": "Ice",
	"shadow_dragon_cave": "Shadow",
	"lightning_dragon_cave": "Storm",
	"fire_dragon_cave": "Fire",
	"frosthold_entrance": "Frost",
	"eldertree_entrance": "Elder",
	"grimhollow_entrance": "Grim",
	"sandrift_entrance": "Sand",
	"ironhaven_entrance": "Iron",
	"steampunk_portal": "Portal",
}


func setup(parent: Node, player: Node2D, map_w: int, map_h: int, tile_size: int, transitions: Dictionary) -> void:
	_player_ref = player
	_map_width = float(map_w * tile_size)
	_map_height = float(map_h * tile_size)

	_canvas = CanvasLayer.new()
	_canvas.name = "Minimap"
	_canvas.layer = 85
	parent.add_child(_canvas)

	# Background
	_bg = ColorRect.new()
	_bg.color = Color(0.0, 0.0, 0.0, 0.4)
	_bg.size = Vector2(MAP_SIZE + 8, MAP_SIZE + 8)
	_bg.position = Vector2(1280 - MAP_SIZE - 24, 16)  # Top-right corner
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_bg)

	# Border
	var border = ColorRect.new()
	border.color = Color(0.5, 0.5, 0.5, 0.6)
	border.size = Vector2(MAP_SIZE + 4, MAP_SIZE + 4)
	border.position = _bg.position + Vector2(2, 2)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(border)

	var inner = ColorRect.new()
	inner.color = Color(0.08, 0.12, 0.08, 0.8)
	inner.size = Vector2(MAP_SIZE, MAP_SIZE)
	inner.position = _bg.position + Vector2(4, 4)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(inner)

	# Transition dots with labels
	for key in transitions:
		var pos: Vector2 = transitions[key]
		if pos == Vector2.ZERO:
			continue
		var dot_type = _get_dot_type(key)
		var color = DOT_COLORS.get(dot_type, Color(0.7, 0.7, 0.7))
		var label_text = SHORT_NAMES.get(key, "")
		_add_dot(pos, color, label_text)

	# Player dot (on top)
	_player_dot = ColorRect.new()
	_player_dot.color = Color(1.0, 1.0, 1.0)
	_player_dot.size = Vector2(PLAYER_DOT_SIZE, PLAYER_DOT_SIZE)
	_player_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_player_dot)

	# Legend below minimap
	var legend_y = _bg.position.y + _bg.size.y + 4
	var legend_x = _bg.position.x
	var legend_items = [
		["You", Color(1.0, 1.0, 1.0)],
		["Village", DOT_COLORS["village"]],
		["Cave", DOT_COLORS["cave"]],
		["Dragon", DOT_COLORS["dragon"]],
		["Portal", DOT_COLORS["portal"]],
	]
	for i in range(legend_items.size()):
		var item = legend_items[i]
		var y_off = legend_y + i * 11
		var dot = ColorRect.new()
		dot.color = item[1]
		dot.size = Vector2(4, 4)
		dot.position = Vector2(legend_x + 4, y_off + 2)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.add_child(dot)
		var lbl = Label.new()
		lbl.text = item[0]
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.add_theme_color_override("font_color", item[1].lightened(0.2))
		lbl.position = Vector2(legend_x + 12, y_off - 2)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.add_child(lbl)


func _get_dot_type(key: String) -> String:
	if "dragon" in key:
		return "dragon"
	if "cave" in key:
		return "cave"
	if "village" in key or "entrance" in key:
		return "village"
	if "portal" in key:
		return "portal"
	return "village"


func _add_dot(world_pos: Vector2, color: Color, label_text: String = "") -> void:
	var dot = ColorRect.new()
	dot.color = color
	dot.size = Vector2(DOT_SIZE, DOT_SIZE)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var map_pos = _world_to_minimap(world_pos)
	dot.position = map_pos - Vector2(DOT_SIZE / 2, DOT_SIZE / 2)
	_canvas.add_child(dot)
	_dots.append(dot)

	if label_text != "":
		var lbl = Label.new()
		lbl.text = label_text
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.add_theme_color_override("font_color", color.lightened(0.3))
		lbl.position = map_pos + Vector2(DOT_SIZE, -4)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.add_child(lbl)


func _world_to_minimap(world_pos: Vector2) -> Vector2:
	var nx = world_pos.x / _map_width
	var ny = world_pos.y / _map_height
	var origin = _bg.position + Vector2(4, 4)
	return origin + Vector2(nx * MAP_SIZE, ny * MAP_SIZE)


func set_objective(world_pos: Vector2) -> void:
	_objective_pos = world_pos
	if _objective_pos == Vector2.ZERO:
		return
	if not _objective_dot:
		_objective_dot = ColorRect.new()
		_objective_dot.color = OBJECTIVE_COLOR
		_objective_dot.size = Vector2(OBJECTIVE_DOT_SIZE, OBJECTIVE_DOT_SIZE)
		_objective_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.add_child(_objective_dot)
	var map_pos = _world_to_minimap(_objective_pos)
	_objective_dot.position = map_pos - Vector2(OBJECTIVE_DOT_SIZE / 2, OBJECTIVE_DOT_SIZE / 2)


func update(player_pos: Vector2) -> void:
	if not _player_dot:
		return
	var map_pos = _world_to_minimap(player_pos)
	_player_dot.position = map_pos - Vector2(PLAYER_DOT_SIZE / 2, PLAYER_DOT_SIZE / 2)

	# Pulse objective marker
	if _objective_dot:
		_pulse_time += 0.05
		var alpha = 0.4 + 0.6 * abs(sin(_pulse_time * 3.0))
		_objective_dot.color = Color(OBJECTIVE_COLOR.r, OBJECTIVE_COLOR.g, OBJECTIVE_COLOR.b, alpha)
