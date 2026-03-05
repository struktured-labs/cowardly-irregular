extends Node2D
class_name MapleHeightsVillageScene

## MapleHeightsVillage - Nostalgic 90s suburban neighborhood
## Features: Mom's Guest Room (Inn), Suburban Mart (Item Shop), Picket fences, Mailboxes, NPCs

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
	# Layout key:
	# W = perimeter wall
	# H = house walls (impassable)
	# I = inn (Mom's Guest Room)
	# S = shop (Suburban Mart)
	# g = grass (mowed suburban lawn)
	# p = path (sidewalk / driveway)
	# f = flower bed (garden patches)
	# e = hedge (impassable fence line)
	# d = dirt (worn areas, backyard)
	# X = exit path (sidewalk leading out)
	# Each row is exactly MAP_WIDTH (24) characters
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWWWW",
		"WggggppppppppppppggfggggW",
		"WgHHHggggfggggggfgggggggW",
		"WgHHHggggggfgggggfggfgggW",
		"WgHHHgggfggggggggggggfggW",
		"WggggppppppppppppppppgggW",
		"WggfgpgggSSSggggIIIgpfggW",
		"WgggepgggSSSggggIIIgpgggW",
		"WgfgepgggSSSggggIIIgpfggW",
		"WggggppppppppppppppppgggW",
		"WgfgggggfggHHHggggggfgggW",
		"WgggggfgggHHHgggfgggggggW",
		"WggfgggggfHHHgggggfgggfgW",
		"WgggggggggggggggggggggggW",
		"WggfggggfggggfgggggfggggW",
		"WgggggggggggggggfgggggggW",
		"WgfggggggggXXXXXXgggfgggW",
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

	spawn_points["entrance"] = Vector2(12 * TILE_SIZE, 14 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["maple_heights_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"H", "I", "S": return TileGeneratorScript.TileType.WALL
		"g": return TileGeneratorScript.TileType.VILLAGE_GRASS
		"p": return TileGeneratorScript.TileType.VILLAGE_PATH
		"d": return TileGeneratorScript.TileType.VILLAGE_DIRT
		"f": return TileGeneratorScript.TileType.VILLAGE_FLOWER
		"e": return TileGeneratorScript.TileType.VILLAGE_HEDGE
		"X": return TileGeneratorScript.TileType.VILLAGE_PATH
		_: return TileGeneratorScript.TileType.VILLAGE_GRASS


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "suburban_overworld"
	exit_trans.target_spawn = "maple_heights_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(352, 544))
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
	# === INN (Mom's Guest Room) ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Mom's Guest Room"
	inn.position = Vector2(17.5 * TILE_SIZE, 7 * TILE_SIZE)
	buildings.add_child(inn)

	# === ITEM SHOP (Suburban Mart) ===
	var shop = VillageShopScript.new()
	shop.shop_name = "Suburban Mart"
	shop.shop_type = VillageShopScript.ShopType.ITEM
	shop.keeper_name = "Donna"
	shop.position = Vector2(10 * TILE_SIZE, 7 * TILE_SIZE)
	buildings.add_child(shop)


func _setup_treasures() -> void:
	# Hidden behind the house — a forgotten lunchbox with supplies
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "maple_heights_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "potion"
	chest1.contents_amount = 2
	chest1.position = Vector2(1.5 * TILE_SIZE, 3 * TILE_SIZE)
	treasures.add_child(chest1)

	# Buried in the backyard — someone's old allowance
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "maple_heights_chest_2"
	chest2.contents_type = "gold"
	chest2.gold_amount = 80
	chest2.position = Vector2(20 * TILE_SIZE, 11 * TILE_SIZE)
	treasures.add_child(chest2)

	# Under a garden flower patch — a dusty ether
	var chest3 = TreasureChestScript.new()
	chest3.chest_id = "maple_heights_chest_3"
	chest3.contents_type = "item"
	chest3.contents_id = "ether"
	chest3.contents_amount = 1
	chest3.position = Vector2(4 * TILE_SIZE, 14 * TILE_SIZE)
	treasures.add_child(chest3)


func _setup_npcs() -> void:
	# Neighborhood Dad (BBQ tips / gameplay hints)
	var dad = _create_npc("Neighborhood Dad", "villager", Vector2(6 * TILE_SIZE, 12 * TILE_SIZE), [
		"Hey there, sport! You look like you could use some LIFE ADVICE.",
		"Always grill on medium heat. Never rush the char.",
		"Same applies to leveling up, by the way.",
		"Slow and steady. Unless you've got AUTOBATTLE running.",
		"Then honestly? Just let it rip.",
		"*flips imaginary burger*"
	])
	npcs.add_child(dad)

	# Mail Carrier (gossip / rumors)
	var mailman = _create_npc("Carriers Reg", "guard", Vector2(18 * TILE_SIZE, 4 * TILE_SIZE), [
		"Mail call! Uh... none for you, actually.",
		"But I heard some things on my route today.",
		"Old Mrs. Petrov says the caves north of here started HUMMING.",
		"The Hendersons got a new car. Very suspicious.",
		"And someone filed a complaint about reality 'feeling off'.",
		"Probably nothing. Here's a coupon."
	])
	npcs.add_child(mailman)

	# Kid on Bike (weird stuff / comedy)
	var kid = _create_npc("Tyler on Bike", "villager", Vector2(12 * TILE_SIZE, 9 * TILE_SIZE), [
		"WHOOOOOAAA—",
		"*skids to stop*",
		"Dude. DUDE. There's something in the storm drain.",
		"It blinks at me every Tuesday.",
		"I've been documenting it in a notebook.",
		"Anyway, gotta go. Mom said dinner's at 6. BYE."
	])
	npcs.add_child(kid)

	# Retired Teacher (lore about how the world changed)
	var teacher = _create_npc("Ms. Finch", "elder", Vector2(3 * TILE_SIZE, 9 * TILE_SIZE), [
		"Ah, a young traveler. Sit down. I used to teach history.",
		"Not the history in your textbooks — the REAL history.",
		"This neighborhood wasn't always... suburban.",
		"Something shifted. The aesthetics changed overnight.",
		"One morning: cobblestones and swords. Next: cul-de-sacs and minivans.",
		"I'm retired now. I don't ask questions anymore."
	])
	npcs.add_child(teacher)

	# Dog Walker (comedy relief)
	var dogwalker = _create_npc("Doug & Pretzel", "villager", Vector2(16 * TILE_SIZE, 12 * TILE_SIZE), [
		"Oh, don't mind Pretzel. He barks at adventurers.",
		"*BORK BORK BORK*",
		"He once defeated a Level 12 Goblin by sitting on it.",
		"We didn't plan that. It just happened.",
		"Anyway, he gets three walks a day and is probably stronger than you.",
		"*tail wagging intensifies*"
	])
	npcs.add_child(dogwalker)


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
	player.position = spawn_points.get("default", Vector2(384, 448))
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
	controller.current_area_id = "maple_heights_village"

	controller.set_area_config("maple_heights_village", true, 0.0, [])

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
