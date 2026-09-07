extends Node
class_name DangerZone

## DangerZone — pulsing red vignette + danger music near boss areas.
## Intensity scales with proximity to danger points.

const DANGER_RADIUS: float = 256.0  # Pixels — start showing warning
const FULL_DANGER_RADIUS: float = 96.0  # Full intensity at this distance
const PULSE_SPEED: float = 3.0

var _canvas: CanvasLayer
var _vignette: ColorRect
var _danger_points: Array[Vector2] = []
var _player_ref: Node2D
var _pulse_timer: float = 0.0
var _current_intensity: float = 0.0
var _danger_music_playing: bool = false


func setup(parent: Node, player: Node2D, points: Array[Vector2]) -> void:
	_player_ref = player
	_danger_points = points

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


func process(delta: float) -> void:
	if not _player_ref or _danger_points.is_empty():
		return

	# Find closest danger point
	var player_pos = _player_ref.global_position
	var min_dist = DANGER_RADIUS + 1.0
	for pt in _danger_points:
		var d = player_pos.distance_to(pt)
		if d < min_dist:
			min_dist = d

	# Calculate intensity (0 at DANGER_RADIUS, 1 at FULL_DANGER_RADIUS)
	var target_intensity = 0.0
	if min_dist < DANGER_RADIUS:
		target_intensity = clampf(1.0 - (min_dist - FULL_DANGER_RADIUS) / (DANGER_RADIUS - FULL_DANGER_RADIUS), 0.0, 1.0)

	_current_intensity = lerpf(_current_intensity, target_intensity, 4.0 * delta)

	if _current_intensity > 0.01:
		_pulse_timer += delta * PULSE_SPEED
		var pulse = (sin(_pulse_timer) * 0.5 + 0.5) * _current_intensity
		_vignette.color.a = pulse * 0.25  # Max 25% opacity

		# Trigger danger music
		if not _danger_music_playing and _current_intensity > 0.3:
			if SoundManager and SoundManager.has_method("play_area_music"):
				SoundManager.play_area_music("danger")
			_danger_music_playing = true
	else:
		_vignette.color.a = 0.0
		_pulse_timer = 0.0

		# Return to normal music
		if _danger_music_playing:
			if SoundManager and SoundManager.has_method("play_area_music"):
				SoundManager.play_area_music("overworld")
			_danger_music_playing = false
