extends Node
class_name Mode7Overlay

var enabled: bool = true
var player_display_size: float = 240.0
var player_screen_pos: Vector2 = Vector2(640, 540)

var horizon: float = 0.0
var near_scale: float = 0.22
var ground_y: float = 0.52
var curvature: float = 0.01
var fog_color: Color = Color(0.50, 0.60, 0.78, 1.0)
var sky_top: Color = Color(0.25, 0.35, 0.65, 1.0)
var sky_bottom: Color = Color(0.55, 0.65, 0.85, 1.0)
var scanline_intensity: float = 0.0
var dissolve_progress: float = 0.0

## Per-world Mode 7 visual presets — the shader evolution IS the narrative.
## W1 classic SNES → W5 wireframe/data → W6 shader dissolves entirely.
const WORLD_PRESETS: Dictionary = {
	"medieval": {
		"curvature": 0.01,
		"fog_color": Color(0.50, 0.60, 0.78),
		"sky_top": Color(0.25, 0.35, 0.65),
		"sky_bottom": Color(0.55, 0.65, 0.85),
	},
	"suburban": {
		"curvature": 0.005,  # Flatter — suburban grid regularity
		"fog_color": Color(0.72, 0.75, 0.80),  # Artificial-bright HOA haze
		"sky_top": Color(0.45, 0.55, 0.75),
		"sky_bottom": Color(0.70, 0.78, 0.90),
	},
	"steampunk": {
		"curvature": 0.02,  # More curved — gear-like horizon
		"fog_color": Color(0.60, 0.45, 0.25),  # Bronze/warm fog
		"sky_top": Color(0.35, 0.25, 0.15),  # Dark brass sky
		"sky_bottom": Color(0.55, 0.45, 0.30),
	},
	"industrial": {
		"curvature": 0.0,  # Zero curvature — brutalist flat
		"fog_color": Color(0.42, 0.40, 0.38),  # Gray-brown smog
		"sky_top": Color(0.28, 0.27, 0.26),  # Oppressive dark gray
		"sky_bottom": Color(0.38, 0.37, 0.36),
	},
	"digital": {
		"curvature": 0.005,
		"fog_color": Color(0.02, 0.40, 0.70),  # Neon blue
		"sky_top": Color(0.0, 0.05, 0.12),  # Near black
		"sky_bottom": Color(0.0, 0.15, 0.30),  # Dark blue
		"scanline_intensity": 0.3,  # CRT/terminal scanlines
	},
	# "abstract" intentionally omitted — W6 disables Mode 7 entirely
}

var _mode7_layer: CanvasLayer
var _player_overlay_layer: CanvasLayer
var _player_overlay_sprite: Sprite2D
var _player_ref: Node2D
var _shader_mat: ShaderMaterial

## Billboard system — render nearby world objects upright on the overlay layer
## instead of letting them get warped by the Mode 7 shader.
var _billboard_sources: Array = []
var _billboard_sprites: Dictionary = {}  # instance_id -> Sprite2D on overlay
const BILLBOARD_MAX_DIST: float = 400.0
const BILLBOARD_MIN_SCALE: float = 0.3
const BILLBOARD_BASE_SIZE: float = 96.0

var _current_rotation: float = 0.0
const ROTATION_SPEED: float = 2.5
const MAX_ROTATION: float = PI / 2.0  # ±90° = 180° total range (authentic SNES feel)
const SWAY_PIXELS: float = 16.0
const BOB_AMPLITUDE: float = 2.5
const BOB_SPEED: float = 10.0
var _bob_timer: float = 0.0
var _last_player_pos: Vector2 = Vector2.ZERO
var _player_moving: bool = false

static var camera_angle: float = 0.0


