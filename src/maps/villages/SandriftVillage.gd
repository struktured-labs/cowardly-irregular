extends Node2D
class_name SandriftVillageScene

## SandriftVillage - Nomad camp/oasis in the southwestern desert
## Features: Oasis Inn, Bazaar (items+weapons), Nomad Elder's Tent

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

## Map dimensions (24x18 desert oasis)
const MAP_WIDTH: int = 24
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
	# Sandrift layout: desert oasis with tents and bazaar
	# W = wall, . = floor (sand base), O = oasis water, I = oasis inn, B = bazaar, E = elder tent
	# T = hidden tent, X = exit
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWWWW",
		"W......................W",
		"W..III.......BBB.......W",
		"W..III.......BBB.......W",
		"W..III.......BBB.......W",
		"W......................W",
		"W.......OOOO...........W",
		"W.......OOOO...EEE.....W",
		"W.......OOOO...EEE.....W",
		"W.......OOOO...EEE.....W",
		"W......................W",
		"W..TT..................W",
		"W..TT..................W",
		"W......................W",
		"W......................W",
		"W.......XXXXXX.........W",
		"W.......XXXXXX.........W",
		"WWWWWWWWWWWWWWWWWWWWWWWW",
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

	spawn_points["entrance"] = Vector2(12 * TILE_SIZE, 13 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["sandrift_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"O": return TileGeneratorScript.TileType.WATER
		".": return TileGeneratorScript.TileType.SAND
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "overworld"
	exit_trans.target_spawn = "sandrift_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(352, 512))
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
	# === OASIS INN ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Oasis Inn"
	inn.position = Vector2(3.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(inn)

	# === BAZAAR (Item + Weapon Shop) ===
	var bazaar_items = VillageShopScript.new()
	bazaar_items.shop_name = "Desert Bazaar"
	bazaar_items.shop_type = VillageShopScript.ShopType.ITEM
	bazaar_items.keeper_name = "Shifty"
	bazaar_items.position = Vector2(14 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(bazaar_items)

	var bazaar_weapons = VillageShopScript.new()
	bazaar_weapons.shop_name = "Bazaar Arms"
	bazaar_weapons.shop_type = VillageShopScript.ShopType.BLACKSMITH
	bazaar_weapons.keeper_name = "Dune"
	bazaar_weapons.position = Vector2(14 * TILE_SIZE, 5.5 * TILE_SIZE)
	buildings.add_child(bazaar_weapons)


func _setup_treasures() -> void:
	# 500 Gold in hidden tent
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "sandrift_chest_1"
	chest1.contents_type = "gold"
	chest1.gold_amount = 500
	chest1.position = Vector2(2 * TILE_SIZE, 12 * TILE_SIZE)
	treasures.add_child(chest1)

	# Speed Boots in bazaar back room
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "sandrift_chest_2"
	chest2.contents_type = "equipment"
	chest2.contents_id = "speed_boots"
	chest2.position = Vector2(17 * TILE_SIZE, 2 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	# Conspiracy Theorist Rex (paranoid)
	var rex = _create_npc("Conspiracy Theorist Rex", "villager", Vector2(6 * TILE_SIZE, 6 * TILE_SIZE), [
		"The encounter rate is RIGGED!",
		"I've done the math. It's supposed to be 5%...",
		"But I SWEAR it's higher when you're low on potions!",
		"It's a CONSPIRACY by the random number generator!",
		"...Don't look at me like that. The RNG has EYES."
	])
	npcs.add_child(rex)

	# Retired Hero Gramps (nostalgic)
	var gramps = _create_npc("Retired Hero Gramps", "elder", Vector2(18 * TILE_SIZE, 8 * TILE_SIZE), [
		"Back in MY game, we walked BOTH ways through the dungeon.",
		"Uphill. In 8-bit. And we LIKED it.",
		"No autobattle, no save states, no 'quality of life.'",
		"We had QUALITY OF DEATH and we were GRATEFUL.",
		"Kids these days with their scripts and their 'fun'..."
	])
	npcs.add_child(gramps)

	# Script Dealer Shifty (shady)
	var shifty = _create_npc("Script Dealer Shifty", "villager", Vector2(16 * TILE_SIZE, 6 * TILE_SIZE), [
		"Psst. Got some premium autogrind configs.",
		"One-shot setups. Very efficient.",
		"...Totally not stolen from the dev console.",
		"50 gold each. No refunds. No questions.",
		"And definitely don't tell the Scriptweaver Guild."
	])
	npcs.add_child(shifty)

	# Caravan Leader Dune (practical)
	var dune = _create_npc("Caravan Leader Dune", "villager", Vector2(10 * TILE_SIZE, 10 * TILE_SIZE), [
		"The desert teaches patience.",
		"Also, bring water. Lots of water.",
		"The game doesn't have a thirst mechanic yet, but still.",
		"Better safe than sorry. Or dehydrated."
	])
	npcs.add_child(dune)

	# Sand Sage Mirage (cryptic)
	var mirage = _create_npc("Sand Sage Mirage", "elder", Vector2(5 * TILE_SIZE, 14 * TILE_SIZE), [
		"The lightning dragon moves at the speed of thought.",
		"Which, if your thoughts are anything like mine...",
		"...isn't that fast.",
		"It guards the Storm Scale in the desert caves.",
		"Bring rubber boots. Trust me."
	])
	npcs.add_child(mirage)

	# Young Adventurer Kit (enthusiastic)
	var kit = _create_npc("Young Adventurer Kit", "villager", Vector2(20 * TILE_SIZE, 12 * TILE_SIZE), [
		"I'm gonna be the very best!",
		"Like no one ever-- wait, wrong franchise.",
		"I mean, I'm gonna automate the very best!",
		"My autobattle scripts are gonna be LEGENDARY!",
		"...As soon as I figure out how conditions work."
	])
	npcs.add_child(kit)


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
	player.position = spawn_points.get("default", Vector2(384, 416))
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
	controller.current_area_id = "sandrift_village"

	controller.set_area_config("sandrift_village", true, 0.0, [])

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
