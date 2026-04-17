extends Area2D
class_name RoamingMonster

## RoamingMonster - Visible wandering enemy on the overworld
## Sprite sheet: 128x128, 4 rows x 4 cols, 32x32 per frame
## Row 0=walk_down, 1=walk_left, 2=walk_right, 3=walk_up

signal touched(monster_id: String, monster_types: Array)

const FRAME_W: int = 32
const FRAME_H: int = 32
const SHEET_COLS: int = 4
const WANDER_SPEED: float = 90.0
const CHASE_SPEED: float = 115.0
const CHASE_RADIUS: float = 96.0
const WANDER_RADIUS: float = 160.0
const RESPAWN_TIME_MIN: float = 30.0
const RESPAWN_TIME_MAX: float = 60.0
const ANIM_FPS: float = 6.0

@export var monster_id: String = "slime"
@export var monster_types: Array = []

var _spawn_origin: Vector2 = Vector2.ZERO
var _active: bool = true
var _player_ref: Node2D = null

var _sprite: Sprite2D
var _sheet: Texture2D
var _sheet_loaded: bool = false

var _dir: Vector2 = Vector2.ZERO
var _state: int = 0  # 0=wander, 1=pause, 2=chase
var _state_timer: float = 0.0
var _anim_timer: float = 0.0
var _anim_frame: int = 0
var _row: int = 0  # sprite sheet row

var _respawn_timer: float = 0.0
var _fading: bool = false
var _fade_timer: float = 0.0
const FADE_DURATION: float = 0.5

var _collision: CollisionShape2D


func _ready() -> void:
	_spawn_origin = global_position
	if monster_types.is_empty():
		monster_types = [monster_id]

	_setup_sprite()
	_setup_collision()
	body_entered.connect(_on_body_entered)

	# Start with a short random offset so monsters don't all move in sync
	_state_timer = randf_range(0.0, 2.0)
	_pick_wander_dir()


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.centered = true
	add_child(_sprite)

	var path = "res://assets/sprites/monsters/overworld/%s.png" % monster_id
	if ResourceLoader.exists(path):
		_sheet = load(path)
		_sheet_loaded = true
		_sprite.texture = _sheet
		_sprite.region_enabled = true
		_apply_frame(0, 0)
	else:
		_draw_fallback_sprite()


func _draw_fallback_sprite() -> void:
	var img = Image.create(FRAME_W, FRAME_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.2, 0.2, 0.9))
	for x in range(FRAME_W):
		img.set_pixel(x, 0, Color.BLACK)
		img.set_pixel(x, FRAME_H - 1, Color.BLACK)
	for y in range(FRAME_H):
		img.set_pixel(0, y, Color.BLACK)
		img.set_pixel(FRAME_W - 1, y, Color.BLACK)
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.region_enabled = false


func _apply_frame(row: int, col: int) -> void:
	if not _sheet_loaded:
		return
	_sprite.region_rect = Rect2(col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)


func _setup_collision() -> void:
	_collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 112.0  # Compensates for Mode 7 perspective foreshortening
	_collision.shape = shape
	add_child(_collision)

	collision_layer = 8
	collision_mask = 2
	monitoring = true
	monitorable = true


func _process(delta: float) -> void:
	if not _active:
		_tick_respawn(delta)
		return

	if _fading:
		_tick_fade(delta)
		return

	_tick_anim(delta)
	_tick_state(delta)
	_move(delta)


func _tick_anim(delta: float) -> void:
	_anim_timer += delta
	if _anim_timer >= 1.0 / ANIM_FPS:
		_anim_timer -= 1.0 / ANIM_FPS
		if _dir != Vector2.ZERO or _state == 2:
			_anim_frame = (_anim_frame + 1) % SHEET_COLS
		else:
			_anim_frame = 0
		_apply_frame(_row, _anim_frame)


func _tick_state(delta: float) -> void:
	if _player_ref and is_instance_valid(_player_ref):
		var dist = global_position.distance_to(_player_ref.global_position)
		if dist <= CHASE_RADIUS and _state != 2:
			_state = 2
			_state_timer = 0.0
			return

	if _state == 2:
		if not _player_ref or not is_instance_valid(_player_ref):
			_state = 0
			_pick_wander_dir()
			return
		var dist = global_position.distance_to(_player_ref.global_position)
		if dist > CHASE_RADIUS * 1.5:
			_state = 0
			_pick_wander_dir()
		return

	_state_timer -= delta
	if _state_timer <= 0.0:
		if _state == 0:
			_state = 1
			_state_timer = randf_range(1.0, 3.0)
			_dir = Vector2.ZERO
		else:
			_state = 0
			_pick_wander_dir()


func _pick_wander_dir() -> void:
	var dirs = [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]
	_dir = dirs[randi() % dirs.size()]
	_state_timer = randf_range(0.8, 2.0)
	_update_row_from_dir()


func _update_row_from_dir() -> void:
	if _dir == Vector2.DOWN:
		_row = 0
	elif _dir == Vector2.LEFT:
		_row = 1
	elif _dir == Vector2.RIGHT:
		_row = 2
	elif _dir == Vector2.UP:
		_row = 3


func _move(delta: float) -> void:
	if _state == 1:
		return

	var move_dir: Vector2
	var speed: float

	if _state == 2 and _player_ref and is_instance_valid(_player_ref):
		move_dir = ((_player_ref.global_position - global_position).normalized())
		speed = CHASE_SPEED
		_update_row_from_move_dir(move_dir)
	else:
		move_dir = _dir
		speed = WANDER_SPEED

	if move_dir == Vector2.ZERO:
		return

	var next_pos = global_position + move_dir * speed * delta
	var dist_from_spawn = next_pos.distance_to(_spawn_origin)
	if dist_from_spawn > WANDER_RADIUS:
		_dir = (_spawn_origin - global_position).normalized().round()
		if _dir == Vector2.ZERO:
			_dir = Vector2.DOWN
		_update_row_from_dir()
		return

	global_position = next_pos


func _update_row_from_move_dir(move_dir: Vector2) -> void:
	if abs(move_dir.x) > abs(move_dir.y):
		_row = 2 if move_dir.x > 0 else 1
	else:
		_row = 0 if move_dir.y > 0 else 3


func _tick_fade(delta: float) -> void:
	_fade_timer += delta
	var t = clampf(_fade_timer / FADE_DURATION, 0.0, 1.0)
	_sprite.modulate.a = 1.0 - t
	if _fade_timer >= FADE_DURATION:
		_active = false
		_fading = false
		_sprite.visible = false
		_collision.disabled = true
		_respawn_timer = randf_range(RESPAWN_TIME_MIN, RESPAWN_TIME_MAX)


func _tick_respawn(delta: float) -> void:
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn()


func _respawn() -> void:
	global_position = _spawn_origin
	_active = true
	_fading = false
	_fade_timer = 0.0
	_sprite.visible = true
	_sprite.modulate.a = 1.0
	_collision.disabled = false
	_state = 0
	_pick_wander_dir()


func _on_body_entered(body: Node2D) -> void:
	if not _active or _fading:
		return
	if body.has_method("set_can_move"):
		_begin_fade()
		touched.emit(monster_id, monster_types)


func _begin_fade() -> void:
	_fading = true
	_fade_timer = 0.0


func set_player_ref(player: Node2D) -> void:
	_player_ref = player