## Apply a per-world visual preset. Call BEFORE setup().
func apply_preset(world_id: String) -> void:
	if not WORLD_PRESETS.has(world_id):
		push_warning("[MODE7] No preset for world '%s', using defaults" % world_id)
		return
	var preset: Dictionary = WORLD_PRESETS[world_id]
	if preset.has("curvature"):
		curvature = preset["curvature"]
	if preset.has("fog_color"):
		fog_color = preset["fog_color"]
	if preset.has("sky_top"):
		sky_top = preset["sky_top"]
	if preset.has("sky_bottom"):
		sky_bottom = preset["sky_bottom"]
	if preset.has("horizon"):
		horizon = preset["horizon"]
	if preset.has("near_scale"):
		near_scale = preset["near_scale"]
	if preset.has("ground_y"):
		ground_y = preset["ground_y"]
	if preset.has("scanline_intensity"):
		scanline_intensity = preset["scanline_intensity"]
	if preset.has("dissolve_progress"):
		dissolve_progress = preset["dissolve_progress"]
	print("[MODE7] Applied '%s' world preset" % world_id)


func setup(scene: Node2D, player: Node2D) -> void:
	_player_ref = player
	camera_angle = 0.0
	var vp_rect = scene.get_viewport().get_visible_rect()
	var viewport_width = vp_rect.size.x if vp_rect.size.x > 0 else 1280.0
	var viewport_height = vp_rect.size.y if vp_rect.size.y > 0 else 1080.0
	player_screen_pos = Vector2(viewport_width / 2.0, viewport_height * 0.75)
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
	_shader_mat.set_shader_parameter("sky_top", sky_top)
	_shader_mat.set_shader_parameter("sky_bottom", sky_bottom)
	_shader_mat.set_shader_parameter("scanline_intensity", scanline_intensity)
	_shader_mat.set_shader_parameter("dissolve_progress", dissolve_progress)
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
	_player_overlay_sprite.z_index = 100  # Player always on top of billboards
	_player_overlay_layer.add_child(_player_overlay_sprite)

	_last_player_pos = player.position
	print("[MODE7] Screen-texture Mode 7 overlay active (360° camera)")


func process_frame() -> void:
	if not enabled or not _player_overlay_sprite or not _player_ref:
		return

	var delta = _player_ref.get_process_delta_time()

	var src = _player_ref.get_node_or_null("Sprite")
	if not src or not src.texture:
		# Ensure player stays visible if overlay can't take over
		if _player_overlay_sprite:
			_player_overlay_sprite.visible = false
		return
	_player_overlay_sprite.texture = src.texture
	_player_overlay_sprite.visible = true
	var tex_h = src.texture.get_height()
	var s = player_display_size / max(float(tex_h), 1.0)
	_player_overlay_sprite.flip_h = src.flip_h
	src.visible = false

	var move_delta = _player_ref.position - _last_player_pos
	_player_moving = move_delta.length_squared() > 0.5
	_last_player_pos = _player_ref.position

	# Camera rotation: right stick only (no movement-based auto-turn)
	var cam_input = GamepadFilter.right_stick_x
	if abs(cam_input) < 0.2:
		# Keyboard fallback for camera rotation
		if Input.is_key_pressed(KEY_E):
			cam_input = 1.0
		elif Input.is_key_pressed(KEY_Q):
			cam_input = -1.0

	if abs(cam_input) > 0.2:
		_current_rotation += cam_input * ROTATION_SPEED * delta
		_current_rotation = clampf(_current_rotation, -MAX_ROTATION, MAX_ROTATION)

	camera_angle = _current_rotation

	# Drive rotation via Camera2D instead of shader UV rotation.
	# This fixes texture sampling degradation past ~180 degrees —
	# the screen texture now contains the correctly rotated world view,
	# so the shader only needs to apply the perspective warp.
	var cam = _player_ref.get_node_or_null("Camera") as Camera2D
	if cam:
		cam.ignore_rotation = false
		cam.rotation = _current_rotation

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

	_update_billboards()


func register_billboard(obj: Node2D) -> void:
	if obj not in _billboard_sources:
		_billboard_sources.append(obj)


## Set dissolve progress at runtime (for W5→W6 transition animation).
## Call from a tween or _process loop: 0.0 = normal, 1.0 = fully dissolved.
func set_dissolve(progress: float) -> void:
	dissolve_progress = clampf(progress, 0.0, 1.0)
	if _shader_mat:
		_shader_mat.set_shader_parameter("dissolve_progress", dissolve_progress)


