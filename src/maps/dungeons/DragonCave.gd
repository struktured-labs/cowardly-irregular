extends Node2D
class_name DragonCave

## DragonCave - Base class for dragon cave dungeons
## Smaller maps (20x16), 2-3 floors, configurable via subclass overrides

const TileGeneratorScript = preload("res://src/exploration/TileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)
signal floor_changed(new_floor: int)

## Map dimensions (in tiles) - smaller than WhisperingCave
const MAP_WIDTH: int = 20
const MAP_HEIGHT: int = 16
const TILE_SIZE: int = 32

## Subclass MUST override these
var cave_name: String = "Dragon Cave"
var cave_id: String = "dragon_cave"
var boss_id: String = "dragon"
var boss_flag_key: String = "dragon_defeated"
var total_floors: int = 3
var overworld_exit_spawn: String = "cave_entrance"

## Override in subclass: floor number -> Array of ASCII rows (20 chars × 16 rows)
var floor_layouts: Dictionary = {}

## Override in subclass: floor number -> {"entrance": Vector2} or {"down_stairs": Vector2}
var floor_spawn_points: Dictionary = {}

## Override in subclass: floor number -> Array of enemy type strings
var floor_encounter_pools: Dictionary = {}

## Floor state
var current_floor: int = 1
var boss_defeated: bool = false
var _transitioning: bool = false

## Scene components
var tile_map: TileMapLayer
var player: Node2D
var camera: Camera2D
var controller: Node
var tile_generator: Node

## Area transitions
var transitions: Node2D

## Stair sprites
var stair_sprites: Node2D

## Spawn points (pixel coordinates, populated during map generation)
var spawn_points: Dictionary = {}


func _ready() -> void:
	_setup_scene()
	_load_boss_state()
	_generate_map_for_floor(current_floor)
	_setup_player()
	_setup_camera()
	_setup_controller()

	if SoundManager:
		SoundManager.play_area_music("cave")

	exploration_ready.emit()


func _setup_scene() -> void:
	tile_generator = TileGeneratorScript.new()
	add_child(tile_generator)

	tile_map = TileMapLayer.new()
	tile_map.name = "TileMap"
	tile_map.tile_set = tile_generator.create_tileset()
	add_child(tile_map)

	transitions = Node2D.new()
	transitions.name = "Transitions"
	add_child(transitions)

	stair_sprites = Node2D.new()
	stair_sprites.name = "StairSprites"
	add_child(stair_sprites)


func _generate_map_for_floor(floor_num: int) -> void:
	spawn_points.clear()

	var map_data = floor_layouts.get(floor_num, floor_layouts.get(1, []))
	if map_data.is_empty():
		push_warning("[%s] No layout for floor %d" % [cave_name, floor_num])
		return

	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "M"
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			if char == "U":
				spawn_points["stairs_up"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)
			elif char == "D":
				spawn_points["stairs_down"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)
			elif char == "T":
				var key = "treasure_%d" % spawn_points.size()
				spawn_points[key] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)
			elif char == "B":
				spawn_points["boss"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)

	var spawn_pos = floor_spawn_points.get(floor_num, {}).get("entrance", Vector2(10, 12))
	spawn_points["default"] = Vector2(spawn_pos.x * TILE_SIZE, spawn_pos.y * TILE_SIZE)

	_setup_transitions_for_floor(floor_num)
	_add_stair_visuals()


