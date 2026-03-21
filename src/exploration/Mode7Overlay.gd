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


func setup(scene: Node2D, player: Node2D) -> void:
	_player_ref = player
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

	var mat = ShaderMaterial.new()
	mat.shader = mode7_shader
	mat.set_shader_parameter("horizon", horizon)
	mat.set_shader_parameter("near_scale", near_scale)
	mat.set_shader_parameter("ground_y", ground_y)
	mat.set_shader_parameter("curvature", curvature)
	mat.set_shader_parameter("fog_color", fog_color)
	overlay.material = mat

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

	print("[MODE7] Screen-texture Mode 7 overlay active")


func process_frame() -> void:
	if not enabled or not _player_overlay_sprite or not _player_ref:
		return
	var src = _player_ref.get_node_or_null("Sprite")
	if not src or not src.texture:
		return
	_player_overlay_sprite.texture = src.texture
	var tex_h = src.texture.get_height()
	var s = player_display_size / max(float(tex_h), 1.0)
	_player_overlay_sprite.scale = Vector2(s, s)
	_player_overlay_sprite.flip_h = src.flip_h
	src.visible = false


func cleanup() -> void:
	if _mode7_layer:
		var overlay = _mode7_layer.get_node_or_null("Mode7Screen")
		if overlay:
			overlay.material = null
			overlay.visible = false


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
