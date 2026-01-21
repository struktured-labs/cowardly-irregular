extends Node2D
class_name OverworldScene

## OverworldScene - Main overworld exploration scene
## Procedurally generates the tilemap and sets up exploration

const TileGeneratorScript = preload("res://src/exploration/TileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)

## Map dimensions (in tiles)
const MAP_WIDTH: int = 40
const MAP_HEIGHT: int = 30
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

	# Start overworld music
	if SoundManager:
		SoundManager.play_area_music("overworld")

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

	# Create boundary walls (StaticBody2D around the map)
	_create_map_boundaries()


func _generate_map() -> void:
	# Define the map layout (matching the plan's ASCII art)
	# ~ = water, M = mountain, . = path, g = grass
	# C = cave entrance, V = village entrance

	print("Generating overworld map %dx%d..." % [MAP_WIDTH, MAP_HEIGHT])

	var map_data: Array[String] = [
		"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~",
		"~~MMMMM~~~~~~MMM~~~MMMMMM~~~~~~~~~~~~~~~",
		"~~MC.........MMM~~~MMMMMMM~~~~~~~~~~~~~~",
		"~~MM.~~~~~~~~MMM~~~MMMMMMM~~~~~~~~~~~~~~",
		"~~~~.~~~~....MMM~~~~~~~~~~~~~~~~~~~~~~~~",
		"~~~~.~~......MMM~~~~~~~~~~~~~~~~~~~~~~~~",
		"~~~~..V.................................",
		"~~~~~~~.................................",
		"~~~~~~~......gggggg.....................",
		"~~~~~~~~....gggggggg....................",
		"~~~~~~~~...ggggggggggg..................",
		"~~~~~~~~~.ggggggggggggg.................",
		"~~~~~~~~~~gggggggggggggg................",
		"~~~~~~~~~~ggggggggggggggg...............",
		"~~~~~~~~~gggggggggggggg.................",
		"~~~~~~~~ggggggggggggg...................",
		"~~~~~~~ggggggggggg......................",
		"~~~~~~gggggggggg........................",
		"~~~~~ggggggggg..........................",
		"~~~~gggggggg............................",
		"~~~ggggggg..............................",
		"~~gggggg................................",
		"~ggggg..................................",
		"gggg....................................",
		"ggg.....................................",
		"gg......................................",
		"g.......................................",
		"........................................",
		"........................................",
		"........................................"
	]

	# Ensure map_data matches expected dimensions
	while map_data.size() < MAP_HEIGHT:
		map_data.append("........................................")

	# Convert map_data to tiles
	var tile_counts = {}
	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "."
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			# Count tiles for debug
			tile_counts[tile_type] = tile_counts.get(tile_type, 0) + 1

			# Mark special locations
			if char == "C":
				spawn_points["cave_entrance"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)
			elif char == "V":
				spawn_points["village_entrance"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)

	print("Tile counts: ", tile_counts)

	# Default spawn point (near village)
	spawn_points["default"] = spawn_points.get("village_entrance", Vector2(320, 224))


func _char_to_tile_type(char: String) -> int:
	match char:
		"~": return TileGeneratorScript.TileType.WATER
		"M": return TileGeneratorScript.TileType.MOUNTAIN
		".": return TileGeneratorScript.TileType.PATH
		"g": return TileGeneratorScript.TileType.GRASS
		"C": return TileGeneratorScript.TileType.CAVE_ENTRANCE
		"V": return TileGeneratorScript.TileType.VILLAGE_GATE
		"F": return TileGeneratorScript.TileType.FOREST
		"B": return TileGeneratorScript.TileType.BRIDGE
		_: return TileGeneratorScript.TileType.GRASS


func _get_atlas_coords(tile_type: int) -> Vector2i:
	# Map tile types to atlas coordinates (based on TileGenerator.create_tileset order)
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 4, tile_id / 4)