func _char_to_tile_type(char: String) -> int:
	match char:
		"M": return TileGeneratorScript.TileType.CAVE_WALL
		".", "T", "B", "U", "D", "X":
			return TileGeneratorScript.TileType.CAVE_FLOOR
		_: return TileGeneratorScript.TileType.CAVE_FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions_for_floor(floor_num: int) -> void:
	for child in transitions.get_children():
		child.queue_free()

	# Stairs up (to next floor)
	if spawn_points.has("stairs_up"):
		var up_trans = AreaTransitionScript.new()
		up_trans.name = "StairsUp"
		up_trans.require_interaction = false
		up_trans.position = spawn_points["stairs_up"]
		_setup_transition_collision(up_trans, Vector2(TILE_SIZE, TILE_SIZE))
		up_trans.body_entered.connect(_on_stairs_up_entered)
		transitions.add_child(up_trans)

	# Stairs down / exit
	if spawn_points.has("stairs_down"):
		var down_trans = AreaTransitionScript.new()
		down_trans.name = "StairsDown"
		down_trans.require_interaction = false
		down_trans.position = spawn_points["stairs_down"]
		_setup_transition_collision(down_trans, Vector2(TILE_SIZE * 2, TILE_SIZE * 2))

		if floor_num == 1:
			down_trans.target_map = "overworld"
			down_trans.target_spawn = overworld_exit_spawn
			down_trans.transition_triggered.connect(_on_transition_triggered)
		else:
			down_trans.body_entered.connect(_on_stairs_down_entered)

		transitions.add_child(down_trans)

	# Boss trigger on final floor
	if floor_num == total_floors:
		if spawn_points.has("boss") and not boss_defeated:
			var BossTriggerScript = load("res://src/maps/dungeons/BossTrigger.gd")
			var boss_area = BossTriggerScript.new()
			boss_area.name = "BossTrigger"
			boss_area.position = spawn_points["boss"]
			boss_area.cave_ref = self
			_setup_transition_collision(boss_area, Vector2(TILE_SIZE * 2, TILE_SIZE * 2))
			transitions.add_child(boss_area)
			DebugLogOverlay.log("[%s] Boss trigger at %s" % [cave_name, boss_area.position])


func _add_stair_visuals() -> void:
	for child in stair_sprites.get_children():
		child.queue_free()

	if spawn_points.has("stairs_up"):
		stair_sprites.add_child(_create_stair_marker(spawn_points["stairs_up"], true))

	if spawn_points.has("stairs_down"):
		stair_sprites.add_child(_create_stair_marker(spawn_points["stairs_down"], false))

	if current_floor == total_floors and spawn_points.has("boss") and not boss_defeated:
		stair_sprites.add_child(_create_boss_marker(spawn_points["boss"]))


func _create_stair_marker(pos: Vector2, is_up: bool) -> Node2D:
	var marker = Node2D.new()
	marker.position = pos

	var bg = ColorRect.new()
	bg.size = Vector2(TILE_SIZE, TILE_SIZE)
	bg.position = Vector2(-TILE_SIZE / 2, -TILE_SIZE / 2)
	bg.color = Color(0.3, 0.4, 0.5, 0.7) if is_up else Color(0.5, 0.4, 0.3, 0.7)
	marker.add_child(bg)

	var label = Label.new()
	label.text = "▲" if is_up else "▼"
	label.position = Vector2(-8, -12)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color.WHITE)
	marker.add_child(label)

	marker.ready.connect(func():
		var tween = marker.create_tween()
		tween.set_loops()
		tween.tween_property(label, "modulate:a", 0.5, 0.8)
		tween.tween_property(label, "modulate:a", 1.0, 0.8)
	)

	return marker


func _create_boss_marker(pos: Vector2) -> Node2D:
	var marker = Node2D.new()
	marker.position = pos

	var bg = ColorRect.new()
	bg.size = Vector2(TILE_SIZE, TILE_SIZE)
	bg.position = Vector2(-TILE_SIZE / 2, -TILE_SIZE / 2)
	bg.color = Color(0.8, 0.2, 0.2, 0.8)
	marker.add_child(bg)

	var label = Label.new()
	label.text = "B"
	label.position = Vector2(-8, -12)
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color.YELLOW)
	marker.add_child(label)

	marker.ready.connect(func():
		var tween = marker.create_tween()
		tween.set_loops()
		tween.tween_property(bg, "modulate:a", 0.6, 0.5)
		tween.tween_property(bg, "modulate:a", 1.0, 0.5)
	)

	return marker


func _setup_transition_collision(trans: Area2D, size: Vector2) -> void:
	trans.collision_layer = 4
	trans.collision_mask = 2
	trans.monitoring = true
	trans.monitorable = true

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	trans.add_child(collision)


func _on_stairs_up_entered(body: Node2D) -> void:
	if body.has_method("set_can_move") and not _transitioning:
		_transition_to_floor(current_floor + 1, "up")


func _on_stairs_down_entered(body: Node2D) -> void:
	if body.has_method("set_can_move") and not _transitioning:
		_transition_to_floor(current_floor - 1, "down")


