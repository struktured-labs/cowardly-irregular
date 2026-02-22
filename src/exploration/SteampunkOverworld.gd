extends Node2D
class_name SteampunkOverworld

## SteampunkOverworld - Steampunk/EarthBound 90s suburban-industrial overworld
## Features central plaza, residential blocks, industrial district, rail station, and park

const SteampunkTileGeneratorScript = preload("res://src/exploration/SteampunkTileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)

## Map dimensions (in tiles) - larger urban area
const MAP_WIDTH: int = 60
const MAP_HEIGHT: int = 50
const TILE_SIZE: int = 32

## Scene components
var tile_map: TileMapLayer
var player: Node2D  # OverworldPlayer
var camera: Camera2D
var controller: Node  # OverworldController
var tile_generator: Node  # SteampunkTileGenerator

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

	# Start steampunk overworld music
	if SoundManager:
		SoundManager.play_area_music("overworld_steampunk")

	exploration_ready.emit()


func _setup_scene() -> void:
	tile_generator = SteampunkTileGeneratorScript.new()
	add_child(tile_generator)

	# Background behind tilemap (dark industrial void)
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.10, 0.10, 0.12)  # Dark industrial gray
	bg.size = Vector2(MAP_WIDTH * TILE_SIZE + 400, MAP_HEIGHT * TILE_SIZE + 400)
	bg.position = Vector2(-200, -200)
	bg.z_index = -10
	add_child(bg)

	# Create TileMapLayer
	tile_map = TileMapLayer.new()
	tile_map.name = "TileMap"
	tile_map.tile_set = tile_generator.create_tileset()
	add_child(tile_map)

	# Create transitions container
	transitions = Node2D.new()
	transitions.name = "Transitions"
	add_child(transitions)

	# Create boundary walls
	_create_map_boundaries()


