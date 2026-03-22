extends Node
class_name Mode7Overlay

var enabled: bool = true
var player_display_size: float = 240.0
var player_screen_pos: Vector2 = Vector2(640, 540)

var horizon: float = 0.0
var near_scale: float = 0.12
var ground_y: float = 0.59
var curvature: float = 0.02
var fog_color: Color = Color(0.50, 0.60, 0.78, 1.0)

var _mode7_layer: CanvasLayer
var _player_overlay_layer: CanvasLayer
var _player_overlay_sprite: Sprite2D
var _player_ref: Node2D
var _shader_mat: ShaderMaterial

var _current_rotation: float = 0.0
const ROTATION_SPEED: float = 2.5
const SWAY_PIXELS: float = 24.0
const BOB_AMPLITUDE: float = 3.0
const BOB_SPEED: float = 10.0
var _bob_timer: float = 0.0
var _last_player_pos: Vector2 = Vector2.ZERO
var _player_moving: bool = false

static var camera_angle: float = 0.0


func setup(scene: Node2D, player: Node2D) -> void:
	_player_ref = player
	camera_angle = 0.0
	if not enabled:
		return

	var mode7_shader = load("res://src/shaders/mode7.gdshader")
	if not mode7_shader:
		push_warning("[MODE7] Failed to load mode7.gdshader")
		return

	_mode7_layer = CanvasLayer.new()
	_mode7_layer.name = "Mode7Overlay"
	_mode7_layer.layer = 1
	scene.add_child(_mode7_layer)

	var overlay = ColorRect.new()
	overlay.name = "Mode7Screen"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = mode7_shader
	_shader_mat.set_shader_parameter("horizon", horizon)
	_shader_mat.set_shader_parameter("near_scale", near_scale)
	_shader_mat.set_shader_parameter("ground_y", ground_y)
	_shader_mat.set_shader_parameter("curvature", curvature)
	_shader_mat.set_shader_parameter("fog_color", fog_color)
	_shader_mat.set_shader_parameter("world_rotation", 0.0)
	overlay.material = _shader_mat

	_mode7_layer.add_child(overlay)

	_player_overlay_layer = CanvasLayer.new()
	_player_overlay_layer.name = "PlayerOverlay"
	_player_overlay_layer.layer = 2
	scene.add_child(_player_overlay_layer)

	_player_overlay_sprite = Sprite2D.new()
	_player_overlay_sprite.name = "PlayerSprite"
	_player_overlay_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player_overlay_sprite.position = player_screen_pos
	_player_overlay_layer.add_child(_player_overlay_sprite)

	_last_player_pos = player.position
	print("[MODE7] Screen-texture Mode 7 overlay active (360° camera)")


func process_frame() -> void:
	if not enabled or not _player_overlay_sprite or not _player_ref:
		return

	var delta = _player_ref.get_process_delta_time()

	var src = _player_ref.get_node_or_null("Sprite")
	if not src or not src.texture:
		return
	_player_overlay_sprite.texture = src.texture
	var tex_h = src.texture.get_height()
	var s = player_display_size / max(float(tex_h), 1.0)
	_player_overlay_sprite.flip_h = src.flip_h
	src.visible = false

	var move_delta = _player_ref.position - _last_player_pos
	_player_moving = move_delta.length_squared() > 0.5
	_last_player_pos = _player_ref.position

	# Camera rotation: right stick (via GamepadFilter autoload) > Q/E > walking fallback
	var cam_input = GamepadFilter.right_stick_x
	if abs(cam_input) < 0.1:
		if Input.is_key_pressed(KEY_E):
			cam_input = 1.0
		elif Input.is_key_pressed(KEY_Q):
			cam_input = -1.0
	if abs(cam_input) < 0.1 and abs(move_delta.x) > 0.5:
		cam_input = -sign(move_delta.x) * 0.4

	if abs(cam_input) > 0.05:
		_current_rotation += cam_input * ROTATION_SPEED * delta

	camera_angle = _current_rotation

	var cam = _player_ref.get_node_or_null("Camera") as Camera2D
	if cam:
		cam.ignore_rotation = false
		cam.rotation = _current_rotation

	if _shader_mat:
		_shader_mat.set_shader_parameter("world_rotation", 0.0)

	# Sway
	var screen_move = move_delta.rotated(-_current_rotation)
	var sway_x = 0.0
	if abs(screen_move.x) > 0.5:
		sway_x = -sign(screen_move.x) * SWAY_PIXELS

	# Bob
	var bob_y = 0.0
	if _player_moving:
		_bob_timer += delta * BOB_SPEED
		bob_y = sin(_bob_timer) * BOB_AMPLITUDE
	else:
		_bob_timer = 0.0

	var sway_offset = Vector2(
		lerp(_player_overlay_sprite.position.x - player_screen_pos.x, sway_x, 6.0 * delta),
		bob_y
	)
	_player_overlay_sprite.position = player_screen_pos + sway_offset
	_player_overlay_sprite.scale = Vector2(s, s)


func cleanup() -> void:
	camera_angle = 0.0
	if _mode7_layer:
		var overlay = _mode7_layer.get_node_or_null("Mode7Screen")
		if overlay:
			overlay.material = null
			overlay.visible = false
	if _player_ref:
		var cam = _player_ref.get_node_or_null("Camera") as Camera2D
		if cam:
			cam.rotation = 0.0
			cam.ignore_rotation = true


static func apply_camera(cam: Camera2D, mode7: bool) -> void:
	if mode7:
		cam.zoom = Vector2(0.8, 0.8)
		cam.offset = Vector2(0, -50)
	else:
		cam.zoom = Vector2(2.0, 2.0)
		cam.offset = Vector2.ZERO


static func apply_camera_limits(cam: Camera2D, map_w: int, map_h: int, tile_size: int) -> void:
	cam.limit_left = -tile_size * 8
	cam.limit_top = -tile_size * 12
	cam.limit_right = map_w * tile_size + tile_size * 8
	cam.limit_bottom = map_h * tile_size + tile_size * 8
