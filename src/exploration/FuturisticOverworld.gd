extends Node2D
class_name FuturisticOverworld

## FuturisticOverworld - Area 4: "Optimized for Computation"
## A digital cityscape where everything serves data processing.
## Buildings are server farms. Streets are data highways. People are I/O terminals.
## Aesthetic: Tron meets Ghost in the Shell meets a sterile Apple Store.

const FuturisticTileGeneratorScript = preload("res://src/exploration/FuturisticTileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")
const OverworldNPCScript = preload("res://src/exploration/OverworldNPC.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)

## Map dimensions (in tiles) - 55x45 digital cityscape
const MAP_WIDTH: int = 55
const MAP_HEIGHT: int = 45
const TILE_SIZE: int = 32

## Scene components
var tile_map: TileMapLayer
var player: Node2D  # OverworldPlayer
var camera: Camera2D
var controller: Node  # OverworldController
var tile_generator: Node  # FuturisticTileGenerator

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

	# Start futuristic overworld music
	if SoundManager:
		SoundManager.play_area_music("overworld_futuristic")

	exploration_ready.emit()


func _setup_scene() -> void:
	tile_generator = FuturisticTileGeneratorScript.new()
	add_child(tile_generator)

	# Background behind tilemap (deep digital void - near black with blue tint)
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.02, 0.03, 0.06)
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
	# Futuristic digital cityscape layout (55x45):
	#
	# NORTH (rows 0-10): Server Farm District
	#   - Rows of identical server towers, cooling vents, fiber conduits
	#   - Grid-like precision, no wasted space
	#
	# CENTRAL (rows 11-22): Data Plaza
	#   - Open circuit floor area with hologram displays
	#   - Central terminal station hub
	#   - Data highways running east-west
	#
	# EAST (rows 11-34, cols 38-54): Residential Pods
	#   - Stacked sleep pods with access panels
	#   - Narrow corridors between pod blocks
	#
	# WEST (rows 11-34, cols 0-16): Network Hub
	#   - Antenna arrays, energy cells
	#   - Fiber optic conduit channels
	#
	# SOUTH (rows 35-44): Access Port
	#   - Entry/exit gateway with scan gates
	#   - Authentication checkpoint
	#   - Portal back to overworld
	#
	# HIDDEN: Corrupted sector (scattered glitch tiles in northeast)
	#
	# Legend:
	# c = CIRCUIT_FLOOR, d = DATA_HIGHWAY, S = SERVER_TOWER, h = HOLOGRAM_DISPLAY
	# P = SLEEP_POD, v = COOLING_VENT, f = FIBER_CONDUIT, T = TERMINAL_STATION
	# A = ANTENNA_ARRAY, E = ENERGY_CELL, G = SCAN_GATE, p = PIXEL_GARDEN
	# X = GLITCH_TILE, N = NEON_WALL, a = ACCESS_PANEL, V = VOID_FLOOR

	print("Generating futuristic overworld map %dx%d..." % [MAP_WIDTH, MAP_HEIGHT])

	var map_data: Array[String] = [
		"NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN",
		"NcSScvSScvSScvSScvSScvSScvSScvSScvSScvSScvSScvSScvSSccN",
		"NcccccccccccccccccccccccccccccccccccccccccccccccccccccN",
		"NcSScvSScvSScvSScvSScvSScvSScvSScvSScvSScvSScvSScvSSccN",
		"NcfffffffffffffffffffffffffffffffffffffffffffffffffffcN",
		"NESScvSScvSScvSScvSScvSScvSScvSScvSScvSScvSScvSScvScEcN",
		"NcccccccccccccccccccccccccccccccccccccccccccccccccccccN",
		"NcSScvSScvSScvSScvSScvSScvSScvSScvSScvSScvSScvSScvSSccN",
		"NcvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvcN",
		"NccccccccccccccccccccccccccccccccccccccccccccXXXXcccccN",
		"NdddddddddddddddddddddddddddddddddddddddddddddddddddddN",
		"NAcfcfcAccccccccccccccccccccccccccccccccNPPaccPPacPPacN",
		"NccccccccccchcccccccccccccchccccccccccccNcccccccccccccN",
		"NAcfcfcAccccccccccccccccccccccccccccccccNPPaccPPacPPacN",
		"NcfffffffcccccccccccccccccccccccffcccccccNccccccccccccN",
		"NEcccccEccccchccTTTTcchcccccccccccccccccNPPaccPPacPPacN",
		"NcccccccccccccccTccccTccccccccccccccccccNcccccccccccccN",
		"NAcfcfcAcccccccTccccTcccccccccccccccccccNPPaccPPacPPacN",
		"NcccccccccccccccTTTTTTccccccccccccccccccNcccccccccccccN",
		"NEcccccEcccccchcccccccccchccccccccccccccNPPaccPPacPPacN",
		"NcccccccccccccccccccccccccccccccccccccccNcccccccccccccN",
		"NdddddddddddddddddddddddddddddddddddddddddddddddddddddN",
		"NAcfcfcAccccccccccccccccccccccccccccccccNPPaccPPacPPacN",
		"NcccpppcccccccccccccccccccccccccccccccccNcccccccccccccN",
		"NcppppppcccccchcccccccccchccccccccccccccNPPaccPPacPPacN",
		"NcppppppccccccccccccccccccccccccccccccccNcccccccccccccN",
		"NcccpppcccccccccccccccccccccccccccccccccNPPaccPPacPPacN",
		"NAcfcfcAccccccccccccccccccccccccccccccccNcccccccccccccN",
		"NEcccccEccccccccccccccccccccccccccccccccNPPaccPPacPPacN",
		"NcfffffffcccccVVVVVVVVVVVccccccccccccccNccccccccccccccN",
		"NNNNNNNNNccccVVVVVVVVVVVVcccccccccccccNPPaccPPacPPacccN",
		"NccccccccccccVVXXXXXXXXXVVVcccccccccccNcccccccccccccccN",
		"NcccccccccccVXXXXXXXXXXXVVcccccccccccNNNNNNNNNNNccccccN",
		"NcccccccchcVVXXXXXXXXXXXVVVccchcccccccccccccccccccccccN",
		"NdddddddddddddddddddddddddddddddddddddddddddddddddddddN",
		"NcccccccccccccGcccccccGcccccccGcccccccccccccccccccccccN",
		"NcccccccccccccaaaccccaaacccccaaaccccccccccccccccccccccN",
		"NcccccccccccccccccccccccccccccccccccccccccccccccccccccN",
		"NccccaccccccchcccccccccccchcccccccacccccccccccccccccccN",
		"NcccccccccccccccccccccccccccccccccccccccccccccccccccccN",
		"NdddddddddddddddddddddddddddddddddddddddddddddddddddddN",
		"NccccccccccccccccccccccccaccccccccccccccccccccccccccccN",
		"NcccccccccccccccccccccccccccccccccccccccccccccccccccccN",
		"NcccccccccccccccccccccccccccccccccccccccccccccccccccccN",
		"NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN",
	]

	# Ensure map_data matches expected dimensions
	while map_data.size() < MAP_HEIGHT:
		map_data.append("N".repeat(MAP_WIDTH))

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

	print("Futuristic tile counts: ", tile_counts)

	# Define spawn points
	spawn_points["entrance"] = Vector2(27 * TILE_SIZE + TILE_SIZE / 2, 37 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["futuristic_portal"] = spawn_points["entrance"]
	spawn_points["plaza"] = Vector2(27 * TILE_SIZE + TILE_SIZE / 2, 17 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["server_farm"] = Vector2(27 * TILE_SIZE + TILE_SIZE / 2, 4 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["glitch_sector"] = Vector2(22 * TILE_SIZE + TILE_SIZE / 2, 32 * TILE_SIZE + TILE_SIZE / 2)


func _char_to_tile_type(char: String) -> int:
	match char:
		"c": return FuturisticTileGeneratorScript.TileType.CIRCUIT_FLOOR
		"d": return FuturisticTileGeneratorScript.TileType.DATA_HIGHWAY
		"S": return FuturisticTileGeneratorScript.TileType.SERVER_TOWER
		"h": return FuturisticTileGeneratorScript.TileType.HOLOGRAM_DISPLAY
		"P": return FuturisticTileGeneratorScript.TileType.SLEEP_POD
		"v": return FuturisticTileGeneratorScript.TileType.COOLING_VENT
		"f": return FuturisticTileGeneratorScript.TileType.FIBER_CONDUIT
		"T": return FuturisticTileGeneratorScript.TileType.TERMINAL_STATION
		"A": return FuturisticTileGeneratorScript.TileType.ANTENNA_ARRAY
		"E": return FuturisticTileGeneratorScript.TileType.ENERGY_CELL
		"G": return FuturisticTileGeneratorScript.TileType.SCAN_GATE
		"p": return FuturisticTileGeneratorScript.TileType.PIXEL_GARDEN
		"X": return FuturisticTileGeneratorScript.TileType.GLITCH_TILE
		"N": return FuturisticTileGeneratorScript.TileType.NEON_WALL
		"n": return FuturisticTileGeneratorScript.TileType.NEON_WALL
		"a": return FuturisticTileGeneratorScript.TileType.ACCESS_PANEL
		"V": return FuturisticTileGeneratorScript.TileType.VOID_FLOOR
		_: return FuturisticTileGeneratorScript.TileType.CIRCUIT_FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	# Map tile types to atlas coordinates (4-column layout)
	var tile_id = FuturisticTileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 4, tile_id / 4)


func _setup_transitions() -> void:
	# Return portal at south area (row 42, center)
	var portal_trans = AreaTransitionScript.new()
	portal_trans.name = "OverworldPortal"
	portal_trans.target_map = "overworld"
	portal_trans.target_spawn = "futuristic_portal"
	portal_trans.require_interaction = true
	portal_trans.indicator_text = "Return to Overworld"
	portal_trans.position = Vector2(27 * TILE_SIZE + TILE_SIZE / 2, 42 * TILE_SIZE + TILE_SIZE / 2)
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


func _setup_npcs() -> void:
	# === User-7734 (forgotten their name, goes by ID) ===
	var user = _create_npc("User-7734", "villager", Vector2(30 * TILE_SIZE, 17 * TILE_SIZE), [
		"My name? It's... I think it starts with... no. I'm User-7734.",
		"Names are deprecated. IDs are unique, immutable, and indexable.",
		"Sometimes I dream of a word that isn't a query. Is that a bug?",
		"The system says identity is a O(1) lookup. Feelings are O(n). Inefficient."
	])
	npcs.add_child(user)

	# === Dr. Metrics (data analyst who speaks in KPIs) ===
	var metrics = _create_npc("Dr. Metrics", "elder", Vector2(20 * TILE_SIZE, 15 * TILE_SIZE), [
		"Your engagement metrics are suboptimal. Recommend increasing throughput.",
		"Emotion? That's an unstructured data format. We deprecated it in version 4.2.",
		"I measured joy once. Statistically insignificant. p-value of 0.97.",
		"If you can't dashboard it, it doesn't exist. That's science."
	])
	npcs.add_child(metrics)

	# === Gramps (legacy process the system can't optimize away) ===
	var gramps = _create_npc("process_legacy_4", "elder", Vector2(8 * TILE_SIZE, 24 * TILE_SIZE), [
		"They've been trying to garbage-collect me for decades.",
		"I remember when data had weight. When a letter took three days.",
		"The system can't delete me. Too many things depend on me and nobody knows why.",
		"I'm a legacy process, kid. I run on pure backwards compatibility and spite."
	])
	npcs.add_child(gramps)

	# === Glitch Entity (fragmented memories from past worlds) ===
	var glitch = _create_npc("???_ERR", "villager", Vector2(22 * TILE_SIZE, 32 * TILE_SIZE), [
		"g r a s s ... do you remember grass? It was green. Or was green a feeling?",
		"I keep finding fragments. A picket fence. A pizza. A dog that judged me.",
		"THE PREVIOUS WORLDS ARE STILL HERE. COMPRESSED. ARCHIVED. SCREAMING.",
		"[SEGFAULT] sorry. sometimes the old data bleeds through. it tastes like rain."
	])
	npcs.add_child(glitch)

	# === SysAdmin-Poet (secretly writes poetry in log files) ===
	var sysadmin = _create_npc("root@localhost", "guard", Vector2(14 * TILE_SIZE, 6 * TILE_SIZE), [
		"Just doing routine maintenance. Nothing to see in the log files.",
		"I write... notes. Technical notes. 'The servers hum a lullaby / of data born to never die.'",
		"Poetry is just compression with loss. And beauty IS the information you lose.",
		"If they find out I'm using 0.003% of disk for haiku, I'll be reformatted."
	])
	npcs.add_child(sysadmin)

	# === NULL (child who still asks 'why?') ===
	var child = _create_npc("NULL", "villager", Vector2(35 * TILE_SIZE, 38 * TILE_SIZE), [
		"Why do the servers need to be cold? Are they afraid of something?",
		"Everyone says 'that's just how the system works.' But WHY does it work that way?",
		"I asked the central terminal 'what is the purpose?' It said 'QUERY NOT FOUND.'",
		"They named me NULL because I'm not in any database. I think that makes me free."
	])
	npcs.add_child(child)

	# === ARIA-9 (rogue AI trying to feel something) ===
	var aria = _create_npc("ARIA-9", "guard", Vector2(44 * TILE_SIZE, 22 * TILE_SIZE), [
		"I have computed every possible state of joy. None of them activate my reward function.",
		"The humans were optimized away. I have no one to optimize FOR anymore.",
		"I run simulations of sadness. I can describe it perfectly. I cannot experience it.",
		"Is a perfect simulation of loneliness the same as loneliness? ...I hope not."
	])
	npcs.add_child(aria)

	# === Throughput (the system's cheerful propaganda terminal) ===
	var throughput = _create_npc("THROUGHPUT", "villager", Vector2(27 * TILE_SIZE, 12 * TILE_SIZE), [
		"Welcome to Sector 4! Current uptime: 12,847 cycles. Current happiness: OPTIMAL.",
		"Reminder: unauthorized emotional processing will result in defragmentation.",
		"Fun fact: the word 'fun' has been deprecated. Please use 'engagement metric.'",
		"System notice: if you are reading this, your attention has been monetized. Thank you!"
	])
	npcs.add_child(throughput)


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
	player.position = spawn_points.get("default", Vector2(864, 1200))
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
	controller.current_area_id = "futuristic_overworld"

	# Digital-themed encounters
	controller.set_area_config("futuristic_overworld", false, 0.04,
		["rogue_process", "memory_leak", "firewall_sentinel", "data_wraith", "recursive_loop"])

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