func _transition_to_floor(target_floor: int, direction: String = "") -> void:
	if target_floor < 1 or target_floor > total_floors:
		return

	_transitioning = true

	if player and player.has_method("set_can_move"):
		player.set_can_move(false)

	controller.pause_exploration()

	current_floor = target_floor

	tile_map.clear()
	_generate_map_for_floor(current_floor)

	_update_floor_encounters(current_floor)

	var spawn_key = "default"
	if direction == "up":
		spawn_key = "stairs_down"
	elif direction == "down":
		if target_floor == 1:
			spawn_key = "entrance"
		else:
			spawn_key = "stairs_up"

	if spawn_points.has(spawn_key):
		player.teleport(spawn_points[spawn_key])
	else:
		player.teleport(spawn_points.get("default", Vector2(320, 384)))

	player.reset_step_count()

	await get_tree().create_timer(0.3).timeout
	if player and player.has_method("set_can_move"):
		player.set_can_move(true)

	controller.resume_exploration()
	floor_changed.emit(current_floor)

	DebugLogOverlay.log("[%s] Floor %d" % [cave_name, current_floor])

	await get_tree().create_timer(0.5).timeout
	_transitioning = false


func _update_floor_encounters(floor_num: int) -> void:
	var base_rate = 0.06
	var encounter_rate = base_rate + (floor_num - 1) * 0.02
	var pool = floor_encounter_pools.get(floor_num, [])

	var is_boss_floor = (floor_num == total_floors)
	if is_boss_floor:
		encounter_rate = 0.0
		controller.encounter_enabled = false
	else:
		controller.encounter_enabled = true

	var area_id = "%s_f%d" % [cave_id, floor_num]
	controller.set_area_config(area_id, is_boss_floor, encounter_rate, pool)
	controller.current_area_id = area_id

	DebugLogOverlay.log("[%s] Encounters: rate=%.0f%%, pool=%s" % [cave_name, encounter_rate * 100, str(pool)])


func _trigger_boss_battle() -> void:
	controller.pause_exploration()
	_show_boss_intro()
	await get_tree().create_timer(2.0).timeout
	battle_triggered.emit([boss_id])


func _show_boss_intro() -> void:
	var lines = _get_boss_intro_dialogue()
	print("")
	print("=== BOSS ENCOUNTER ===")
	print("")
	for line in lines:
		print(line)
	print("")
	print("======================")
	print("")


## Virtual - subclass MUST override to provide boss dialogue
func _get_boss_intro_dialogue() -> Array:
	return ["A dragon blocks the path!"]


func _on_boss_defeated() -> void:
	boss_defeated = true
	_save_boss_state()
	print("%s defeated! Exit stairs appear." % boss_id)
	_setup_transitions_for_floor(current_floor)


func _load_boss_state() -> void:
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.player_party.size() > 0:
		var flags = game_state.player_party[0].get("dungeon_flags", {})
		boss_defeated = flags.get(boss_flag_key, false)


func _save_boss_state() -> void:
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.player_party.size() > 0:
		if not game_state.player_party[0].has("dungeon_flags"):
			game_state.player_party[0]["dungeon_flags"] = {}
		game_state.player_party[0]["dungeon_flags"][boss_flag_key] = true


func _setup_player() -> void:
	player = OverworldPlayerScript.new()
	player.name = "Player"
	player.position = spawn_points.get("default", Vector2(320, 384))
	player.set_job("fighter")
	add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	camera.make_current()
	camera.zoom = Vector2(2.0, 2.0)

	var map_pixel_width = MAP_WIDTH * TILE_SIZE
	var map_pixel_height = MAP_HEIGHT * TILE_SIZE
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = map_pixel_width
	camera.limit_bottom = map_pixel_height
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0


func _setup_controller() -> void:
	controller = OverworldControllerScript.new()
	controller.name = "Controller"
	controller.player = player
	controller.encounter_enabled = true
	controller.current_area_id = "%s_f1" % cave_id

	_update_floor_encounters(current_floor)

	controller.battle_triggered.connect(_on_battle_triggered)
	controller.menu_requested.connect(_on_menu_requested)
	add_child(controller)


func _on_transition_triggered(target_map: String, spawn_point: String) -> void:
	area_transition.emit(target_map, spawn_point)


func _on_battle_triggered(enemies: Array) -> void:
	battle_triggered.emit(enemies)


func _on_menu_requested() -> void:
	pass


func spawn_player_at(spawn_name: String) -> void:
	if spawn_points.has(spawn_name):
		player.teleport(spawn_points[spawn_name])
		player.reset_step_count()


func resume() -> void:
	controller.resume_exploration()


func pause() -> void:
	controller.pause_exploration()


func set_player_job(job_name: String) -> void:
	if player:
		player.set_job(job_name)


func set_player_appearance(leader) -> void:
	if player and player.has_method("set_appearance_from_leader"):
		player.set_appearance_from_leader(leader)
