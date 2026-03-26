extends Node2D
class_name RivetRowVillageScene

## RivetRowVillage - Workers' settlement on factory outskirts
## Features: Workers' Barracks, Company Store, canteen, smokestacks, graffiti wall

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
const MAP_WIDTH: int = 22
const MAP_HEIGHT: int = 16
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
	# Rivet Row layout: industrial workers' settlement
	# W = perimeter wall, . = floor (concrete), d = village dirt (yard)
	# I = inn (barracks), G = general store (company store), C = canteen
	# V = lava channel (industrial runoff), X = exit
	# Each row is exactly MAP_WIDTH (22) characters
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWW",
		"W....................W",
		"W.III..ddd..GGG......W",
		"W.III..ddd..GGG......W",
		"W.III..ddd..GGG......W",
		"W....................W",
		"W....VVVVVVV.........W",
		"W....VVVVVVV.........W",
		"W....................W",
		"W.CCC................W",
		"W.CCC................W",
		"W.CCC................W",
		"W....................W",
		"W.......XXXXXX.......W",
		"W.......XXXXXX.......W",
		"WWWWWWWWWWWWWWWWWWWWWW",
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

	spawn_points["entrance"] = Vector2(11 * TILE_SIZE, 10 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["rivet_row_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"V": return TileGeneratorScript.TileType.LAVA
		"d": return TileGeneratorScript.TileType.VILLAGE_DIRT
		"X": return TileGeneratorScript.TileType.VILLAGE_PATH
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "industrial_overworld"
	exit_trans.target_spawn = "rivet_row_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(352, 448))
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
	# === WORKERS' BARRACKS (Inn) ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Workers' Barracks"
	inn.position = Vector2(2.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(inn)

	# === COMPANY STORE (Item Shop) ===
	var store = VillageShopScript.new()
	store.shop_name = "Company Store"
	store.shop_type = VillageShopScript.ShopType.ITEM
	store.keeper_name = "Overseer Brack"
	store.position = Vector2(12.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(store)


func _setup_treasures() -> void:
	# Contraband stash behind the barracks
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "rivet_row_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "potion"
	chest1.contents_amount = 2
	chest1.position = Vector2(1.5 * TILE_SIZE, 1.5 * TILE_SIZE)
	treasures.add_child(chest1)

	# Union dues hidden under canteen floorboard
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "rivet_row_chest_2"
	chest2.contents_type = "gold"
	chest2.gold_amount = 80
	chest2.position = Vector2(1.5 * TILE_SIZE, 11 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	# Shift Foreman (work-related hints)
	var foreman = _create_npc("Shift Foreman Grix", "guard", Vector2(8 * TILE_SIZE, 3 * TILE_SIZE), [
		"Shift starts when the whistle blows. No excuses.",
		"We run three shifts here: early, late, and 'extended late'.",
		"Management calls it 'optimization.' I call it Tuesday.",
		"If your HP drops below twenty-five percent, REST. That's an ORDER.",
		"A dead worker is an inefficient worker. And inefficiency is UNACCEPTABLE."
	])
	npcs.add_child(foreman)

	# Union Rep (subversive)
	var union_rep = _create_npc("Union Rep Voss", "villager", Vector2(17 * TILE_SIZE, 9 * TILE_SIZE), [
		"*whispers* Keep your voice down.",
		"The foreman tracks output. Every action you take is LOGGED.",
		"They called it 'optimization gone wrong' — I call it working as designed.",
		"They automate us. We automate back. Fair is fair.",
		"If you find out how to edit the shift log... come find me.",
		"I'll make it worth your while."
	])
	npcs.add_child(union_rep)

	# Canteen Cook (heals party, humor)
	var cook = _create_npc("Canteen Cook Murl", "villager", Vector2(3 * TILE_SIZE, 11 * TILE_SIZE), [
		"Welcome to the canteen! Today's special is Mystery Stew.",
		"Yesterday's special was also Mystery Stew.",
		"Every day is Mystery Stew. We haven't solved the mystery yet.",
		"...Actually, eat up. Your whole party looks terrible.",
		"*the stew restores the party's spirits, if not their dignity*"
	])
	npcs.add_child(cook)

	# Factory Kid (aspirational)
	var kid = _create_npc("Factory Kid Pell", "villager", Vector2(15 * TILE_SIZE, 6 * TILE_SIZE), [
		"I'm gonna be Employee of the Month someday!",
		"I swept the east corridor TWICE yesterday.",
		"The quota is once. I am TWICE the worker.",
		"Management gave me a certificate. It said 'satisfactory.'",
		"...I'm going to frame it."
	])
	npcs.add_child(kid)

	# Graffiti Wall (interactable object)
	var graffiti = _create_npc("Graffiti Wall", "villager", Vector2(19 * TILE_SIZE, 2 * TILE_SIZE), [
		"Scrawled on the wall:",
		"'AUTOMATE THE FOREMAN'",
		"'QUOTA IS A LIE'",
		"'THE CAVE DOESN'T LOG YOUR HOURS'",
		"'EMPLOYEE OF THE MONTH IS RIGGED — ASK VOSS'",
		"Someone has drawn a surprisingly accurate map of the overworld. In crayon."
	])
	npcs.add_child(graffiti)


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
	player.position = spawn_points.get("default", Vector2(352, 320))
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
	controller.current_area_id = "rivet_row_village"

	controller.set_area_config("rivet_row_village", true, 0.0, [])

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
	save_pt.position = Vector2(10 * TILE_SIZE, 6 * TILE_SIZE)
	save_pt.save_requested.connect(_on_save_requested)
	add_child(save_pt)


func _on_save_requested() -> void:
	if SaveSystem and SaveSystem.has_method("quick_save"):
		SaveSystem.quick_save()
		print("[SAVE] Quick save triggered from Rivet Row save point")
