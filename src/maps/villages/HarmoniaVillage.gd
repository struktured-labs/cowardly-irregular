extends Node2D
class_name HarmoniaVillageScene

## HarmoniaVillage - Starter village with full JRPG amenities
## Features: Inn, Shops, Bar with dancer, Fountain, Treasures, NPCs

const TileGeneratorScript = preload("res://src/exploration/TileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")
const OverworldNPCScript = preload("res://src/exploration/OverworldNPC.gd")
const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const VillageBarScript = preload("res://src/exploration/VillageBar.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")
const VillageFountainScript = preload("res://src/exploration/VillageFountain.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)

## Map dimensions (expanded for full village)
const MAP_WIDTH: int = 30
const MAP_HEIGHT: int = 25
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

	# Start village music
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
	# Expanded village layout:
	# W = wall, . = floor, H = house, F = fountain area
	# I = inn, A = armor shop, P = weapon shop, G = general store, B = bar
	# X = exit
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
		"W............................W",
		"W..HHH..........AAA..........W",
		"W..HHH..........AAA....PPP...W",
		"W..HHH..........AAA....PPP...W",
		"W............................W",
		"W........FFFFFF..............W",
		"W..III...FFFFFF....GGG.......W",
		"W..III...FFFFFF....GGG.......W",
		"W..III...FFFFFF....GGG.......W",
		"W........FFFFFF..............W",
		"W............................W",
		"W............................W",
		"W..HHH...................BBB.W",
		"W..HHH...................BBB.W",
		"W..HHH...................BBB.W",
		"W............................W",
		"W....HHH.....................W",
		"W....HHH.....................W",
		"W....HHH.....................W",
		"W............................W",
		"W..........XXXXXX............W",
		"W..........XXXXXX............W",
		"W............................W",
		"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"
	]

	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "W"
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			# Mark special locations
			if char == "X" and not spawn_points.has("exit"):
				spawn_points["exit"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)

	# Entrance spawn (safe distance from exit)
	spawn_points["entrance"] = Vector2(15 * TILE_SIZE, 18 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	# Bar exit spawn (in front of The Dancing Tonberry)
	spawn_points["bar_exit"] = Vector2(26 * TILE_SIZE, 16 * TILE_SIZE)


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"F": return TileGeneratorScript.TileType.WATER  # Fountain water effect
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 4, tile_id / 4)


func _setup_transitions() -> void:
	# Exit back to overworld
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "overworld"
	exit_trans.target_spawn = "village_entrance"
	exit_trans.require_interaction = false  # Auto-exit on touch
	exit_trans.position = spawn_points.get("exit", Vector2(480, 704))
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
	# === INN ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Sleepy Slime Inn"
	inn.position = Vector2(3.5 * TILE_SIZE, 8 * TILE_SIZE)
	buildings.add_child(inn)

	# === WEAPON SHOP ===
	var weapon_shop = VillageShopScript.new()
	weapon_shop.shop_name = "Ironclad Arms"
	weapon_shop.shop_type = VillageShopScript.ShopType.WEAPON
	weapon_shop.keeper_name = "Brutus"
	weapon_shop.position = Vector2(25 * TILE_SIZE, 3.5 * TILE_SIZE)
	buildings.add_child(weapon_shop)

	# === ARMOR SHOP ===
	var armor_shop = VillageShopScript.new()
	armor_shop.shop_name = "Guardian's Garb"
	armor_shop.shop_type = VillageShopScript.ShopType.ARMOR
	armor_shop.keeper_name = "Helga"
	armor_shop.position = Vector2(16 * TILE_SIZE, 3.5 * TILE_SIZE)
	buildings.add_child(armor_shop)

	# === ITEM SHOP ===
	var item_shop = VillageShopScript.new()
	item_shop.shop_name = "Mystic Remedies"
	item_shop.shop_type = VillageShopScript.ShopType.ITEM
	item_shop.keeper_name = "Willow"
	item_shop.position = Vector2(22 * TILE_SIZE, 8 * TILE_SIZE)
	buildings.add_child(item_shop)

	# === ACCESSORY SHOP ===
	var accessory_shop = VillageShopScript.new()
	accessory_shop.shop_name = "Glittering Baubles"
	accessory_shop.shop_type = VillageShopScript.ShopType.ACCESSORY
	accessory_shop.keeper_name = "Opal"
	accessory_shop.position = Vector2(10 * TILE_SIZE, 3.5 * TILE_SIZE)
	buildings.add_child(accessory_shop)

	# === BAR ===
	var bar = VillageBarScript.new()
	bar.bar_name = "The Dancing Tonberry"
	bar.position = Vector2(26 * TILE_SIZE, 14.5 * TILE_SIZE)
	bar.transition_triggered.connect(_on_transition_triggered)
	buildings.add_child(bar)

	# === FOUNTAIN ===
	var fountain = VillageFountainScript.new()
	fountain.fountain_name = "Harmony Fountain"
	fountain.tree_type = "cherry"
	fountain.position = Vector2(11 * TILE_SIZE, 8 * TILE_SIZE)
	buildings.add_child(fountain)