func unregister_billboard(obj: Node2D) -> void:
	_billboard_sources.erase(obj)
	var obj_id = obj.get_instance_id()
	if _billboard_sprites.has(obj_id):
		_billboard_sprites[obj_id].queue_free()
		_billboard_sprites.erase(obj_id)


func _update_billboards() -> void:
	if not _player_ref or not _player_overlay_layer:
		return

	var player_pos = _player_ref.global_position
	var active_ids: Dictionary = {}

	# Collect visible billboards sorted far-to-near for z-ordering
	var entries: Array = []
	for obj in _billboard_sources:
		if not is_instance_valid(obj) or not obj.visible:
			continue
		var offset = obj.global_position - player_pos
		var dist = offset.length()
		if dist < 8.0 or dist > BILLBOARD_MAX_DIST:
			continue
		# Rotate offset to camera-relative screen space
		var screen_offset = offset.rotated(-_current_rotation)
		# Only show objects in front of player (negative Y = forward in top-down)
		if screen_offset.y > 0:
			continue
		entries.append({"obj": obj, "dist": dist, "sx": screen_offset.x, "sy": screen_offset.y})

	entries.sort_custom(func(a, b): return a["dist"] > b["dist"])

	for i in range(entries.size()):
		var e = entries[i]
		var obj: Node2D = e["obj"]
		var dist: float = e["dist"]
		var obj_id = obj.get_instance_id()
		active_ids[obj_id] = true

		# Perspective scaling
		var t = clampf(dist / BILLBOARD_MAX_DIST, 0.0, 1.0)
		var perspective = lerpf(1.0, BILLBOARD_MIN_SCALE, t)

		# Screen position: lateral offset compressed by perspective,
		# Y offset maps forward distance to horizon approach
		var scr_x = player_screen_pos.x + e["sx"] * perspective * 0.5
		var scr_y = player_screen_pos.y + e["sy"] * perspective * 0.3

		# Get or create billboard sprite
		var bb: Sprite2D
		if _billboard_sprites.has(obj_id):
			bb = _billboard_sprites[obj_id]
		else:
			bb = Sprite2D.new()
			bb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_player_overlay_layer.add_child(bb)
			_billboard_sprites[obj_id] = bb

		# Copy texture from source
		var src_sprite = obj.get_node_or_null("Sprite") as Sprite2D
		if src_sprite and src_sprite.texture:
			bb.texture = src_sprite.texture
			bb.region_enabled = src_sprite.region_enabled
			if src_sprite.region_enabled:
				bb.region_rect = src_sprite.region_rect
			bb.flip_h = src_sprite.flip_h
			src_sprite.visible = false

		bb.position = Vector2(scr_x, scr_y)
		var tex_h = float(bb.texture.get_height()) if bb.texture else 32.0
		var s = BILLBOARD_BASE_SIZE / max(tex_h, 1.0) * perspective
		bb.scale = Vector2(s, s)
		bb.z_index = i  # Far objects first (low z), near objects last (high z)
		bb.visible = true

	# Hide billboards no longer in range
	for obj_id in _billboard_sprites:
		if not active_ids.has(obj_id):
			_billboard_sprites[obj_id].visible = false


func cleanup() -> void:
	camera_angle = 0.0
	_current_rotation = 0.0
	# Free billboard sprites
	for obj_id in _billboard_sprites:
		if is_instance_valid(_billboard_sprites[obj_id]):
			_billboard_sprites[obj_id].queue_free()
	_billboard_sprites.clear()
	_billboard_sources.clear()
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
		cam.zoom = Vector2(0.65, 0.65)
		cam.offset = Vector2(0, -30)
	else:
		cam.zoom = Vector2(2.0, 2.0)
		cam.offset = Vector2.ZERO


static func apply_camera_limits(cam: Camera2D, map_w: int, map_h: int, tile_size: int) -> void:
	cam.limit_left = -tile_size * 8
	cam.limit_top = -tile_size * 12
	cam.limit_right = map_w * tile_size + tile_size * 8
	cam.limit_bottom = map_h * tile_size + tile_size * 8
