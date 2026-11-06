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
const ARROW_FONT_SIZE := 14
const MIN_BOX := Vector2(120, 20)  ## the authored box; it only grows when the scaled text needs it
const ARROW_COLOR = Color(1.0, 0.85, 0.3)
const ARROWS = {
	"up": "^ Objective",
	"down": "v Objective",
	"left": "< Objective",
	"right": "Objective >",
	"up_left": "<^ Objective",
	"up_right": "Objective ^>",
	"down_left": "<v Objective",
	"down_right": "Objective v>",
}


func setup(parent: Node, player: Node2D) -> void:
	_player_ref = player
	_canvas = CanvasLayer.new()
	_canvas.name = "ObjectiveArrow"
	_canvas.layer = 82
	parent.add_child(_canvas)

	_arrow_label = Label.new()
	_arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrow_label.add_theme_font_size_override("font_size", ARROW_FONT_SIZE)
	TextScale.apply(_arrow_label)
	_arrow_label.add_theme_color_override("font_color", ARROW_COLOR)
	_arrow_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_arrow_label.add_theme_constant_override("shadow_offset_x", 1)
	_arrow_label.add_theme_constant_override("shadow_offset_y", 1)
	_arrow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow_label.visible = false
	_canvas.add_child(_arrow_label)
	if not GameState.text_size_scale_changed.is_connected(_on_text_size_changed):
		GameState.text_size_scale_changed.connect(_on_text_size_changed)


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

	_arrow_label.text = ARROWS.get(dir_key, "> Objective")
	_arrow_label.add_theme_color_override("font_color", Color(ARROW_COLOR.r, ARROW_COLOR.g, ARROW_COLOR.b, alpha))

	# Position at screen edge
	var norm_dir = dir.normalized()
	var box := box_size()
	var edge_x = clampf(vp_size.x / 2.0 + norm_dir.x * (vp_size.x / 2.0 - ARROW_MARGIN), ARROW_MARGIN, vp_size.x - ARROW_MARGIN - (box.x - 40.0))  ## the authored 20px right inset at any box width
	var edge_y = clampf(vp_size.y / 2.0 + norm_dir.y * (vp_size.y / 2.0 - ARROW_MARGIN), ARROW_MARGIN, vp_size.y - ARROW_MARGIN)

	_arrow_label.position = clear_of_hud(Rect2(edge_x, edge_y, box.x, box.y), _reserved_rects(), vp_size)
	_arrow_label.size = box
	_arrow_label.visible = true


## The arrow's box: the widest arrow text at the live font size, never smaller than the authored box.
func box_size() -> Vector2:
	var font: Font = _arrow_label.get_theme_font("font") if _arrow_label else null
	if font == null:
		return MIN_BOX
	var px: int = _arrow_label.get_theme_font_size("font_size")
	var w: float = 0.0
	for t in ARROWS.values():
		w = maxf(w, font.get_string_size(str(t), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)
	return Vector2(maxf(MIN_BOX.x, w + 8.0), maxf(MIN_BOX.y, font.get_height(px)))


func _on_text_size_changed(_scale: float) -> void:
	TextScale.apply(_arrow_label)


func _exit_tree() -> void:
	if GameState.text_size_scale_changed.is_connected(_on_text_size_changed):
		GameState.text_size_scale_changed.disconnect(_on_text_size_changed)


func _reserved_rects() -> Array:
	var out: Array = []
	if _arrow_label == null or not _arrow_label.is_inside_tree():
		return out
	for n in _arrow_label.get_tree().get_nodes_in_group(OverworldMinimap.HUD_GROUP):
		if n.has_method("reserved_rect"):
			var r: Rect2 = n.reserved_rect()
			if r.has_area():
				out.append(r)
	return out


## Up-right objectives put the arrow on the minimap legend ("Objective >" over "Cave"); step below a reserved
## HUD block, or to its left when below would leave the screen.
static func clear_of_hud(arrow: Rect2, reserved: Array, vp_size: Vector2) -> Vector2:
	for r in reserved:
		if not arrow.intersects(r):
			continue
		if r.end.y + 4.0 + arrow.size.y <= vp_size.y:
			arrow.position.y = r.end.y + 4.0
		else:
			arrow.position.x = r.position.x - arrow.size.x - 4.0
	return arrow.position
