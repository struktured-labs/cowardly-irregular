extends Node2D
class_name NodePrimeVillageScene

## NodePrimeVillage - Digital rest stop / data hub in the futuristic overworld
## Features: Sleep.exe (inn), Cache Store (magic shop), holographic signs, geometric architecture

const TileGeneratorScript = preload("res://src/exploration/TileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")
const OverworldNPCScript = preload("res://src/exploration/OverworldNPC.gd")
const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)

## Map dimensions
const MAP_WIDTH: int = 20
const MAP_HEIGHT: int = 18
const TILE_SIZE: int = 32

## Scene components
var tile_map: TileMapLayer
var player: Node2D
var camera: Camera2D
var controller: Node
var tile_generator: Node

## Containers
var transitions: Node2D
var npcs: Node2D
var buildings: Node2D
var treasures: Node2D

## Spawn points
var spawn_points: Dictionary = {}


func _ready() -> void:
	_setup_scene()
	_generate_map()
	_setup_transitions()
	_setup_buildings()
	_setup_treasures()
	_setup_npcs()
	_setup_player()
	_setup_camera()
	_setup_controller()
	_setup_save_point()

	if SoundManager:
		SoundManager.play_area_music("village")

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

	buildings = Node2D.new()
	buildings.name = "Buildings"
	add_child(buildings)

	treasures = Node2D.new()
	treasures.name = "Treasures"
	add_child(treasures)

	npcs = Node2D.new()
	npcs.name = "NPCs"
	add_child(npcs)


func _generate_map() -> void:
	# Node Prime layout: clean geometric digital architecture
	# W = wall, . = floor (polished), p = path (grid lines)
	# I = inn (Sleep.exe), C = cache store, F = firewall barrier (wall)
	# X = exit, W = water (coolant channels)
	# Each row is exactly MAP_WIDTH (20) characters
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWW",
		"W..................W",
		"W.III....CCC.......W",
		"W.III....CCC.......W",
		"W.III....CCC.......W",
		"W..................W",
		"W...pppppppp.......W",
		"W...pppppppp.......W",
		"W..................W",
		"W..................W",
		"W..FFFF............W",
		"W..FFFF............W",
		"W..FFFF............W",
		"W..................W",
		"W..................W",
		"W......XXXXXX......W",
		"W......XXXXXX......W",
		"WWWWWWWWWWWWWWWWWWWW",
	]

	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "W"
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			if char == "X" and not spawn_points.has("exit"):
				spawn_points["exit"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)

	spawn_points["entrance"] = Vector2(10 * TILE_SIZE, 10 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["node_prime_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"F": return TileGeneratorScript.TileType.WALL
		"p": return TileGeneratorScript.TileType.VILLAGE_PATH
		"X": return TileGeneratorScript.TileType.VILLAGE_PATH
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "futuristic_overworld"
	exit_trans.target_spawn = "node_prime_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(320, 512))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


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


func _setup_buildings() -> void:
	# === SLEEP.EXE (Inn) ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Sleep.exe"
	inn.position = Vector2(2.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(inn)

	# === CACHE STORE (White Magic Shop) ===
	var cache_store = VillageShopScript.new()
	cache_store.shop_name = "Cache Store"
	cache_store.shop_type = VillageShopScript.ShopType.WHITE_MAGIC
	cache_store.keeper_name = "CACHE-1"
	cache_store.position = Vector2(10 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(cache_store)


func _setup_treasures() -> void:
	# Corrupted data packet — unclaimed memory
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "node_prime_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "ether"
	chest1.contents_amount = 2
	chest1.position = Vector2(17 * TILE_SIZE, 1.5 * TILE_SIZE)
	treasures.add_child(chest1)

	# Archived gold — old transaction log
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "node_prime_chest_2"
	chest2.contents_type = "gold"
	chest2.gold_amount = 200
	chest2.position = Vector2(17 * TILE_SIZE, 13 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	# System Admin ADMIN-01 (terminal commands)
	var admin = _create_npc("ADMIN-01", "guard", Vector2(7 * TILE_SIZE, 2 * TILE_SIZE), [
		"> QUERY: purpose_of_visit",
		"> INPUT RECEIVED: adventurer",
		"> STATUS: access_granted",
		"Proceed to designated rest nodes. Unauthorized processes will be terminated.",
		"> NOTE: the optimization layer is watching",
		"> END TRANSMISSION"
	])
	npcs.add_child(admin)

	# Debugger DEBUG-7 (glitches)
	var debugger = _create_npc("DEBUG-7", "villager", Vector2(14 * TILE_SIZE, 7 * TILE_SIZE), [
		"Oh good, you can see me. That means the render pass is working.",
		"I've been flagging anomalies in sector nine for three cycles.",
		"Something keeps rewriting the encounter tables.",
		"I call it a 'glitch.' The admin calls it 'intended behavior.'",
		"...The admin is lying.",
		"Also, your HP display flickered on my end. You might want to check that."
	])
	npcs.add_child(debugger)

	# Tourist Program TOURIST.EXE (confused)
	var tourist = _create_npc("TOURIST.EXE", "villager", Vector2(10 * TILE_SIZE, 12 * TILE_SIZE), [
		"ERROR: context_mismatch — expected 'scenic overlook', received 'data hub'",
		"I booked a package tour. The brochure said 'breathtaking vistas.'",
		"This is a floor. It is very flat. I am not taking breath.",
		"...Is this the scenic route?",
		"I will leave a review. It will be two stars.",
		"One star for the floor. One star for you. You seem nice."
	])
	npcs.add_child(tourist)

	# Data Archivist (lore keeper)
	var archivist = _create_npc("Data Archivist", "elder", Vector2(3 * TILE_SIZE, 9 * TILE_SIZE), [
		"Before the optimization, this place had a name.",
		"A real name. Not a designation.",
		"People lived here. They had routines that were not mandated.",
		"The system said efficiency required... simplification.",
		"I kept the old records. In here.",
		"*taps head* They cannot optimize what they cannot index."
	])
	npcs.add_child(archivist)

	# Firewall Guard (blocks path, future content hint)
	var firewall = _create_npc("FIREWALL-ALPHA", "guard", Vector2(3 * TILE_SIZE, 13 * TILE_SIZE), [
		"HALT. Access to sector twelve is restricted.",
		"Clearance level required: DELTA.",
		"Your current clearance level: NONE.",
		"When you have acquired sufficient system permissions, return.",
		"...I will be here. I am always here.",
		"I have been here for four hundred cycles. I am fine. Everything is fine."
	])
	npcs.add_child(firewall)


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
	player.position = spawn_points.get("default", Vector2(320, 320))
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
	controller.encounter_enabled = false
	controller.current_area_id = "node_prime_village"

	controller.set_area_config("node_prime_village", true, 0.0, [])

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


func _setup_save_point() -> void:
	var save_pt = SavePoint.new()
	save_pt.position = Vector2(8 * TILE_SIZE, 8 * TILE_SIZE)
	save_pt.save_requested.connect(_on_save_requested)
	add_child(save_pt)


func _on_save_requested() -> void:
	if SaveSystem and SaveSystem.has_method("quick_save"):
		SaveSystem.quick_save()
		print("[SAVE] Quick save triggered from Node Prime save point")
