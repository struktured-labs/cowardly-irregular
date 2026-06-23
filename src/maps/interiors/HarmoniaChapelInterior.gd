extends Node2D
class_name HarmoniaChapelInterior

## HarmoniaChapelInterior - Small stone chapel in Harmonia Village.
## Adds one enterable interior beyond the tavern. Sister Concord is
## present and foreshadows the Mordaine fight: she remembers when the
## Chancellor used to come here, and she's worried what's changed.

signal transition_triggered(target_map: String, target_spawn: String)
signal area_transition(target_map: String, target_spawn: String)
signal battle_triggered(enemies: Array)

const TILE_SIZE: int = 32
const MAP_WIDTH: int = 14
const MAP_HEIGHT: int = 10

const CHAPEL_LAYOUT = [
	"WWWWWWWWWWWWWW",
	"W............W",
	"W.PP......PP.W",
	"W............W",
	"W.....AA.....W",
	"W.....AA.....W",
	"W.PP......PP.W",
	"W............W",
	"W............W",
	"WWWWWWDDWWWWWW",
]

var tilemap: TileMapLayer
var player: Node2D
var camera: Camera2D
var npcs: Node2D
var transitions: Node2D
var decorations: Node2D
var controller: Node

var spawn_points: Dictionary = {
	"entrance": Vector2(6, 8),
	"altar": Vector2(6, 5),
}


func _ready() -> void:
	_setup_tilemap()
	_setup_decorations()
	_setup_npcs()
	_setup_transitions()
	_setup_player()
	_setup_camera()
	_setup_controller()
	if SoundManager:
		SoundManager.play_area_music("village")


func _setup_tilemap() -> void:
	tilemap = TileMapLayer.new()
	tilemap.name = "TileMapLayer"
	add_child(tilemap)

	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	var floor_source = TileSetAtlasSource.new()
	var floor_img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_floor_tile(floor_img)
	floor_source.texture = ImageTexture.create_from_image(floor_img)
	floor_source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	floor_source.create_tile(Vector2i(0, 0))
	tileset.add_source(floor_source, 0)

	var wall_source = TileSetAtlasSource.new()
	var wall_img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_wall_tile(wall_img)
	wall_source.texture = ImageTexture.create_from_image(wall_img)
	wall_source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	wall_source.create_tile(Vector2i(0, 0))
	tileset.add_source(wall_source, 1)

	tilemap.tile_set = tileset

	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var ch = CHAPEL_LAYOUT[y][x]
			if ch == "W":
				tilemap.set_cell(Vector2i(x, y), 1, Vector2i(0, 0))
			else:
				tilemap.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))


func _draw_floor_tile(image: Image) -> void:
	var stone = Color(0.55, 0.55, 0.58)
	var stone_dark = Color(0.42, 0.42, 0.46)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var seam = (x % 8 == 0) or (y % 8 == 0)
			image.set_pixel(x, y, stone_dark if seam else stone)


func _draw_wall_tile(image: Image) -> void:
	var stone = Color(0.38, 0.36, 0.42)
	var stone_light = Color(0.50, 0.48, 0.54)
	var mortar = Color(0.62, 0.60, 0.55)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var row = y / 10
			var offset = 10 if row % 2 == 0 else 0
			var in_mortar_h = y % 10 == 0
			var in_mortar_v = (x + offset) % 20 == 0
			if in_mortar_h or in_mortar_v:
				image.set_pixel(x, y, mortar)
			else:
				image.set_pixel(x, y, stone_light if (x + y) % 11 == 0 else stone)


func _setup_decorations() -> void:
	decorations = Node2D.new()
	decorations.name = "Decorations"
	add_child(decorations)
	_draw_altar()
	_draw_pews()


