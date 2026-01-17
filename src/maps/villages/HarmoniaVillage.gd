extends Node2D
class_name HarmoniaVillageScene

## HarmoniaVillage - Starter village, safe zone
## No random encounters, NPCs, shops, inn

const TileGeneratorScript = preload("res://src/exploration/TileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)

## Map dimensions (in tiles)
const MAP_WIDTH: int = 20
const MAP_HEIGHT: int = 15
const TILE_SIZE: int = 32

## Scene components
var tile_map: TileMapLayer
var player: Node2D  # OverworldPlayer
var camera: Camera2D
var controller: Node  # OverworldController
var tile_generator: Node  # TileGenerator

## Area transitions
var transitions: Node2D

## Spawn points
var spawn_points: Dictionary = {}


func _ready() -> void:
	_setup_scene()
	_generate_map()
	_setup_transitions()
	_setup_player()
	_setup_camera()
	_setup_controller()

	exploration_ready.emit()


func _setup_scene() -> void:
	tile_generator = TileGeneratorScript.new()
	add_child(tile_generator)

	# Create TileMapLayer
	tile_map = TileMapLayer.new()
	tile_map.name = "TileMap"
	tile_map.tile_set = tile_generator.create_tileset()
	add_child(tile_map)

	# Create transitions container
	transitions = Node2D.new()
	transitions.name = "Transitions"
	add_child(transitions)


func _generate_map() -> void:
	# Village layout:
	# W = wall, . = floor, I = inn, S = shop, N = NPC spot, X = exit, P = save point
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWW",
		"W..................W",
		"W..III.......SSS...W",
		"W..III.......SSS...W",
		"W..................W",
		"W.......NNN........W",
		"W..................W",
		"W..................W",
		"W........PPP.......W",
		"W........PPP.......W",
		"W..................W",
		"W..................W",
		"W.......XXXX.......W",
		"W.......XXXX.......W",
		"WWWWWWWWWWWWWWWWWWWW"
	]

	# Convert map_data to tiles
	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "W"
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			# Mark special locations
			if char == "X" and not spawn_points.has("exit"):
				spawn_points["exit"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)

	# Default spawn (entrance from overworld) - slightly inside to avoid immediate exit trigger
	spawn_points["entrance"] = Vector2(10 * TILE_SIZE, 10 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		".": return TileGeneratorScript.TileType.FLOOR
		"I": return TileGeneratorScript.TileType.FLOOR  # Inn area (floor)
		"S": return TileGeneratorScript.TileType.FLOOR  # Shop area (floor)
		"N": return TileGeneratorScript.TileType.FLOOR  # NPC area (floor)
		"X": return TileGeneratorScript.TileType.FLOOR  # Exit (floor)
		"P": return TileGeneratorScript.TileType.FLOOR  # Save point (floor)
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 4, tile_id / 4)


func _setup_transitions() -> void:
	# Exit back to overworld
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "overworld"
	exit_trans.target_spawn = "village_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(320, 416))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 4, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_transition_collision(trans: Area2D, size: Vector2) -> void:
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	trans.add_child(collision)


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

	# Set camera limits to map bounds
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MAP_WIDTH * TILE_SIZE
	camera.limit_bottom = MAP_HEIGHT * TILE_SIZE

	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0


func _setup_controller() -> void:
	controller = OverworldControllerScript.new()
	controller.name = "Controller"
	controller.player = player
	controller.encounter_enabled = false  # Safe zone!
	controller.current_area_id = "harmonia_village"

	# Configure as safe zone
	controller.set_area_config("harmonia_village", true, 0.0, [])

	controller.battle_triggered.connect(_on_battle_triggered)
	controller.menu_requested.connect(_on_menu_requested)

	add_child(controller)


func _on_transition_triggered(target_map: String, spawn_point: String) -> void:
	area_transition.emit(target_map, spawn_point)


func _on_battle_triggered(enemies: Array) -> void:
	battle_triggered.emit(enemies)


func _on_menu_requested() -> void:
	pass


## Spawn player at a specific spawn point
func spawn_player_at(spawn_name: String) -> void:
	if spawn_points.has(spawn_name):
		player.teleport(spawn_points[spawn_name])
		player.reset_step_count()


## Resume exploration
func resume() -> void:
	controller.resume_exploration()


## Pause exploration
func pause() -> void:
	controller.pause_exploration()


## Set the player's job
func set_player_job(job_name: String) -> void:
	if player:
		player.set_job(job_name)