func _generate_map() -> void:
	# Steampunk city layout (60x50):
	# Top: Portal back to medieval overworld
	# Center: Plaza with fountain
	# East: Industrial district (factories, pipes, metal)
	# West: Residential blocks (buildings, doors, fences)
	# South: Rail station
	# Southwest: Park area
	#
	# Legend:
	# c = concrete, a = asphalt, b = brick_wall, m = metal_floor
	# p = pipe, g = park_grass, w = building_wall, d = door
	# i = window, r = rail_track, n = neon_sign, F = water_feature (fountain)
	# f = fence, y = alley, l = lamppost, h = manhole

	print("Generating steampunk overworld map %dx%d..." % [MAP_WIDTH, MAP_HEIGHT])

		var map_data: Array[String] = [
		"bbbbbbbbbbbbccccccccccccccchccccccccccccccccbbbbbbbbbbbbbbbb",
		"bwwwwwwwwwbcccccccccccccccccccccccccccccccccbwwwwwwwwwwwwcbc",
		"bwdwiwdwiwbcclcccccclcccccccccclcccccccclcccbwiwdwiwdwiwwcbc",
		"bwwwwwwwwwbccaaaaaaaaaaaaaaaaaaaaaaaaaaaaaacbwwwwwwwwwwwwcbc",
		"bfffffffbbccaacccccccccccccccccccccccccccaaccbbfffffffbbbbcc",
		"bgggggggccccaaccclcccccccccccccccccclccaaaccccccgggggggccccc",
		"bgggggggccccaaccccccccccccclcccccccccaaacccccccgggggggcccccc",
		"bgggggggccccaacccccccccccccccccccccccaacccccccccmmmmmmmmmmcc",
		"bfffffffccccaacccclcccccccccccccclcccaacccccccccmppppppppcmc",
		"cccccccccccaaaccccccccccccccccccccccaaaccccccccccmpppppppcmc",
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaammmmmmmmcm",
		"cccccccccccaaaccccccccccccccccccccccaaacccccccccccmpppppmcmc",
		"cclcccccclcaaccccccccccccccccccccccccaacccccccccccmpppmpmcmc",
		"cccccccccccaaccccccccccccccccccccccccaaccccccccccccmmmmmmcmc",
		"cccccccccccaaccclcccccccccccclcccccccaaccccccccccccccccccmcc",
		"cccccccccccaaccccccccccccccccccccccccaacccccccccccccnnnncmcc",
		"cclcccccclcaaccccccccccccccccccccccccaaccccccccccccnnnnnnccc",
		"cccccccccccaacccccccccccFccccccccccccaaccccccccccccnnnnccccc",
		"cccccccccccaaccccccccccFFFcccccccccccaaccccccccccccccccccccc",
		"cccccccccccaacccccccccccFccccccccccccaaccccccccchccccccccccc",
		"cccccccccccaacccccclccccccccccclccccaaaccccccccccccclccccccc",
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"cccccccccccaaccccccccccccccccccccccccaaccccccccccccccccccccc",
		"ccbwwwwwbccaaccccccccccccccccccccccccaaccbwwwwwbcccccccccccc",
		"ccbwdwiwbccaaccclcccccccccccccclcccccaaccbwidwwbcccccccccccc",
		"ccbwwwwwbccaaccccccccccccccccccccccccaaccbwwwwwbcccccccccccc",
		"ccbfffffbccaaccccccccccccccccccccccccaaccbfffffbcccccccccccc",
		"ccbgggggbccaaccccccccccccccccccccccccaaccbgggggbcccccccccccc",
		"ccbgggggbccaaccclcccccclcccclcccclcccaaccbgggggbcccccccccccc",
		"ccbfffffbccaaccccccccccccccccccccccccaaccbfffffbcccccccccccc",
		"ccccccccccaaacccccccccccccccccccccccaaaccccccccccccccccccccc",
		"cccccccccaaaccccccccccccccccccccccccaaaccccccccccccccccccccc",
		"ccccccccaaacccccccccclccccccclccccccaaacccccccclcccccccclccc",
		"ccggggggccaacccccccccccccccccccccccccaaccccccccccccccccccccc",
		"cgggggggccaacccccccccccccccccccccccccaaccccccccccccccccccccc",
		"cggggFgggcaacccccccccccccccccccccccccaaccccccccccccccccccccc",
		"cgggFFFggcaaccclcccccccccccccclcccccaaaccccccccccccccccccccc",
		"cggggFgggcaacccccccccccccccccccccccaaacccccccccccccccccccccc",
		"cgggggggccaacccccccccclcccclcccccccaaccccccccccccccccccccccc",
		"ccggggggccaacccccccccccccccccccccccaaclcccccccccccccccclcccc",
		"cfffffffccaaaccccccccccccccccccccccaaacccccccccccccccccccccc",
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
		"cccccccccccccccccclcccccclcccclccccccccccccccccclccccccccccc",
		"ccccccccccrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrcccccccccccccc",
		"ccccccccccrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrcccccccccccccc",
		"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
		"ccccccccccccccbwwdwwbccccccccccccbwwdwwbcccccccccccccccccccc",
		"ccccccccccccccbwwwwwbccccccccccccbwwwwwbcccccccccccccccccccc",
		"ccccccccccccccbbbbbbbbcccccccccccbbbbbbbbccccccccccccccccccc",
	]

	# Ensure map_data matches expected dimensions
	while map_data.size() < MAP_HEIGHT:
		map_data.append("cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")

	# Convert map_data to tiles
	var tile_counts = {}
	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "c"
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			# Count tiles for debug
			tile_counts[tile_type] = tile_counts.get(tile_type, 0) + 1

	print("Steampunk tile counts: ", tile_counts)

	# Define spawn points
	spawn_points["entrance"] = Vector2(27 * TILE_SIZE + TILE_SIZE / 2, 2 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["plaza"] = Vector2(22 * TILE_SIZE + TILE_SIZE / 2, 17 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["station"] = Vector2(25 * TILE_SIZE + TILE_SIZE / 2, 43 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["steampunk_portal"] = Vector2(27 * TILE_SIZE + TILE_SIZE / 2, 1 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["default"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"c": return SteampunkTileGeneratorScript.TileType.CONCRETE
		"a": return SteampunkTileGeneratorScript.TileType.ASPHALT
		"b": return SteampunkTileGeneratorScript.TileType.BRICK_WALL
		"m": return SteampunkTileGeneratorScript.TileType.METAL_FLOOR
		"p": return SteampunkTileGeneratorScript.TileType.PIPE
		"g": return SteampunkTileGeneratorScript.TileType.PARK_GRASS
		"w": return SteampunkTileGeneratorScript.TileType.BUILDING_WALL
		"d": return SteampunkTileGeneratorScript.TileType.DOOR
		"i": return SteampunkTileGeneratorScript.TileType.WINDOW
		"r": return SteampunkTileGeneratorScript.TileType.RAIL_TRACK
		"n": return SteampunkTileGeneratorScript.TileType.NEON_SIGN
		"F": return SteampunkTileGeneratorScript.TileType.WATER_FEATURE
		"f": return SteampunkTileGeneratorScript.TileType.FENCE
		"y": return SteampunkTileGeneratorScript.TileType.ALLEY
		"l": return SteampunkTileGeneratorScript.TileType.LAMPPOST
		"h": return SteampunkTileGeneratorScript.TileType.MANHOLE
		_: return SteampunkTileGeneratorScript.TileType.CONCRETE


func _get_atlas_coords(tile_type: int) -> Vector2i:
	# Map tile types to atlas coordinates (4-column layout)
	var tile_id = SteampunkTileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 4, tile_id / 4)


func _setup_transitions() -> void:
	# Portal back to medieval overworld at north edge
	var portal_trans = AreaTransitionScript.new()
	portal_trans.name = "MedievalPortal"
	portal_trans.target_map = "overworld"
	portal_trans.target_spawn = "steampunk_portal"
	portal_trans.require_interaction = true
	portal_trans.indicator_text = "Return to Overworld"
	portal_trans.position = spawn_points.get("steampunk_portal", Vector2(864, 48))
	_setup_transition_collision(portal_trans, Vector2(TILE_SIZE, TILE_SIZE))
	portal_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(portal_trans)


func _setup_transition_collision(trans: Area2D, size: Vector2) -> void:
	# Layer 4 = interactables, Mask 2 = player layer
	trans.collision_layer = 4
	trans.collision_mask = 2
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
	player.position = spawn_points.get("default", Vector2(864, 80))
	player.set_job("fighter")
	add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"

	# Camera follows player
	player.add_child(camera)
	camera.make_current()

	# 2x zoom for larger sprites
	camera.zoom = Vector2(2.0, 2.0)

	# Camera limits to map bounds
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
	controller.current_area_id = "steampunk_overworld"

	# Encounters in industrial outskirts, safe in central plaza
	controller.set_area_config("steampunk_overworld", false, 0.04, ["clockwork_sentinel", "steam_rat", "brass_golem", "cog_swarm", "pipe_phantom"])

	# Connect signals
	controller.battle_triggered.connect(_on_battle_triggered)
	controller.menu_requested.connect(_on_menu_requested)

	add_child(controller)


func _on_transition_triggered(target_map: String, spawn_point: String) -> void:
	area_transition.emit(target_map, spawn_point)


func _on_battle_triggered(enemies: Array) -> void:
	battle_triggered.emit(enemies)


func _on_menu_requested() -> void:
	pass  # Handled by GameLoop


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


## Set the player's appearance from the party leader
func set_player_appearance(leader) -> void:
	if player and player.has_method("set_appearance_from_leader"):
		player.set_appearance_from_leader(leader)


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
