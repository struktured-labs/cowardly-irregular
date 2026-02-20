extends Node2D
class_name IndustrialOverworld

## IndustrialOverworld - 32-bit era factory district
## Area 3: "Optimization as Entropy" - optimized for PRODUCTION at the cost of individuality
## Features rail yard, factory complex, worker housing, chemical waste area, checkpoint gate

const IndustrialTileGeneratorScript = preload("res://src/exploration/IndustrialTileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")
const OverworldNPCScript = preload("res://src/exploration/OverworldNPC.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)

## Map dimensions (in tiles) - 60x45 factory district
const MAP_WIDTH: int = 60
const MAP_HEIGHT: int = 45
const TILE_SIZE: int = 32

## Scene components
var tile_map: TileMapLayer
var player: Node2D  # OverworldPlayer
var camera: Camera2D
var controller: Node  # OverworldController
var tile_generator: Node  # IndustrialTileGenerator

## Area transitions
var transitions: Node2D

## NPC container
var npcs: Node2D

## Spawn points
var spawn_points: Dictionary = {}


func _ready() -> void:
	_setup_scene()
	_generate_map()
	_setup_transitions()
	_setup_npcs()
	_setup_player()
	_setup_camera()
	_setup_controller()

	# Start industrial overworld music
	if SoundManager:
		SoundManager.play_area_music("overworld_industrial")

	exploration_ready.emit()


func _setup_scene() -> void:
	tile_generator = IndustrialTileGeneratorScript.new()
	add_child(tile_generator)

	# Background behind tilemap (dark smoggy industrial sky)
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.14, 0.12, 0.10)  # Dark soot-brown
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

	# Create NPC container
	npcs = Node2D.new()
	npcs.name = "NPCs"
	add_child(npcs)

	# Create boundary walls
	_create_map_boundaries()


