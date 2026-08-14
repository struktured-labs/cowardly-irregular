class_name BattleCameraRig
extends Node
## Battle camera juice: trauma-decay shake + pivoted micro punch-zoom. Single writer of camera offset/zoom while registered (EffectSystem delegates here), replacing the 30Hz random-step shake with a decaying noise model.

const MAX_OFFSET := 14.0
const TRAUMA_DECAY := 1.8
const NOISE_SPEED := 22.0
const DIR_BIAS := 0.6
## Phase-A ceiling: UI shares the sprite canvas (no CanvasLayer), so zoom must stay imperceptible on panels — raise only after the A2 CanvasLayer migration.
const ZOOM_CEILING := 1.04
const ROTATION_MAX := 0.0

var _cam: Camera2D = null
var _trauma := 0.0
var _sustain := 0.0
var _shake_dir := Vector2.ZERO
var _shake_offset := Vector2.ZERO
var _zoom_offset := Vector2.ZERO
var _zoom_tween: Tween = null
var _noise := FastNoiseLite.new()
var _noise_t := 0.0


func setup(camera: Camera2D) -> void:
	_cam = camera
	_noise.seed = 7
	_noise.frequency = 1.0


func add_trauma(amount: float, dir: Vector2 = Vector2.ZERO, sustain: float = 0.0) -> void:
	if GameState and "screen_shake_enabled" in GameState and not GameState.screen_shake_enabled:
		return
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
	_sustain = maxf(_sustain, sustain)
	if dir != Vector2.ZERO:
		_shake_dir = dir.normalized()


func punch_zoom(pivot: Vector2, strength: float = 0.03, duration: float = 0.14) -> void:
	if _cam == null:
		return
	# Never zoom out (would reveal canvas edges); clamp to the Phase-A ceiling
	var z := clampf(1.0 + strength, 1.0, ZOOM_CEILING)
	if z <= 1.0:
		return
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.tween_method(_apply_zoom.bind(pivot), 1.0, z, duration * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_method(_apply_zoom.bind(pivot), z, 1.0, duration * 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func crit_push(pivot: Vector2) -> void:
	punch_zoom(pivot, 0.04, 0.18)


func _apply_zoom(z: float, pivot: Vector2) -> void:
	if _cam == null:
		return
	_cam.zoom = Vector2.ONE * z
	# Zoom about screen point P under FIXED_TOP_LEFT: offset = P * (1 - 1/z)
	_zoom_offset = pivot * (1.0 - 1.0 / z)
	_compose()


func _process(delta: float) -> void:
	if _cam == null:
		return
	if _trauma > 0.0:
		if _sustain > 0.0:
			_sustain = maxf(_sustain - delta, 0.0)
		else:
			_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
		_noise_t += delta * NOISE_SPEED
		var shake := _trauma * _trauma
		var n := Vector2(_noise.get_noise_2d(_noise_t, 0.0), _noise.get_noise_2d(0.0, _noise_t))
		var iso := n * MAX_OFFSET * shake
		_shake_offset = iso if _shake_dir == Vector2.ZERO else iso.lerp(_shake_dir * n.x * MAX_OFFSET * shake, DIR_BIAS)
		if _trauma == 0.0:
			_shake_offset = Vector2.ZERO
			_shake_dir = Vector2.ZERO
	elif _shake_offset != Vector2.ZERO:
		_shake_offset = Vector2.ZERO
		_shake_dir = Vector2.ZERO
	_compose()


func _compose() -> void:
	_cam.offset = _zoom_offset + _shake_offset


func reset() -> void:
	_trauma = 0.0
	_sustain = 0.0
	_shake_dir = Vector2.ZERO
	_shake_offset = Vector2.ZERO
	_zoom_offset = Vector2.ZERO
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	if _cam:
		_cam.zoom = Vector2.ONE
		_cam.offset = Vector2.ZERO


func _exit_tree() -> void:
	reset()
	_cam = null
