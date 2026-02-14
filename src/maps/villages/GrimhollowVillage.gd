extends Node2D
class_name GrimhollowVillageScene

## GrimhollowVillage - Haunted hamlet in the northeastern swamps
## Features: Restless Inn, Cursed Curios (items), Decrepit Chapel

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

## Map dimensions (20x16 swamp hamlet)
const MAP_WIDTH: int = 20
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
	# Grimhollow layout: dark swamp hamlet
	# W = wall, . = floor, S = swamp pools, R = restless inn, C = cursed curios, D = decrepit chapel
	# G = graveyard area, X = exit
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWW",
		"W..................W",
		"W..RRR....DDD......W",
		"W..RRR....DDD......W",
		"W..RRR....DDD......W",
		"W..................W",
		"W.....SS.....CCC...W",
		"W.....SS.....CCC...W",
		"W.....SS.....CCC...W",
		"W..................W",
		"W..GGG.............W",
		"W..GGG.............W",
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

	spawn_points["entrance"] = Vector2(10 * TILE_SIZE, 11 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["grimhollow_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"S": return TileGeneratorScript.TileType.SWAMP
		"G": return TileGeneratorScript.TileType.DARK_GROUND
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "overworld"
	exit_trans.target_spawn = "grimhollow_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(288, 448))
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
	# === RESTLESS INN ===
	var inn = VillageInnScript.new()
	inn.inn_name = "The Restless Inn"
	inn.position = Vector2(3.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(inn)

	# === CURSED CURIOS (Item Shop) ===
	var curios = VillageShopScript.new()
	curios.shop_name = "Cursed Curios"
	curios.shop_type = VillageShopScript.ShopType.ITEM
	curios.keeper_name = "Mort"
	curios.position = Vector2(15 * TILE_SIZE, 7 * TILE_SIZE)
	buildings.add_child(curios)

	# === DECREPIT CHAPEL (Magic Shop) ===
	var chapel = VillageShopScript.new()
	chapel.shop_name = "Decrepit Chapel"
	chapel.shop_type = VillageShopScript.ShopType.BLACK_MAGIC
	chapel.keeper_name = "Sister Shadow"
	chapel.position = Vector2(11 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(chapel)


func _setup_treasures() -> void:
	# Phoenix Down in cemetery
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "grimhollow_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "phoenix_down"
	chest1.contents_amount = 1
	chest1.position = Vector2(1.5 * TILE_SIZE, 11 * TILE_SIZE)
	treasures.add_child(chest1)

	# Shadow Ring behind chapel
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "grimhollow_chest_2"
	chest2.contents_type = "equipment"
	chest2.contents_id = "shadow_ring"
	chest2.position = Vector2(14 * TILE_SIZE, 2 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	# Fortune Teller Madame Hex (dramatic)
	var hex = _create_npc("Madame Hex", "elder", Vector2(8 * TILE_SIZE, 5 * TILE_SIZE), [
		"I see your future...",
		"BOSS FIGHT!",
		"...That's all futures, really.",
		"The cards never lie. They just exaggerate dramatically.",
		"For 50 gold I can tell you which element to use. For free? Good luck."
	])
	npcs.add_child(hex)

	# Undead Shopkeeper Mort (deadpan)
	var mort = _create_npc("Undead Shopkeeper Mort", "villager", Vector2(16 * TILE_SIZE, 5 * TILE_SIZE), [
		"Being dead is great for overhead.",
		"No rent, no food costs. 10/10 would die again.",
		"I used to be an adventurer. Then I died.",
		"But the shop needed a keeper, so here I am. Un-retired."
	])
	npcs.add_child(mort)

	# Creepy Child Wednesday (meta-horror)
	var wednesday = _create_npc("Creepy Child Wednesday", "villager", Vector2(6 * TILE_SIZE, 9 * TILE_SIZE), [
		"I can see the save file from here.",
		"There's something... WRITTEN between the bytes.",
		"Can you hear it too?",
		"The data whispers your name. And your playtime.",
		"...It says you've been playing for a while. Maybe take a break?"
	])
	npcs.add_child(wednesday)

	# Ghost Barkeep Claude (friendly)
	var claude = _create_npc("Ghost Barkeep Claude", "villager", Vector2(4 * TILE_SIZE, 7 * TILE_SIZE), [
		"The usual? One Spectral Ale?",
		"...Oh right, you're alive. That limits the menu.",
		"I can offer water. Ghostly water. It's just regular water.",
		"Being dead has its perks. I never forget an order. Or close up shop."
	])
	npcs.add_child(claude)

	# Nervous Gravedigger Earl (anxious)
	var earl = _create_npc("Gravedigger Earl", "villager", Vector2(3 * TILE_SIZE, 12 * TILE_SIZE), [
		"Please don't use Raise on the graves.",
		"Last time someone did that, we had a UNION issue.",
		"The undead demanded dental coverage.",
		"Do you know how much dental costs for someone with NO TEETH?!"
	])
	npcs.add_child(earl)

	# Swamp Witch Murk (warnings)
	var murk = _create_npc("Swamp Witch Murk", "elder", Vector2(12 * TILE_SIZE, 10 * TILE_SIZE), [
		"The shadow dragon speaks in null pointers and broken promises.",
		"Fun at parties though.",
		"It lives in the darkest cave to the northeast.",
		"If you hear binary in your dreams... it's already too late.",
		"...Just kidding. Probably."
	])
	npcs.add_child(murk)


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
	player.position = spawn_points.get("default", Vector2(320, 352))
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
	controller.current_area_id = "grimhollow_village"

	controller.set_area_config("grimhollow_village", true, 0.0, [])

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