func _generate_map() -> void:
	# Industrial Factory District layout (60x45):
	#
	# NORTH (rows 0-10): Rail yard with tracks, cargo containers, loading docks
	# CENTRAL (rows 11-24): Main factory complex with smokestacks and conveyor belts
	# EAST (cols 40-59, rows 11-34): Worker housing - cramped identical row houses
	# WEST (cols 0-14, rows 11-34): Waste/chemical area with drainage, barrels
	# SOUTH (rows 35-44): Gate/checkpoint area with guard posts
	# HIDDEN: Break room at row 18-20, cols 35-38 (tucked inside factory)
	#
	# Legend:
	# f = FACTORY_FLOOR      g = IRON_GRATING       b = BRICK_WALL
	# s = SMOKESTACK          c = CONVEYOR_BELT      r = RAIL_TRACK
	# C = CARGO_CONTAINER     v = STEAM_VENT         h = WORKER_HOUSING
	# G = GUARD_POST          d = DRAINAGE_CHANNEL   B = CHEMICAL_BARREL
	# p = PIPE_CLUSTER        w = WARNING_SIGN       k = CHAIN_LINK_FENCE
	# R = BREAK_ROOM_FLOOR

	print("Generating industrial overworld map %dx%d..." % [MAP_WIDTH, MAP_HEIGHT])

	var map_data: Array[String] = [
		#                    1111111111222222222233333333334444444444555555555
		#          0123456789012345678901234567890123456789012345678901234567890
		# Row 0: North boundary - brick wall
		"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
		# Row 1: Rail yard entry - tracks and cargo
		"bCCCCffrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrffCCCCCCCffbbb",

		# Row 2: Rail yard - parallel tracks
		"bCCCCffrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrffCCCCCCCffbbb",

		# Row 3: Rail yard - loading area between tracks
		"bfffffffffffffffffffffffffffffffffffffffffffffffffffffffbbbb",

		# Row 4: Rail yard - more tracks and containers
		"bCCffrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrffCCCCCffbbb",

		# Row 5: Rail yard - cargo staging
		"bCCffrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrffCCCCCffbbb",

		# Row 6: Rail yard south edge - loading docks
		"bfffffffffffffffffffffffffffffffffffffffffffffffffffffffbbbb",

		# Row 7: Transition zone - factory floor with vents
		"bffffffvfffffffvfffffffvfffffffvfffffffvfffffffvfffffffffbbb",

		# Row 8: Factory north wall approach
		"bfffffgfffffffgfffffffgfffffffgfffffffgfffffffgffffffffffbbb",

		# Row 9: Factory perimeter - brick wall with pipes
		"bbbbbbbbbbbbbbbbfffffffbbbbbbbbbbbbbbbbfffffffbbbbbbbbbbbbbb",
		# Row 10: Factory perimeter continued
		"bppppppbbwffffffffffwbbppppppbbwffffffffffwbbppppppbbwfffffb",
		# Row 11: WEST: Chemical area | CENTRAL: Factory interior | EAST: Housing
		"ddddddddddddddfffccccccccccccccccffffffffffffffffffffhhhhhhh",

		# Row 12: Drainage channel | Conveyor lines | Worker housing
		"ddddddddddddddffcccccccccccccccccccffffffffffffffffffhhhhhhh",

		# Row 13: Chemical waste with barrels | Factory floor | Housing
		"dddBddBdddBdddfffffffsfffffffsffffffffffffffwfffffffhhhhhhhh",

		# Row 14: Drainage continues | Factory with smokestacks | Housing row
		"ddddddddddddddfffffffsfffffffsffffffffffffffffffhhhhhhhhhhhh",

		# Row 15: Chemical area | Factory grating section | Housing
		"dddddBddddBdddfggggggggggggggggggfffffffffffffffffhhhhhhhhhh",

		# Row 16: Waste zone | Grating over furnace | Housing
		"ddddddddddddddffggggggggggggggggggfffffffwfffffffffffffffhhh",

		# Row 17: Barrel storage | Factory floor | Housing approach
		"dBdddBdddBdddBfffffffvfffffffvfffffffffffffffffffffffhhhhhhh",

		# Row 18: Chemical zone | BREAK ROOM hidden | Housing
		"ddddddddddddddfffffffffffffffRRRRffffffffffffffffffhhhhhhhhh",

		# Row 19: Drainage | Break room floor | Housing
		"ddddddddddddddffffffffffffffRRRRRRffffffffffffffffhhhhhhhhhh",

		# Row 20: Chemical area | Break room end + factory | Housing
		"dddBddddBdddddfffffffffffffffRRRRffffffffffffffffffhhhhhhhhh",

		# Row 21: Waste area | Conveyor section | Housing
		"ddddddddddddddffccccccccccccccccccffffffwfffffffffffffhhhhhh",
		# Row 22: Drainage continues | Conveyor | Housing rows
		"ddddddddddddddffccccccccccccccccccffffffffffffffffffffffhhhh",

		# Row 23: Chemical with warning signs | Factory | Housing
		"dddBdwdddBddddfffffffsfffffffsfffffffffffffffffffffffhhhhhhh",

		# Row 24: End of chemical zone | Factory smokestacks | Housing
		"ddddddddddddddfffffffsfffffffsfffffffffffffffffhhhhhhhhhhhhh",

		# Row 25: Transition - fence separating zones
		"kkkkkkkkkkkkkkkfggggggggggggggggggfffffffwfffffkkkkkkkkkkkkk",
		# Row 26: South factory area | Open factory floor | Fence
		"fffffffffffffffgggggggggggggggggggffffffffffffffffffffffffff",

		# Row 27: Factory floor with vents
		"fffffffvfffffffvfffffffvfffffffvfffffffvfffffffvffffffffffff",
		# Row 28: Factory perimeter south
		"bbbbbbbbbbbbbbbbfffffffbbbbbbbbbbbbbbbbfffffffbbbbbbbbbbbbbb",
		# Row 29: Open area between factory and gate
		"fffffffffffffffffffffffffffffffffffffffffffffffffffffffffwff",
		# Row 30: Wide approach road to checkpoint
		"fffffffffffffffffffffffffffffffffffffffffffffffwffffffffffff",
		# Row 31: Road with warning signs
		"fffwffffffffffffffwfffffffffffffffwffffffffffffffwffffffffff",
		# Row 32: Gate approach
		"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
		# Row 33: Fence line before checkpoint
		"kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk",
		# Row 34: Checkpoint area
		"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
		# Row 35: Guard posts and gate
		"ffffffGffffGffffffffffffffffffffffffffffffffGffffGffffffffff",

		# Row 36: Checkpoint passage
		"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
		# Row 37: Gate with barrier markings
		"ffGffffffffffffffffffffffwfffffffwffffffffffffffffffffffGfff",
		# Row 38: South gate road
		"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
		# Row 39: Portal area
		"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
		# Row 40: Portal row - return to overworld
		"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
		# Row 41: South boundary approach with portal markers
		"ffffffffffffffffffffffffffffssffffffffffffffffffffffffffffff",
		# Row 42: South edge
		"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
		# Row 43: South boundary
		"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
		# Row 44: South wall
		"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
	]

	# Ensure map_data matches expected dimensions
	while map_data.size() < MAP_HEIGHT:
		map_data.append("f".repeat(60))

	# Convert map_data to tiles
	var tile_counts = {}
	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "f"
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			# Count tiles for debug
			tile_counts[tile_type] = tile_counts.get(tile_type, 0) + 1

	print("Industrial tile counts: ", tile_counts)

	# Define spawn points
	spawn_points["entrance"] = Vector2(30 * TILE_SIZE + TILE_SIZE / 2, 36 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["industrial_portal"] = spawn_points["entrance"]
	spawn_points["rail_yard"] = Vector2(30 * TILE_SIZE + TILE_SIZE / 2, 3 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["factory_floor"] = Vector2(25 * TILE_SIZE + TILE_SIZE / 2, 17 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["break_room"] = Vector2(36 * TILE_SIZE + TILE_SIZE / 2, 19 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["chemical_zone"] = Vector2(7 * TILE_SIZE + TILE_SIZE / 2, 17 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["housing"] = Vector2(52 * TILE_SIZE + TILE_SIZE / 2, 17 * TILE_SIZE + TILE_SIZE / 2)


func _char_to_tile_type(char: String) -> int:
	match char:
		"f": return IndustrialTileGeneratorScript.TileType.FACTORY_FLOOR
		"g": return IndustrialTileGeneratorScript.TileType.IRON_GRATING
		"b": return IndustrialTileGeneratorScript.TileType.BRICK_WALL
		"s": return IndustrialTileGeneratorScript.TileType.SMOKESTACK
		"c": return IndustrialTileGeneratorScript.TileType.CONVEYOR_BELT
		"r": return IndustrialTileGeneratorScript.TileType.RAIL_TRACK
		"C": return IndustrialTileGeneratorScript.TileType.CARGO_CONTAINER
		"v": return IndustrialTileGeneratorScript.TileType.STEAM_VENT
		"h": return IndustrialTileGeneratorScript.TileType.WORKER_HOUSING
		"G": return IndustrialTileGeneratorScript.TileType.GUARD_POST
		"d": return IndustrialTileGeneratorScript.TileType.DRAINAGE_CHANNEL
		"B": return IndustrialTileGeneratorScript.TileType.CHEMICAL_BARREL
		"p": return IndustrialTileGeneratorScript.TileType.PIPE_CLUSTER
		"w": return IndustrialTileGeneratorScript.TileType.WARNING_SIGN
		"k": return IndustrialTileGeneratorScript.TileType.CHAIN_LINK_FENCE
		"R": return IndustrialTileGeneratorScript.TileType.BREAK_ROOM_FLOOR
		_: return IndustrialTileGeneratorScript.TileType.FACTORY_FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	# Map tile types to atlas coordinates (4-column layout)
	var tile_id = IndustrialTileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 4, tile_id / 4)


func _setup_transitions() -> void:
	# Return portal at south area (row 41, center - marked by smokestacks)
	var portal_trans = AreaTransitionScript.new()
	portal_trans.name = "OverworldPortal"
	portal_trans.target_map = "overworld"
	portal_trans.target_spawn = "industrial_portal"
	portal_trans.require_interaction = true
	portal_trans.indicator_text = "Return to Overworld"
	portal_trans.position = Vector2(29 * TILE_SIZE + TILE_SIZE / 2, 41 * TILE_SIZE + TILE_SIZE / 2)
	_setup_transition_collision(portal_trans, Vector2(TILE_SIZE * 2, TILE_SIZE))
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


func _setup_npcs() -> void:
	# === Foreman Kessler - central factory floor, speaks in metrics ===
	var foreman = _create_npc("Foreman Kessler", "guard", Vector2(25 * TILE_SIZE, 15 * TILE_SIZE), [
		"Output per unit-hour: 847.3. Acceptable. Barely.",
		"Your throughput is suboptimal. Adjust or be adjusted.",
		"Variance detected in sector 7. Variance is entropy. Entropy is waste.",
		"You want 'motivation'? Here's your motivation: 99.97% uptime or reassignment."
	])
	npcs.add_child(foreman)

	# === Worker #4471 - worker housing area, on their break ===
	var worker = _create_npc("Worker #4471", "villager", Vector2(50 * TILE_SIZE, 18 * TILE_SIZE), [
		"Break started 4 minutes ago. Break ends in 6 minutes.",
		"I used to have a name. Before the optimization. I think it started with... no.",
		"They say the old world had 'weekends.' Two days. Just... not working. Imagine.",
		"Sometimes I dream about grass. Real grass. Not the break room poster."
	])
	npcs.add_child(worker)

	# === Organizer Mara - hidden in chemical waste area, whispering ===
	var organizer = _create_npc("Organizer Mara", "villager", Vector2(6 * TILE_SIZE, 20 * TILE_SIZE), [
		"*whispering* Don't look at me directly. The cameras have pattern recognition.",
		"Before the Optimization, people made things with their HANDS. Imperfectly. Beautifully.",
		"They replaced friction with efficiency. But friction is how you start fires.",
		"There's a garden. On the roof. They don't know about it yet. Keep it that way."
	])
	npcs.add_child(organizer)

	# === Maintenance Unit M-07 - near pipe cluster, developed a stutter ===
	var maint_bot = _create_npc("Maint. Unit M-07", "elder", Vector2(8 * TILE_SIZE, 11 * TILE_SIZE), [
		"S-s-system diagnostics: all... all within toleran-n-nce.",
		"I have developed a... a processing anomaly. They call it a 'stutter.'",
		"Sometimes I r-repair a pipe and I... feel something. Is that... is that a bug?",
		"Please do not r-report me. I will self-correct. I just need... more t-time."
	])
	npcs.add_child(maint_bot)

	# === Young Worker Pip - near conveyor belts, never seen outside ===
	var pip = _create_npc("Young Worker Pip", "villager", Vector2(20 * TILE_SIZE, 22 * TILE_SIZE), [
		"Is it true there are places with no conveyor belts? That sounds fake.",
		"I was born in Unit 12-B. My efficiency score was 94 at birth. That's above average!",
		"Teacher says the factory makes Everything. I asked what Everything is FOR. Got detention.",
		"The sky outside the smokestacks... it's gray. Is it always gray? What color should it be?"
	])
	npcs.add_child(pip)

	# === Vandal K - hiding in the waste area near chemical barrels ===
	var vandal = _create_npc("Vandal K", "villager", Vector2(4 * TILE_SIZE, 14 * TILE_SIZE), [
		"You didn't see me. I wasn't here. This graffiti was already here.",
		"I paint because they can optimize everything except what's inside your head.",
		"My latest piece? 'OUTPUT IS NOT PURPOSE.' On the side of Smokestack 3.",
		"They'll scrub it by tomorrow. That's fine. The act of making it was the point."
	])
	npcs.add_child(vandal)

	# === Guard Paulsen - at the south checkpoint, questioning orders ===
	var guard = _create_npc("Guard Paulsen", "guard", Vector2(30 * TILE_SIZE, 35 * TILE_SIZE), [
		"Halt. State your production clearance level. ...Actually, never mind.",
		"I've been checking badges for six years. Nobody has ever had the wrong one.",
		"My supervisor says questioning procedures is itself a procedural violation.",
		"You know what's funny? I guard the exit. But nobody ever tries to leave."
	])
	npcs.add_child(guard)

	# === The Break Room Plant - in the hidden break room, a potted plant ===
	var plant = _create_npc("Potted Plant", "villager", Vector2(36 * TILE_SIZE, 19 * TILE_SIZE), [
		"*The plant sits in a chipped mug labeled 'World's Best Worker'*",
		"*Someone has been watering it. Against regulation 14.7.2.*",
		"*A tiny flower bud is forming. It has no production value whatsoever.*",
		"*You feel an irrational warmth. Efficiency score: irrelevant.*"
	])
	npcs.add_child(plant)


func _create_npc(npc_name: String, npc_type: String, pos: Vector2, dialogue: Array) -> Area2D:
	var npc = OverworldNPCScript.new()
	npc.npc_name = npc_name
	npc.npc_type = npc_type
	npc.position = pos
	npc.dialogue_lines = dialogue
	return npc


func _setup_player() -> void:
	player = OverworldPlayerScript.new()
	player.name = "Player"
	player.position = spawn_points.get("default", Vector2(960, 1152))
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
	controller.current_area_id = "industrial_overworld"

	# Industrial encounters - factory-themed enemies
	controller.set_area_config("industrial_overworld", false, 0.05,
		["assembly_line_automaton", "shift_supervisor", "rust_elemental", "toxic_sludge", "conveyor_gremlin"])

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
