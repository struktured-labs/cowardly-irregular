extends Node
class_name DangerZone

## DangerZone — pulsing red vignette near boss areas whose boss still stands.
## Intensity scales with proximity to danger points. Visual only: the `danger` bed is the near-death track, so the field never plays it.

const DANGER_RADIUS: float = 256.0  # Pixels — start showing warning
const FULL_DANGER_RADIUS: float = 96.0  # Full intensity at this distance
const PULSE_SPEED: float = 3.0

var _canvas: CanvasLayer
var _vignette: ColorRect
var _danger_points: Array[Vector2] = []
var _clear_flags: Array[String] = []
var _player_ref: Node2D
var _pulse_timer: float = 0.0
var _current_intensity: float = 0.0


func setup(parent: Node, player: Node2D, points: Array[Vector2], clear_flags: Array[String] = []) -> void:
	_player_ref = player
	_danger_points = points
	_clear_flags = clear_flags

	_canvas = CanvasLayer.new()
	_canvas.name = "DangerOverlay"
	_canvas.layer = 80
	parent.add_child(_canvas)

	# Red vignette — full-screen ColorRect with transparent center
	_vignette = ColorRect.new()
	_vignette.name = "DangerVignette"
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(0.8, 0.05, 0.05, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_vignette)


## A point stops warning once its boss falls; read live so a cleared cave goes quiet without a scene rebuild.
func is_point_cleared(i: int) -> bool:
	if i >= _clear_flags.size() or _clear_flags[i] == "":
		return false
	var gs: Node = get_node_or_null("/root/GameState") if is_inside_tree() else null
	return gs != null and gs.has_method("is_story_flag_set") and gs.is_story_flag_set(_clear_flags[i])


func nearest_live_distance(player_pos: Vector2) -> float:
	var min_dist: float = INF
	for i in _danger_points.size():
		if is_point_cleared(i):
			continue
		min_dist = minf(min_dist, player_pos.distance_to(_danger_points[i]))
	return min_dist


func process(delta: float) -> void:
	if not _player_ref or _danger_points.is_empty():
		return

	var min_dist: float = nearest_live_distance(_player_ref.global_position)

	# Calculate intensity (0 at DANGER_RADIUS, 1 at FULL_DANGER_RADIUS)
	var target_intensity = 0.0
	if min_dist < DANGER_RADIUS:
		target_intensity = clampf(1.0 - (min_dist - FULL_DANGER_RADIUS) / (DANGER_RADIUS - FULL_DANGER_RADIUS), 0.0, 1.0)

	_current_intensity = lerpf(_current_intensity, target_intensity, 4.0 * delta)

	if _current_intensity > 0.01:
		_pulse_timer += delta * PULSE_SPEED
		var pulse = (sin(_pulse_timer) * 0.5 + 0.5) * _current_intensity
		_vignette.color.a = pulse * 0.25  # Max 25% opacity
	else:
		_vignette.color.a = 0.0
		_pulse_timer = 0.0
