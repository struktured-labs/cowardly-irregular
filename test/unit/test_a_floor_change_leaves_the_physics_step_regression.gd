extends GutTest

## Regression: a dungeon floor change rebuilt the next floor from INSIDE the stair's `body_entered`,
## i.e. inside the physics step. Every chest, signpost, hidden passage, save crystal and boss trigger
## the rebuild adds is an Area2D, and the engine refuses their setup there. struktured's play log of
## 2026-09-26 carried 12-25 lines per floor change, 243 in one session (Glacial Sanctum floors 2-4):
##   ERROR: Can't change this state while flushing queries. (area_set_shape_disabled)
##   ERROR: Function blocked during in/out signal. Use set_deferred("monitorable", ...)
## `028435b23` deferred the flags on the STAIR areas only; every other area in the rebuild still hit it.
##
## The engine error cannot be observed from GDScript, so each arm records its precondition: whether
## any Area2D of the cave entered the tree while `Engine.is_in_physics_frame()` was true.

const WHISPERING := preload("res://src/maps/dungeons/WhisperingCave.gd")
const FIRE_CAVE := preload("res://src/maps/dungeons/FireDragonCave.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const _DIRECTIONS := ["ui_up", "ui_down", "ui_left", "ui_right"]
const _FLOOR_KEYS := ["whispering_cave_floor", "fire_dragon_cave_floor"]

var _viewport: SubViewport
var _held: Dictionary = {}
var _cave: Node = null
var _added_in_step: Array[String] = []
var _added_total: int = 0


func before_each() -> void:
	for a in _DIRECTIONS:
		Input.action_release(a)
	_viewport = SubViewport.new()
	_viewport.world_2d = World2D.new()
	_viewport.size = Vector2i(640, 360)
	add_child(_viewport)
	_held = {}
	for key in _FLOOR_KEYS:
		if GameState and GameState.game_constants.has(key):
			_held[key] = GameState.game_constants[key]
			GameState.game_constants.erase(key)
	_added_in_step = []
	_added_total = 0
	get_tree().node_added.connect(_on_node_added)


func after_each() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if GameState:
		for key in _FLOOR_KEYS:
			GameState.game_constants.erase(key)
			if _held.has(key):
				GameState.game_constants[key] = _held[key]
	if _viewport and is_instance_valid(_viewport):
		_viewport.queue_free()
	_cave = null
	for a in _DIRECTIONS:
		Input.action_release(a)


func after_all() -> void:
	SoundState.restore()


func _on_node_added(n: Node) -> void:
	if _cave == null or not (n is Area2D) or not _cave.is_ancestor_of(n):
		return
	_added_total += 1
	if Engine.is_in_physics_frame():
		_added_in_step.append(str(n.name))


func _settle(cave: Node) -> void:
	_viewport.add_child(cave)
	for _i in 8:
		await get_tree().process_frame
	_cave = cave


func _wait_for_floor(cave: Node, start: int) -> bool:
	for _i in 120:
		await get_tree().process_frame
		if int(cave.current_floor) != start:
			return true
	return false


func _walk_onto_the_up_stairs(cave: Node) -> void:
	await _settle(cave)
	assert_true(cave.spawn_points.has("stairs_up"), "CONTROL: floor 1 has an up staircase")
	var start: int = int(cave.current_floor)
	_added_total = 0
	cave.player.teleport(cave.spawn_points["stairs_up"])
	var changed: bool = await _wait_for_floor(cave, start)
	assert_true(changed, "CONTROL: standing on the stairs changed the floor through real physics")
	assert_gt(_added_total, 0, "CONTROL: the new floor added areas, so there was something to judge")
	assert_eq(_added_in_step, [] as Array[String],
		"these areas entered the tree inside the physics step — the engine refuses their setup there")
	# The transition awaits 0.8s of timers; let it finish before the cave is freed.
	await get_tree().create_timer(1.0).timeout


func test_dragon_cave_stairs_rebuild_outside_the_physics_step() -> void:
	await _walk_onto_the_up_stairs(FIRE_CAVE.new())


func test_whispering_cave_stairs_rebuild_outside_the_physics_step() -> void:
	await _walk_onto_the_up_stairs(WHISPERING.new())


func test_a_portal_warp_rebuilds_outside_the_physics_step() -> void:
	# Portals and trap plates call puzzle_warp_to from their own body_entered.
	var cave = FIRE_CAVE.new()
	await _settle(cave)
	_added_total = 0
	await get_tree().physics_frame
	assert_true(Engine.is_in_physics_frame(), "CONTROL: this call runs inside the physics step, like a portal's")
	cave.puzzle_warp_to(2, cave.player.global_position)
	var changed: bool = await _wait_for_floor(cave, 1) if int(cave.current_floor) == 1 else true
	assert_true(changed, "CONTROL: the warp reached floor 2")
	assert_gt(_added_total, 0, "CONTROL: the warped-to floor added areas")
	assert_eq(_added_in_step, [] as Array[String],
		"these areas entered the tree inside the physics step — the engine refuses their setup there")
	await get_tree().create_timer(1.0).timeout