func _setup_treasures() -> void:
	# Hidden treasure behind house 1 (top left)
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "harmonia_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "potion"
	chest1.contents_amount = 3
	chest1.position = Vector2(1.5 * TILE_SIZE, 4 * TILE_SIZE)
	treasures.add_child(chest1)

	# Treasure near bar
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "harmonia_chest_2"
	chest2.contents_type = "gold"
	chest2.gold_amount = 150
	chest2.position = Vector2(28 * TILE_SIZE, 13 * TILE_SIZE)
	treasures.add_child(chest2)

	# Treasure behind bottom left house
	var chest3 = TreasureChestScript.new()
	chest3.chest_id = "harmonia_chest_3"
	chest3.contents_type = "item"
	chest3.contents_id = "ether"
	chest3.contents_amount = 2
	chest3.position = Vector2(1.5 * TILE_SIZE, 20 * TILE_SIZE)
	treasures.add_child(chest3)

	# Equipment treasure (hidden corner)
	var chest4 = TreasureChestScript.new()
	chest4.chest_id = "harmonia_chest_4"
	chest4.contents_type = "equipment"
	chest4.contents_id = "lucky_charm"
	chest4.position = Vector2(28 * TILE_SIZE, 1.5 * TILE_SIZE)
	treasures.add_child(chest4)


