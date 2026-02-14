extends Node2D
class_name FrostholdVillageScene

## FrostholdVillage - Nordic outpost in the frozen northwest
## Features: Nordic Lodge (inn), Fur Trader (items), Ice Chapel (magic shop)

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

## Map dimensions (22x18 ice village)
const MAP_WIDTH: int = 22
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
	# Frosthold layout: stone walls, ice terrain
	# W = wall, . = floor, L = lodge (inn), F = fur trader, C = chapel
	# I = ice/snow decoration, X = exit
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWW",
		"W....................W",
		"W..LLL......CCC.....W",
		"W..LLL......CCC.....W",
		"W..LLL......CCC.....W",
		"W....................W",
		"W......IIII..........W",
		"W......IIII..FFF.....W",
		"W......IIII..FFF.....W",
		"W......IIII..FFF.....W",
		"W....................W",
		"W....................W",
		"W....................W",
		"W....................W",
		"W....................W",
		"W.....XXXXXX.........W",
		"W.....XXXXXX.........W",
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

	spawn_points["entrance"] = Vector2(8 * TILE_SIZE, 13 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["frosthold_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"I": return TileGeneratorScript.TileType.ICE
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "overworld"
	exit_trans.target_spawn = "frosthold_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(256, 512))
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
	# === NORDIC LODGE (Inn) ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Nordic Lodge"
	inn.position = Vector2(3.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(inn)

	# === FUR TRADER (Item Shop) ===
	var fur_trader = VillageShopScript.new()
	fur_trader.shop_name = "Fur Trader"
	fur_trader.shop_type = VillageShopScript.ShopType.ITEM
	fur_trader.keeper_name = "Helga"
	fur_trader.position = Vector2(15 * TILE_SIZE, 8 * TILE_SIZE)
	buildings.add_child(fur_trader)

	# === ICE CHAPEL (Magic Shop) ===
	var chapel = VillageShopScript.new()
	chapel.shop_name = "Ice Chapel"
	chapel.shop_type = VillageShopScript.ShopType.WHITE_MAGIC
	chapel.keeper_name = "Brother Frost"
	chapel.position = Vector2(14 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(chapel)


func _setup_treasures() -> void:
	# 2x Hi-Potion behind lodge
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "frosthold_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "hi_potion"
	chest1.contents_amount = 2
	chest1.position = Vector2(1.5 * TILE_SIZE, 5 * TILE_SIZE)
	treasures.add_child(chest1)

	# Ice Charm in chapel corner
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "frosthold_chest_2"
	chest2.contents_type = "equipment"
	chest2.contents_id = "ice_charm"
	chest2.position = Vector2(17 * TILE_SIZE, 2 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	# Old Man Björn (exposition)
	var bjorn = _create_npc("Old Man Björn", "elder", Vector2(6 * TILE_SIZE, 6 * TILE_SIZE), [
		"The ice dragon Glacius has been here since the first compile...",
		"I mean, the first winter.",
		"It guards the frozen peak with breath that freezes code— er, BONE.",
		"If you seek the Ice Scale, you'll need more than warm clothes."
	])
	npcs.add_child(bjorn)

	# Guard Ingrid (pessimistic)
	var ingrid = _create_npc("Guard Ingrid", "guard", Vector2(8 * TILE_SIZE, 14 * TILE_SIZE), [
		"Turn back. You're clearly not high enough level.",
		"I can see your stats from here.",
		"...What? No, I can't literally SEE them.",
		"It's a figure of speech. But seriously, you look weak."
	])
	npcs.add_child(ingrid)

	# Hermit Kael (autobattle)
	var kael = _create_npc("Hermit Kael", "villager", Vector2(10 * TILE_SIZE, 10 * TILE_SIZE), [
		"I automated my entire LIFE, friend.",
		"Breakfast? Automated. Conversations? Scripted.",
		"Do I regret it? ...That's also scripted.",
		"Press F5 to open the Autobattle Editor. Trust me.",
		"Once you automate combat, you'll want to automate EVERYTHING."
	])
	npcs.add_child(kael)

	# Merchant Helga (shivering)
	var helga = _create_npc("Merchant Helga", "villager", Vector2(16 * TILE_SIZE, 11 * TILE_SIZE), [
		"B-buy something warm, please.",
		"The d-developer forgot to add heating.",
		"I've been standing here since the scene loaded.",
		"Do you know how COLD a 32x32 tile gets?!"
	])
	npcs.add_child(helga)

	# Scholar Fynn (lore)
	var fynn = _create_npc("Scholar Fynn", "villager", Vector2(4 * TILE_SIZE, 11 * TILE_SIZE), [
		"Legend says four dragons guard four elemental scales.",
		"Collect them all and... actually, nobody remembers what happens next.",
		"The ancient texts just say 'TODO: implement endgame.'",
		"I'm sure it'll be patched eventually."
	])
	npcs.add_child(fynn)

	# Child Lumi (cheerful)
	var lumi = _create_npc("Child Lumi", "villager", Vector2(12 * TILE_SIZE, 4 * TILE_SIZE), [
		"I built a snowman! I named him 'Null Reference.'",
		"He keeps crashing.",
		"Every time I try to give him a nose, he throws an exception!",
		"Mom says I should try-catch him but that sounds mean."
	])
	npcs.add_child(lumi)


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
	player.position = spawn_points.get("default", Vector2(256, 416))
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
	controller.current_area_id = "frosthold_village"

	controller.set_area_config("frosthold_village", true, 0.0, [])

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
