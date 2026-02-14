extends Node2D
class_name IronhavenVillageScene

## IronhavenVillage - Industrial frontier forge town in the volcanic southeast
## Features: Ironclad Inn, Master Forge (weapons), Steamworks (unique), Miner's Tavern

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

## Map dimensions (25x20 industrial town)
const MAP_WIDTH: int = 25
const MAP_HEIGHT: int = 20
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
	# Ironhaven layout: industrial forge town with lava channels
	# W = wall, . = floor, V = lava, I = ironclad inn, F = master forge
	# S = steamworks, M = miner's tavern, X = exit
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWWWWW",
		"W.......................W",
		"W..III.....FFF..........W",
		"W..III.....FFF...SSS....W",
		"W..III.....FFF...SSS....W",
		"W..........FFF...SSS....W",
		"W.......................W",
		"W.........VVV...........W",
		"W.........VVV...........W",
		"W.........VVV...........W",
		"W.......................W",
		"W..MMM..................W",
		"W..MMM..................W",
		"W..MMM..................W",
		"W.......................W",
		"W.......................W",
		"W.......................W",
		"W........XXXXXX.........W",
		"W........XXXXXX.........W",
		"WWWWWWWWWWWWWWWWWWWWWWWWW",
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

	spawn_points["entrance"] = Vector2(12 * TILE_SIZE, 15 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["ironhaven_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"V": return TileGeneratorScript.TileType.LAVA
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "overworld"
	exit_trans.target_spawn = "ironhaven_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(384, 576))
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
	# === IRONCLAD INN ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Ironclad Inn"
	inn.position = Vector2(3.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(inn)

	# === MASTER FORGE (Weapon Shop) ===
	var forge = VillageShopScript.new()
	forge.shop_name = "Master Forge"
	forge.shop_type = VillageShopScript.ShopType.BLACKSMITH
	forge.keeper_name = "Magda"
	forge.position = Vector2(12.5 * TILE_SIZE, 4 * TILE_SIZE)
	buildings.add_child(forge)

	# === STEAMWORKS (Item Shop - unique tech items) ===
	var steamworks = VillageShopScript.new()
	steamworks.shop_name = "Steamworks"
	steamworks.shop_type = VillageShopScript.ShopType.ITEM
	steamworks.keeper_name = "Dr. Cog"
	steamworks.position = Vector2(20 * TILE_SIZE, 4 * TILE_SIZE)
	buildings.add_child(steamworks)

	# === MINER'S TAVERN ===
	var tavern = VillageInnScript.new()
	tavern.inn_name = "Miner's Tavern"
	tavern.position = Vector2(3.5 * TILE_SIZE, 12 * TILE_SIZE)
	buildings.add_child(tavern)


func _setup_treasures() -> void:
	# Iron Shield near forge
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "ironhaven_chest_1"
	chest1.contents_type = "equipment"
	chest1.contents_id = "iron_shield"
	chest1.position = Vector2(10 * TILE_SIZE, 2 * TILE_SIZE)
	treasures.add_child(chest1)

	# 3x Hi-Potion in tavern cellar
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "ironhaven_chest_2"
	chest2.contents_type = "item"
	chest2.contents_id = "hi_potion"
	chest2.contents_amount = 3
	chest2.position = Vector2(1.5 * TILE_SIZE, 14 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	# Blacksmith Magda (eager)
	var magda = _create_npc("Blacksmith Magda", "villager", Vector2(14 * TILE_SIZE, 6 * TILE_SIZE), [
		"Dragon scales, you say?",
		"Oh, I could forge LEGENDARY equipment from those.",
		"Come back with four. Bring receipts.",
		"I don't accept scales of questionable provenance.",
		"Last guy brought me lizard skin. LIZARD. The audacity."
	])
	npcs.add_child(magda)

	# War Veteran Koss (mysterious)
	var koss = _create_npc("War Veteran Koss", "guard", Vector2(18 * TILE_SIZE, 10 * TILE_SIZE), [
		"I've seen what lies beyond the southern gate.",
		"Concrete. Streetlights. ...Saxophone music.",
		"The future is WEIRD.",
		"If you go south, bring earplugs.",
		"And maybe a map. The streets don't make sense."
	])
	npcs.add_child(koss)

	# Automation Researcher Dr. Cog (philosophical)
	var cog = _create_npc("Dr. Cog", "villager", Vector2(21 * TILE_SIZE, 6 * TILE_SIZE), [
		"What if the NPCs could automate too?",
		"What if I already HAVE and this dialogue is just my script running?",
		"...Hypothesis confirmed.",
		"I've been running my own autobattle scripts for YEARS.",
		"My dialogue tree is fully optimized. You're in the fast path."
	])
	npcs.add_child(cog)

	# Miner Pete (tired)
	var pete = _create_npc("Miner Pete", "villager", Vector2(6 * TILE_SIZE, 10 * TILE_SIZE), [
		"The volcanic caves are brutal.",
		"My pickaxe melted. MY BOOTS melted.",
		"The dragon just laughed.",
		"It breathes fire AND sarcasm.",
		"I'm taking a LONG vacation."
	])
	npcs.add_child(pete)

	# Apprentice Bolt (eager)
	var bolt = _create_npc("Apprentice Bolt", "villager", Vector2(8 * TILE_SIZE, 14 * TILE_SIZE), [
		"I'm building a machine that plays the game FOR you!",
		"...Wait, isn't that just autobattle?",
		"Oh NO.",
		"My entire thesis is redundant.",
		"Well, at least mine has GEARS. That counts for something, right?"
	])
	npcs.add_child(bolt)

	# Barkeep Ember (warm)
	var ember = _create_npc("Barkeep Ember", "villager", Vector2(4 * TILE_SIZE, 14 * TILE_SIZE), [
		"Welcome to the last inn before the fire cave.",
		"We serve drinks and existential dread.",
		"Both are on the house.",
		"The special today is 'Lava Lager.' It's... warm.",
		"Like, REALLY warm. We haven't figured out cooling yet."
	])
	npcs.add_child(ember)

	# Mysterious Stranger (foreshadowing)
	var stranger = _create_npc("Mysterious Stranger", "villager", Vector2(20 * TILE_SIZE, 16 * TILE_SIZE), [
		"The portal to the south...",
		"It leads to a place where magic runs on coal...",
		"And dreams run on rails.",
		"Are you ready?",
		"...Don't answer that. It was rhetorical. Also, probably no."
	])
	npcs.add_child(stranger)


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
	player.position = spawn_points.get("default", Vector2(384, 480))
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
	controller.current_area_id = "ironhaven_village"

	controller.set_area_config("ironhaven_village", true, 0.0, [])

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