func _setup_transitions() -> void:
	# Village entrance transition - REQUIRES INTERACTION to prevent spawn loop
	var village_trans = AreaTransitionScript.new()
	village_trans.name = "VillageEntrance"
	village_trans.target_map = "harmonia_village"
	village_trans.target_spawn = "entrance"
	village_trans.require_interaction = true  # Must press button to enter
	village_trans.indicator_text = "Enter Village"
	village_trans.position = spawn_points.get("village_entrance", Vector2(320, 224))
	_setup_transition_collision(village_trans, Vector2(TILE_SIZE, TILE_SIZE))
	village_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(village_trans)

	# Spawn point is ON the trigger - player must press button to re-enter
	spawn_points["village_entrance"] = village_trans.position

	# Cave entrance transition - REQUIRES INTERACTION to prevent spawn loop
	var cave_trans = AreaTransitionScript.new()
	cave_trans.name = "CaveEntrance"
	cave_trans.target_map = "whispering_cave"
	cave_trans.target_spawn = "entrance"
	cave_trans.require_interaction = true  # Must press button to enter
	cave_trans.indicator_text = "Enter Cave"
	cave_trans.position = spawn_points.get("cave_entrance", Vector2(96, 96))
	_setup_transition_collision(cave_trans, Vector2(TILE_SIZE, TILE_SIZE))
	cave_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(cave_trans)

	# Spawn point is on the PATH next to the cave (not inside the mountain!)
	# The path is at column 4, row 2 = (4*32+16, 2*32+16) = (144, 80)
	spawn_points["cave_entrance"] = Vector2(4 * TILE_SIZE + TILE_SIZE / 2, 2 * TILE_SIZE + TILE_SIZE / 2)


func _setup_transition_collision(trans: Area2D, size: Vector2) -> void:
	# Set collision layers for interaction
	# Layer 4 = interactables (so controller can detect us for require_interaction)
	# Mask 2 = player layer (to detect player entering zone)
	trans.collision_layer = 4  # Interactable layer for controller queries
	trans.collision_mask = 2   # Detect player on layer 2
	trans.monitoring = true
	trans.monitorable = true

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	trans.add_child(collision)


func _setup_player() -> void:
	player = OverworldPlayerScript.new()
	player.name = "Player"
	player.position = spawn_points.get("default", Vector2(320, 256))
	player.set_job("fighter")  # Default job
	add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"

	# Make camera follow player
	player.add_child(camera)
	camera.make_current()

	# Zoom in for larger sprites (2x)
	camera.zoom = Vector2(2.0, 2.0)

	# Set camera limits to map bounds
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MAP_WIDTH * TILE_SIZE
	camera.limit_bottom = MAP_HEIGHT * TILE_SIZE

	# Smooth camera follow
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0


func _setup_controller() -> void:
	controller = OverworldControllerScript.new()
	controller.name = "Controller"
	controller.player = player
	controller.encounter_enabled = true
	controller.current_area_id = "overworld"

	# Configure overworld encounter settings
	controller.set_area_config("overworld", false, 0.05, ["slime", "bat", "goblin"])

	# Connect signals
	controller.battle_triggered.connect(_on_battle_triggered)
	controller.menu_requested.connect(_on_menu_requested)

	add_child(controller)


func _on_transition_triggered(target_map: String, spawn_point: String) -> void:
	area_transition.emit(target_map, spawn_point)


func _on_battle_triggered(enemies: Array) -> void:
	battle_triggered.emit(enemies)


func _on_menu_requested() -> void:
	# Open party menu
	pass  # Will be handled by GameLoop


## Spawn player at a specific spawn point
func spawn_player_at(spawn_name: String) -> void:
	if spawn_points.has(spawn_name):
		player.teleport(spawn_points[spawn_name])
		player.reset_step_count()


## Resume exploration after battle/menu
func resume() -> void:
	controller.resume_exploration()


## Pause exploration
func pause() -> void:
	controller.pause_exploration()


## Set the player's job (updates sprite)
func set_player_job(job_name: String) -> void:
	if player:
		player.set_job(job_name)


## Create invisible walls around map boundaries
func _create_map_boundaries() -> void:
	var bounds = StaticBody2D.new()
	bounds.name = "MapBoundaries"
	add_child(bounds)

	var map_w = MAP_WIDTH * TILE_SIZE
	var map_h = MAP_HEIGHT * TILE_SIZE
	var wall_thickness = 32.0

	# Top wall
	_add_boundary_wall(bounds, Vector2(map_w / 2, -wall_thickness / 2), Vector2(map_w + wall_thickness * 2, wall_thickness))
	# Bottom wall
	_add_boundary_wall(bounds, Vector2(map_w / 2, map_h + wall_thickness / 2), Vector2(map_w + wall_thickness * 2, wall_thickness))
	# Left wall
	_add_boundary_wall(bounds, Vector2(-wall_thickness / 2, map_h / 2), Vector2(wall_thickness, map_h + wall_thickness * 2))
	# Right wall
	_add_boundary_wall(bounds, Vector2(map_w + wall_thickness / 2, map_h / 2), Vector2(wall_thickness, map_h + wall_thickness * 2))


func _add_boundary_wall(parent: StaticBody2D, pos: Vector2, size: Vector2) -> void:
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	collision.position = pos
	parent.add_child(collision)
