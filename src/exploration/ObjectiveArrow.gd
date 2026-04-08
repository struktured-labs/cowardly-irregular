extends Node
class_name ObjectiveArrow

## ObjectiveArrow — screen-edge directional arrow pointing to quest objective.
## Shows a pulsing gold chevron at the screen edge when the objective is off-screen.
## Disappears when the objective is visible on screen.

var _canvas: CanvasLayer
var _arrow_label: Label
var _target_pos: Vector2 = Vector2.ZERO
var _player_ref: Node2D
var _pulse_time: float = 0.0

const ARROW_MARGIN: float = 60.0
const ARROW_COLOR = Color(1.0, 0.85, 0.3)
const ARROWS = {
	"up": "▲ Objective",
	"down": "▼ Objective",
	"left": "◄ Objective",
	"right": "Objective ►",
	"up_left": "◤ Objective",
	"up_right": "Objective ◥",
	"down_left": "◣ Objective",
	"down_right": "Objective ◢",
}


func setup(parent: Node, player: Node2D) -> void:
	_player_ref = player
	_canvas = CanvasLayer.new()
	_canvas.name = "ObjectiveArrow"
	_canvas.layer = 82
	parent.add_child(_canvas)

	_arrow_label = Label.new()
	_arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrow_label.add_theme_font_size_override("font_size", 14)
	_arrow_label.add_theme_color_override("font_color", ARROW_COLOR)
	_arrow_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_arrow_label.add_theme_constant_override("shadow_offset_x", 1)
	_arrow_label.add_theme_constant_override("shadow_offset_y", 1)
	_arrow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow_label.visible = false
	_canvas.add_child(_arrow_label)


func set_target(world_pos: Vector2) -> void:
	_target_pos = world_pos


func update(player_pos: Vector2) -> void:
	if not _arrow_label or _target_pos == Vector2.ZERO:
		return

	_pulse_time += 0.04
	var alpha = 0.5 + 0.5 * sin(_pulse_time * 3.0)

	var vp = _arrow_label.get_viewport()
	if not vp:
		return
	var vp_size = vp.get_visible_rect().size
	if vp_size.x == 0:
		return

	# Direction from player to objective in world space
	var dir = _target_pos - player_pos
	var dist = dir.length()

	# Hide if close enough (objective on screen)
	if dist < 200.0:
		_arrow_label.visible = false
		return

	# Determine direction
	var angle = dir.angle()
	var dir_key = ""
	if angle < -2.35:
		dir_key = "left"
	elif angle < -0.78:
		dir_key = "up" if abs(dir.x) < abs(dir.y) * 0.5 else ("up_left" if dir.x < 0 else "up_right")
	elif angle < 0.78:
		dir_key = "right" if dir.x > 0 else "left"
	elif angle < 2.35:
		dir_key = "down" if abs(dir.x) < abs(dir.y) * 0.5 else ("down_left" if dir.x < 0 else "down_right")
	else:
		dir_key = "left"

	_arrow_label.text = ARROWS.get(dir_key, "► Objective")
	_arrow_label.add_theme_color_override("font_color", Color(ARROW_COLOR.r, ARROW_COLOR.g, ARROW_COLOR.b, alpha))

	# Position at screen edge
	var norm_dir = dir.normalized()
	var edge_x = clampf(vp_size.x / 2.0 + norm_dir.x * (vp_size.x / 2.0 - ARROW_MARGIN), ARROW_MARGIN, vp_size.x - ARROW_MARGIN - 80)
	var edge_y = clampf(vp_size.y / 2.0 + norm_dir.y * (vp_size.y / 2.0 - ARROW_MARGIN), ARROW_MARGIN, vp_size.y - ARROW_MARGIN)

	_arrow_label.position = Vector2(edge_x, edge_y)
	_arrow_label.size = Vector2(120, 20)
	_arrow_label.visible = true