func _draw_altar() -> void:
	var altar = ColorRect.new()
	altar.color = Color(0.85, 0.78, 0.55)
	altar.size = Vector2(TILE_SIZE * 2, TILE_SIZE * 2)
	altar.position = Vector2(5 * TILE_SIZE, 4 * TILE_SIZE)
	decorations.add_child(altar)
	var altar_top = ColorRect.new()
	altar_top.color = Color(0.95, 0.88, 0.65)
	altar_top.size = Vector2(TILE_SIZE * 2, 6)
	altar_top.position = Vector2(5 * TILE_SIZE, 4 * TILE_SIZE)
	decorations.add_child(altar_top)


func _draw_pews() -> void:
	var pew_color = Color(0.34, 0.22, 0.14)
	for pew_pos in [Vector2(1, 2), Vector2(10, 2), Vector2(1, 6), Vector2(10, 6)]:
		var pew = ColorRect.new()
		pew.color = pew_color
		pew.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
		pew.position = pew_pos * TILE_SIZE
		decorations.add_child(pew)


func _setup_npcs() -> void:
	npcs = Node2D.new()
	npcs.name = "NPCs"
	add_child(npcs)
	var OverworldNPCScript = load("res://src/exploration/OverworldNPC.gd")
	if not OverworldNPCScript:
		return
	var sister = OverworldNPCScript.new()
	sister.npc_name = "Sister Concord"
	sister.npc_type = "scholar"
	sister.position = Vector2(7 * TILE_SIZE, 4 * TILE_SIZE)
	sister.dialogue_lines = [
		"Welcome, traveler. Rest your soul a moment.",
		"This chapel used to be full on the holy days.",
		"The Chancellor would sit there, third pew from the back. Always alone.",
		"He hasn't been here in months. Not since the cave started... whispering.",
		"If you go to the castle, look him in the eye. Tell me what you see there.",
	]
	npcs.add_child(sister)


func _setup_transitions() -> void:
	transitions = Node2D.new()
	transitions.name = "Transitions"
	add_child(transitions)
	var AreaTransitionScript = load("res://src/exploration/AreaTransition.gd")
	if not AreaTransitionScript:
		return
	var exit = AreaTransitionScript.new()
	exit.name = "Exit"
	exit.target_map = "harmonia_village"
	exit.target_spawn = "chapel_exit"
	exit.require_interaction = false
	exit.position = Vector2(7 * TILE_SIZE, 9.5 * TILE_SIZE)
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
	collision.shape = shape
	exit.add_child(collision)
	exit.collision_layer = 4
	exit.collision_mask = 2
	exit.monitoring = true
	exit.transition_triggered.connect(_on_exit_triggered)
	transitions.add_child(exit)


func _on_exit_triggered(target_map: String, target_spawn: String) -> void:
	transition_triggered.emit(target_map, target_spawn)
	area_transition.emit(target_map, target_spawn)


func _setup_player() -> void:
	var PlayerScript = load("res://src/exploration/OverworldPlayer.gd")
	if not PlayerScript:
		return
	player = PlayerScript.new()
	player.position = spawn_points["entrance"] * TILE_SIZE
	player._is_interior = true
	add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.zoom = Vector2(2.5, 2.5)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MAP_WIDTH * TILE_SIZE
	camera.limit_bottom = MAP_HEIGHT * TILE_SIZE
	if player:
		player.add_child(camera)
	else:
		add_child(camera)
		camera.position = Vector2(MAP_WIDTH * TILE_SIZE / 2, MAP_HEIGHT * TILE_SIZE / 2)


func _setup_controller() -> void:
	var ControllerScript = load("res://src/exploration/OverworldController.gd")
	if not (ControllerScript and player):
		return
	controller = ControllerScript.new()
	controller.name = "OverworldController"
	add_child(controller)
	if controller.has_method("set_player"):
		controller.set_player(player)
	if controller.has_method("set_area_config"):
		controller.set_area_config("harmonia_chapel", true, 0.0, [])


func spawn_player_at(spawn_name: String) -> void:
	if spawn_points.has(spawn_name) and player:
		player.position = spawn_points[spawn_name] * TILE_SIZE


func pause() -> void:
	if controller and controller.has_method("pause_exploration"):
		controller.pause_exploration()


func resume() -> void:
	if controller and controller.has_method("resume_exploration"):
		controller.resume_exploration()
