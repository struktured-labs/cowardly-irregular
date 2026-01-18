extends Node2D
class_name HarmoniaVillageScene

## HarmoniaVillage - Starter village, safe zone
## No random encounters, NPCs, shops, inn

const TileGeneratorScript = preload("res://src/exploration/TileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")
const OverworldNPCScript = preload("res://src/exploration/OverworldNPC.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)

## Map dimensions (in tiles)
const MAP_WIDTH: int = 20
const MAP_HEIGHT: int = 15
const TILE_SIZE: int = 32

## Scene components
var tile_map: TileMapLayer
var player: Node2D  # OverworldPlayer
var camera: Camera2D
var controller: Node  # OverworldController
var tile_generator: Node  # TileGenerator

## Area transitions
var transitions: Node2D

## NPCs container
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

	# Start village music
	if SoundManager:
		SoundManager.play_area_music("village")

	exploration_ready.emit()


func _setup_scene() -> void:
	tile_generator = TileGeneratorScript.new()
	add_child(tile_generator)

	# Create TileMapLayer
	tile_map = TileMapLayer.new()
	tile_map.name = "TileMap"
	tile_map.tile_set = tile_generator.create_tileset()
	add_child(tile_map)

	# Create transitions container
	transitions = Node2D.new()
	transitions.name = "Transitions"
	add_child(transitions)

	# Create NPCs container
	npcs = Node2D.new()
	npcs.name = "NPCs"
	add_child(npcs)


func _generate_map() -> void:
	# Village layout:
	# W = wall, . = floor, I = inn, S = shop, N = NPC spot, X = exit, P = save point
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWW",
		"W..................W",
		"W..III.......SSS...W",
		"W..III.......SSS...W",
		"W..................W",
		"W.......NNN........W",
		"W..................W",
		"W..................W",
		"W........PPP.......W",
		"W........PPP.......W",
		"W..................W",
		"W..................W",
		"W.......XXXX.......W",
		"W.......XXXX.......W",
		"WWWWWWWWWWWWWWWWWWWW"
	]

	# Convert map_data to tiles
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

	# Default spawn (entrance from overworld) - slightly inside to avoid immediate exit trigger
	spawn_points["entrance"] = Vector2(10 * TILE_SIZE, 10 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		".": return TileGeneratorScript.TileType.FLOOR
		"I": return TileGeneratorScript.TileType.FLOOR  # Inn area (floor)
		"S": return TileGeneratorScript.TileType.FLOOR  # Shop area (floor)
		"N": return TileGeneratorScript.TileType.FLOOR  # NPC area (floor)
		"X": return TileGeneratorScript.TileType.FLOOR  # Exit (floor)
		"P": return TileGeneratorScript.TileType.FLOOR  # Save point (floor)
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
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(320, 416))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 4, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_transition_collision(trans: Area2D, size: Vector2) -> void:
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	trans.add_child(collision)


func _setup_npcs() -> void:
	# Village Elder - center of village (N area - row 5, col 9)
	var elder = _create_npc("Elder Theron", "elder", Vector2(9 * TILE_SIZE, 5 * TILE_SIZE), [
		"Welcome to Harmonia Village, young adventurer.",
		"Our peaceful village has stood for generations...",
		"But dark rumors spread from the Whispering Cave to the north.",
		"Many brave souls have ventured there... few return.",
		"If you seek glory, be warned: the cave adapts to those who challenge it.",
		"May the light guide your path."
	])
	npcs.add_child(elder)

	# Innkeeper - near the inn (I area - row 3, col 4)
	var innkeeper = _create_npc("Martha", "innkeeper", Vector2(4 * TILE_SIZE, 3 * TILE_SIZE), [
		"Welcome to the Sleepy Slime Inn!",
		"A good rest restores the body and spirit.",
		"We don't get many visitors these days...",
		"The cave's been making folks nervous.",
		"Stay safe out there, dear."
	])
	npcs.add_child(innkeeper)

	# Shopkeeper - near the shop (S area - row 3, col 14)
	var shopkeeper = _create_npc("Garvin", "shopkeeper", Vector2(14 * TILE_SIZE, 3 * TILE_SIZE), [
		"Potions! Antidotes! Everything an adventurer needs!",
		"Business has been slow since the cave got... strange.",
		"They say monsters in there grow stronger the more you fight.",
		"Some kind of adaptation, perhaps?",
		"Stock up before you go - you'll need it!"
	])
	npcs.add_child(shopkeeper)

	# Wandering villager - somewhere in the middle
	var villager1 = _create_npc("Farmer Gil", "villager", Vector2(6 * TILE_SIZE, 7 * TILE_SIZE), [
		"*yawn* Another day, another harvest.",
		"Say, you look like an adventurer type.",
		"My cousin went into that cave last month...",
		"Came back babbling about 'infinite loops' and 'meta awareness'.",
		"Poor fellow's been talking to his reflection ever since."
	])
	npcs.add_child(villager1)

	# Another villager near save point
	var villager2 = _create_npc("Young Pip", "villager", Vector2(12 * TILE_SIZE, 8 * TILE_SIZE), [
		"Wow! A real adventurer!",
		"I'm gonna be just like you when I grow up!",
		"I heard you can AUTOMATE fighting in this world...",
		"Isn't that kind of... cheating?",
		"My mom says it's 'enlightenment', whatever that means."
	])
	npcs.add_child(villager2)

	# Guard near exit
	var guard = _create_npc("Guard Boris", "guard", Vector2(7 * TILE_SIZE, 11 * TILE_SIZE), [
		"Halt! ...Oh, you're heading OUT? Carry on then.",
		"I'm here to keep monsters from getting IN.",
		"The overworld isn't too dangerous...",
		"But watch out for the cave. Strange things happen there.",
		"Rumor has it the boss gets stronger each time it's defeated."
	])
	npcs.add_child(guard)


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
	player.position = spawn_points.get("default", Vector2(320, 384))
	player.set_job("fighter")
	add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	camera.make_current()

	var map_pixel_width = MAP_WIDTH * TILE_SIZE
	var map_pixel_height = MAP_HEIGHT * TILE_SIZE

	# Normal camera limits to map bounds
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

	# Configure as safe zone
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