func _setup_npcs() -> void:
	# === STORY/LORE NPCs ===

	# Village Elder (near fountain)
	var elder = _create_npc("Elder Theron", "elder", Vector2(8 * TILE_SIZE, 6 * TILE_SIZE), [
		"Welcome to Harmonia Village, young adventurer.",
		"Our peaceful village has stood for generations...",
		"But dark rumors spread from the Whispering Cave to the north.",
		"Many brave souls have ventured there... few return.",
		"If you seek glory, be warned: the cave adapts to those who challenge it.",
		"May the light guide your path."
	])
	npcs.add_child(elder)

	# === AUTOBATTLE HINT NPCs ===

	# Scholar (hints about automation)
	var scholar = _create_npc("Scholar Milo", "villager", Vector2(16 * TILE_SIZE, 6 * TILE_SIZE), [
		"Ah, a fellow seeker of knowledge!",
		"I've been studying an ancient art called 'AUTOBATTLE'.",
		"Press F5 or START to open the Autobattle Editor!",
		"You can create rules like 'If HP < 25%, use Potion'.",
		"The system executes your script when it's your turn.",
		"It's not cheating - it's ENLIGHTENMENT!"
	])
	npcs.add_child(scholar)

	# Retired Adventurer (autogrind hints)
	var retired = _create_npc("Greta the Grey", "elder", Vector2(4 * TILE_SIZE, 15 * TILE_SIZE), [
		"*cough* In my day, we ground levels by HAND!",
		"But these young folk... they let the game PLAY ITSELF.",
		"Press F6 or Select to toggle autobattle for everyone!",
		"Some say it's lazy. I say it's WISDOM.",
		"Why waste time when monsters await?",
		"Just... be careful in that cave. It... adapts."
	])
	npcs.add_child(retired)

	# === HUMOROUS NPCs ===

	# Existential Villager
	var existential = _create_npc("Phil the Lost", "villager", Vector2(20 * TILE_SIZE, 16 * TILE_SIZE), [
		"Do you ever wonder if we're just... NPCs?",
		"Standing here... saying the same things...",
		"Waiting for someone to talk to us...",
		"What if there's someone CONTROLLING us?!",
		"...",
		"Nah, that's ridiculous. Carry on!"
	])
	npcs.add_child(existential)

	# Chicken Chaser wannabe
	var chicken = _create_npc("Cluck Norris", "villager", Vector2(6 * TILE_SIZE, 19 * TILE_SIZE), [
		"HAVE YOU SEEN MY CHICKENS?!",
		"They escaped during the last monster attack!",
		"I had SEVENTEEN of them!",
		"...What do you mean 'wrong game'?",
		"Every game needs a chicken guy!",
		"*bawk bawk*"
	])
	npcs.add_child(chicken)

	# Fourth Wall Breaker
	var meta = _create_npc("???", "villager", Vector2(25 * TILE_SIZE, 20 * TILE_SIZE), [
		"Psst... hey... over here...",
		"I know things. SECRET things.",
		"Like how the save file is just JSON.",
		"Or how the monsters in the cave scale with you.",
		"The more you fight, the STRONGER they get.",
		"But also... so do YOU. Funny how that works."
	])
	npcs.add_child(meta)

	# Sleeping NPC
	var sleepy = _create_npc("Zzz...", "villager", Vector2(3.5 * TILE_SIZE, 3 * TILE_SIZE), [
		"Zzz...",
		"Zzz... five more minutes...",
		"Zzz... no... I don't want to fight slimes...",
		"Zzz... automate... the farming...",
		"Zzz... *snore* ...",
		"ZZZ!!!"
	])
	npcs.add_child(sleepy)

	# === HELPFUL NPCs ===

	# Guard near exit
	var guard = _create_npc("Guard Boris", "guard", Vector2(8 * TILE_SIZE, 21 * TILE_SIZE), [
		"Halt! ...Oh, you're heading OUT? Carry on then.",
		"I'm here to keep monsters from getting IN.",
		"The overworld isn't too dangerous...",
		"Slimes, bats, goblins - nothing you can't handle.",
		"But the cave... *shudder* ...don't ask."
	])
	npcs.add_child(guard)

	# Kid by fountain
	var kid = _create_npc("Young Pip", "villager", Vector2(16 * TILE_SIZE, 10 * TILE_SIZE), [
		"Wow! A real adventurer!",
		"I'm gonna be just like you when I grow up!",
		"I practice swinging my stick every day!",
		"Mom says I can't go near the cave though.",
		"Something about 'infinite loops'?",
		"Whatever that means!"
	])
	npcs.add_child(kid)

	# Flower Lady
	var flower = _create_npc("Flora", "villager", Vector2(17 * TILE_SIZE, 12 * TILE_SIZE), [
		"*humming* La la la~",
		"Oh! Would you like to buy some flowers?",
		"...I don't actually sell them. Just ask.",
		"They remind me of the old days.",
		"Before the cave started... changing.",
		"Take care of yourself out there."
	])
	npcs.add_child(flower)


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
	player.position = spawn_points.get("default", Vector2(480, 576))
	player.set_job("fighter")
	add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	camera.make_current()

	# Zoom in for larger sprites (2x)
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
	controller.encounter_enabled = false  # Safe zone!
	controller.current_area_id = "harmonia_village"

	controller.set_area_config("harmonia_village", true, 0.0, [])

	controller.battle_triggered.connect(_on_battle_triggered)
	controller.menu_requested.connect(_on_menu_requested)

	add_child(controller)


func _on_transition_triggered(target_map: String, spawn_point: String) -> void:
	area_transition.emit(target_map, spawn_point)


func _on_battle_triggered(enemies: Array) -> void:
	battle_triggered.emit(enemies)


func _on_menu_requested() -> void:
	pass


## Spawn player at a specific spawn point
func spawn_player_at(spawn_name: String) -> void:
	if spawn_points.has(spawn_name):
		player.teleport(spawn_points[spawn_name])
		player.reset_step_count()


## Resume exploration
func resume() -> void:
	controller.resume_exploration()


## Pause exploration
func pause() -> void:
	controller.pause_exploration()


## Set the player's job
func set_player_job(job_name: String) -> void:
	if player:
		player.set_job(job_name)


## Set the player's appearance from the party leader
func set_player_appearance(leader) -> void:
	if player and player.has_method("set_appearance_from_leader"):
		player.set_appearance_from_leader(leader)
