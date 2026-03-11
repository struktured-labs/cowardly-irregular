extends Node
class_name MonsterSpawner

## MonsterSpawner - Manages visible roaming monsters on the overworld
## Spawns monsters from the zone pool and keeps them within screen + buffer range

const RoamingMonsterScript = preload("res://src/exploration/RoamingMonster.gd")

signal monster_touched(monster_id: String, monster_types: Array)

const TILE_SIZE: int = 32
const SPAWN_COUNT_MIN: int = 3
const SPAWN_COUNT_MAX: int = 5
const MIN_SPAWN_DIST_FROM_PLAYER: float = 128.0
const MIN_MONSTER_SEPARATION: float = 64.0
const DESPAWN_DISTANCE: float = 640.0
const SPAWN_BUFFER: float = 480.0
const CHECK_INTERVAL: float = 3.0
const MAP_WIDTH: int = 100
const MAP_HEIGHT: int = 70

## Safe zones (tile rect) where no monsters spawn. Format: Rect2(tile_x, tile_y, w, h)
const SAFE_ZONE_RECTS: Array = [
	# Harmonia village area — rows 21-29, cols 0-10 approx
	[0, 21, 12, 10],
	# Village gate tile region
	[20, 22, 16, 10],
]

var _player: Node2D = null
var _monsters: Array = []
var _enemy_pool: Array = ["slime", "bat", "goblin"]
var _spawn_parent: Node2D = null
var _check_timer: float = 0.0
var _enabled: bool = true


func _ready() -> void:
	_spawn_parent = Node2D.new()
	_spawn_parent.name = "RoamingMonsters"
	get_parent().add_child(_spawn_parent)


func _process(delta: float) -> void:
	if not _enabled or not _player or not is_instance_valid(_player):
		return

	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = CHECK_INTERVAL
		_cull_far_monsters()
		_fill_monsters()


func setup(player: Node2D, enemy_pool: Array) -> void:
	_player = player
	_enemy_pool = enemy_pool if not enemy_pool.is_empty() else ["slime", "bat", "goblin"]
	_fill_monsters()


func set_enemy_pool(pool: Array) -> void:
	_enemy_pool = pool if not pool.is_empty() else ["slime", "bat", "goblin"]


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_despawn_all()


func _fill_monsters() -> void:
	var target = randi_range(SPAWN_COUNT_MIN, SPAWN_COUNT_MAX)
	var alive = _monsters.filter(func(m): return is_instance_valid(m))
	_monsters = alive
	var needed = target - _monsters.size()
	for _i in range(needed):
		_try_spawn_monster()


func _try_spawn_monster() -> void:
	if not _player or not is_instance_valid(_player):
		return

	var candidate = _find_spawn_position()
	if candidate == Vector2.ZERO:
		return

	var pool = _get_valid_pool_for_overworld()
	if pool.is_empty():
		return

	var mid = pool[randi() % pool.size()]
	var monster = RoamingMonsterScript.new()
	monster.monster_id = mid
	monster.monster_types = [mid]
	monster.global_position = candidate
	monster.set_player_ref(_player)
	monster.touched.connect(_on_monster_touched)
	_spawn_parent.add_child(monster)
	_monsters.append(monster)


func _find_spawn_position() -> Vector2:
	var player_pos = _player.global_position
	var map_px_w = MAP_WIDTH * TILE_SIZE
	var map_px_h = MAP_HEIGHT * TILE_SIZE

	for _attempt in range(20):
		var angle = randf() * TAU
		var radius = randf_range(MIN_SPAWN_DIST_FROM_PLAYER + 32.0, SPAWN_BUFFER)
		var candidate = player_pos + Vector2(cos(angle), sin(angle)) * radius
		candidate.x = clampf(candidate.x, TILE_SIZE, map_px_w - TILE_SIZE)
		candidate.y = clampf(candidate.y, TILE_SIZE, map_px_h - TILE_SIZE)

		if _in_safe_zone(candidate):
			continue
		if _too_close_to_others(candidate):
			continue
		return candidate

	return Vector2.ZERO


func _in_safe_zone(pos: Vector2) -> bool:
	var tx = int(pos.x / TILE_SIZE)
	var ty = int(pos.y / TILE_SIZE)
	for rect_arr in SAFE_ZONE_RECTS:
		var rx: int = rect_arr[0]
		var ry: int = rect_arr[1]
		var rw: int = rect_arr[2]
		var rh: int = rect_arr[3]
		if tx >= rx and tx < rx + rw and ty >= ry and ty < ry + rh:
			return true
	return false


func _too_close_to_others(pos: Vector2) -> bool:
	for m in _monsters:
		if not is_instance_valid(m):
			continue
		if m.global_position.distance_to(pos) < MIN_MONSTER_SEPARATION:
			return true
	return false


func _cull_far_monsters() -> void:
	if not _player or not is_instance_valid(_player):
		return
	var player_pos = _player.global_position
	var alive: Array = []
	for m in _monsters:
		if not is_instance_valid(m):
			continue
		if m.global_position.distance_to(player_pos) > DESPAWN_DISTANCE:
			m.queue_free()
		else:
			alive.append(m)
	_monsters = alive


func _despawn_all() -> void:
	for m in _monsters:
		if is_instance_valid(m):
			m.queue_free()
	_monsters.clear()


func _get_valid_pool_for_overworld() -> Array:
	var overworld_sprites = ["slime", "bat", "goblin", "wolf", "spider",
		"skeleton", "ghost", "imp", "troll", "snake"]
	var valid: Array = []
	for entry in _enemy_pool:
		if entry in overworld_sprites:
			valid.append(entry)
	if valid.is_empty():
		valid = overworld_sprites.filter(func(e): return e in _enemy_pool)
	if valid.is_empty():
		valid = ["slime"]
	return valid


func _on_monster_touched(monster_id: String, monster_types: Array) -> void:
	monster_touched.emit(monster_id, monster_types)
