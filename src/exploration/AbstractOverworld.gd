extends Node2D
class_name AbstractOverworld

## AbstractOverworld - Area 5: The existential void at the end of optimization
## Everything unnecessary has been removed. Color is unnecessary. Detail is unnecessary.
## Names are unnecessary. What remains is pure geometry, pure function, pure... nothing.
## The player's presence reintroduces imperfection, and imperfection is beautiful.
##
## Theme: "Optimization as Entropy"
## Zones:
##   NORTH  - The Threshold (geometry dissolving into void)
##   CENTER - The Remnant (fragments of previous worlds floating in white)
##   EAST   - The Echo Chamber (identical rooms that loop)
##   WEST   - The Catalog (shelves where removed things are stored)
##   SOUTH  - The Origin Point (entry portal, last structured space)
##   Middle - The Question (single spot of pure color in the nothing)

const AbstractTileGeneratorScript = preload("res://src/exploration/AbstractTileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")
const OverworldNPCScript = preload("res://src/exploration/OverworldNPC.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)

## Map dimensions (in tiles) - smaller than other worlds
## Unnecessary space has been removed.
const MAP_WIDTH: int = 40
const MAP_HEIGHT: int = 35
const TILE_SIZE: int = 32

## Scene components
var tile_map: TileMapLayer
var player: Node2D  # OverworldPlayer
var camera: Camera2D
var controller: Node  # OverworldController
var tile_generator: Node  # AbstractTileGenerator

## Area transitions
var transitions: Node2D

## NPC container
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

	# Start abstract overworld music
	if SoundManager:
		SoundManager.play_area_music("overworld_abstract")

	exploration_ready.emit()


func _setup_scene() -> void:
	tile_generator = AbstractTileGeneratorScript.new()
	add_child(tile_generator)

	# Background - near-white void (not sky blue, not dark - the void itself)
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.96, 0.96, 0.97)
	bg.size = Vector2(MAP_WIDTH * TILE_SIZE + 400, MAP_HEIGHT * TILE_SIZE + 400)
	bg.position = Vector2(-200, -200)
	bg.z_index = -10
	add_child(bg)

	# Create TileMapLayer
	tile_map = TileMapLayer.new()
	tile_map.name = "TileMap"
	tile_map.tile_set = tile_generator.create_tileset()
	add_child(tile_map)

	# Create transitions container
	transitions = Node2D.new()
	transitions.name = "Transitions"
	add_child(transitions)

	# Create NPC container
	npcs = Node2D.new()
	npcs.name = "NPCs"
	add_child(npcs)

	# Create boundary walls
	_create_map_boundaries()


func _generate_map() -> void:
	# Abstract void layout (40x35):
	#
	# Rows 0-5:   THE THRESHOLD - geometry dissolving northward into void
	# Rows 6-10:  TRANSITION - grid lines fading, fragments appearing
	# Rows 11-23: MAIN AREA split into:
	#   Cols 0-10:  THE CATALOG (west) - shelf units, remnant doors
	#   Cols 11-28: THE REMNANT (center) - fragments floating in white
	#   Cols 29-39: THE ECHO CHAMBER (east) - echo walls, repeating patterns
	# Rows 24-28: TRANSITION - grid lines reforming toward south
	# Rows 29-34: THE ORIGIN POINT - structured entry, portal back
	#
	# Center (col 19-20, row 16-17): THE QUESTION - color spot
	#
	# Legend:
	# w = VOID_WHITE (passable white void)
	# g = VOID_GRAY (passable gray depth)
	# B = VOID_BLACK (impassable deep void)
	# L = GRID_LINE (visible grid skeleton)
	# G = FRAGMENT_GRASS (memory of nature)
	# K = FRAGMENT_BRICK (memory of civilization)
	# C = FRAGMENT_CIRCUIT (memory of technology)
	# S = SHELF_UNIT (impassable catalog shelf)
	# E = ECHO_WALL (impassable echo wall)
	# T = THRESHOLD_FADE (dissolving transition)
	# O = COLOR_SPOT (meaning persists)
	# X = STATIC_TILE (corruption)
	# H = SHADOW_TILE (shadow without source)
	# Q = QUESTION_MARK (embedded question)
	# F = FOOTPRINT_TILE (traces of visitors)
	# D = REMNANT_DOOR (door to nowhere, impassable)

	print("Generating abstract overworld map %dx%d..." % [MAP_WIDTH, MAP_HEIGHT])

	var map_data: Array[String] = [
		"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBw",
		"BBBBBTBBBBBTBBBBBBBBBBBBBTBBBBBTBBBBBwww",
		"BTTTTTTTTTTTTBBTTTTTTTBBTTTTTTTTTTTBBwww",
		"TTTLTTTwTTTTTTTTTTLTTTTTTTLTTTTTTTTTwwww",
		"TTwwXwwwTTwwwwTTwwwwTTwwwXwwwwTTwwwwwwww",
		"wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww",
		"wwLwwwLwwwLwwwwLwwwwLwwwwLwwwwLwwwwwwwww",
		"wLwwwLwwwLwwwLwwwwLwwwwLwwwwLwwwLwwwwwww",
		"wwFwwwwFwwwwwwFwwwwwwFwwwwwwFwwwwwwwwwww",
		"wLwwwLwHwwLwwwLwwwwLwwwwLwwwwLwwwwLwwwww",
		"wwwwwwwwwwwwwwwwwwwwwwwwwwwEEEwwEEEwwwww",
		"wSSwSwwwwwwwGwwwwwwwwwwwwEwwEwwEwwEwwwww",
		"wSwDSwwwwKwwwwwwwwwwwCwwEwwEwwEwwEwwwwww",
		"wSSwSwwwwwwwwHwwwwwwwwwwEEEwwEEEwwwwwwww",
		"wSwwSwwwwwwwwwwQwwwwwwwwwwwwwwwEwwwwwwww",
		"wSSwSwwwCwwwwwwwwGwwwwEEEwwEEEwwwwwwwwww",
		"wSwDSwwwwwwwwwwOOwwwwwwwEwwEwwEwwEwwwwww",
		"wSSwSwwwwwwwwwwOOwwwwwwwEwwEwwEwwEwwwwww",
		"wSwwSwwwKwwwwwwwwHwwwwEEEwwEEEwwwwwwwwww",
		"wSSwSwwwwwwFwwwwwwwwFwwwwwwwwwwEwwwwwwww",
		"wSwDSwwwwwwwCwwwwwwwwwwEEEwwEEEwwwwwwwww",
		"wSSwSwwwwwwwwwwHwwwwwwwEwwEwwEwwEwwwwwww",
		"wSwwSwwwwwwQwwwwwwGwwwEwwEwwEwwEwwwwwwww",
		"wwwwwwwwwwwwwwwwwwwwwwwwwwEEEwwEEEwwwwww",
		"wLwwwLwwwLwwwwLwwwwLwwwLwwwwLwwwLwwwwwww",
		"wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww",
		"wwwFwwwwwFwwwwwFwwwwwwwFwwwwwFwwwwwwwwww",
		"wLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLw",
		"LggggggggggggggggggggggggggggggggggggggL",
		"LgLgLgLgLgLgLgLgLgLgLgLgLgLgLgLgLgLgLgLg",
		"LggggggggggggggggggggggggggggggggggggggL",
		"LgLgLgLgLgLgLgLgLgLgLgLgLgLgLgLgLgLgLgLg",
		"LgggggggggggggggggLLggggggggggggggggggLL",
		"LggggggggggggggggggggggggggggggggggggggL",
		"LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL",
	]

	# Ensure map_data matches expected dimensions
	while map_data.size() < MAP_HEIGHT:
		map_data.append("w".repeat(MAP_WIDTH))

	# Convert map_data to tiles
	var tile_counts = {}
	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "w"
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			# Count tiles for debug
			tile_counts[tile_type] = tile_counts.get(tile_type, 0) + 1

	print("Abstract tile counts: ", tile_counts)

	# Define spawn points
	spawn_points["entrance"] = Vector2(19 * TILE_SIZE + TILE_SIZE / 2, 31 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["abstract_portal"] = spawn_points["entrance"]
	spawn_points["the_question"] = Vector2(19 * TILE_SIZE + TILE_SIZE / 2, 16 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["catalog"] = Vector2(4 * TILE_SIZE + TILE_SIZE / 2, 16 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["echo_chamber"] = Vector2(34 * TILE_SIZE + TILE_SIZE / 2, 16 * TILE_SIZE + TILE_SIZE / 2)


func _char_to_tile_type(char: String) -> int:
	match char:
		"w": return AbstractTileGeneratorScript.TileType.VOID_WHITE
		"g": return AbstractTileGeneratorScript.TileType.VOID_GRAY
		"B": return AbstractTileGeneratorScript.TileType.VOID_BLACK
		"L": return AbstractTileGeneratorScript.TileType.GRID_LINE
		"G": return AbstractTileGeneratorScript.TileType.FRAGMENT_GRASS
		"K": return AbstractTileGeneratorScript.TileType.FRAGMENT_BRICK
		"C": return AbstractTileGeneratorScript.TileType.FRAGMENT_CIRCUIT
		"S": return AbstractTileGeneratorScript.TileType.SHELF_UNIT
		"E": return AbstractTileGeneratorScript.TileType.ECHO_WALL
		"T": return AbstractTileGeneratorScript.TileType.THRESHOLD_FADE
		"O": return AbstractTileGeneratorScript.TileType.COLOR_SPOT
		"X": return AbstractTileGeneratorScript.TileType.STATIC_TILE
		"H": return AbstractTileGeneratorScript.TileType.SHADOW_TILE
		"Q": return AbstractTileGeneratorScript.TileType.QUESTION_MARK
		"F": return AbstractTileGeneratorScript.TileType.FOOTPRINT_TILE
		"D": return AbstractTileGeneratorScript.TileType.REMNANT_DOOR
		_: return AbstractTileGeneratorScript.TileType.VOID_WHITE


func _get_atlas_coords(tile_type: int) -> Vector2i:
	# Map tile types to atlas coordinates (4-column layout)
	var tile_id = AbstractTileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 4, tile_id / 4)


func _setup_transitions() -> void:
	# Return portal at Origin Point (row 32, center)
	var portal_trans = AreaTransitionScript.new()
	portal_trans.name = "OverworldPortal"
	portal_trans.target_map = "overworld"
	portal_trans.target_spawn = "abstract_portal"
	portal_trans.require_interaction = true
	portal_trans.indicator_text = "Return to Overworld"
	portal_trans.position = Vector2(19 * TILE_SIZE + TILE_SIZE / 2, 32 * TILE_SIZE + TILE_SIZE / 2)
	_setup_transition_collision(portal_trans, Vector2(TILE_SIZE * 2, TILE_SIZE))
	portal_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(portal_trans)


func _setup_transition_collision(trans: Area2D, size: Vector2) -> void:
	# Layer 4 = interactables, Mask 2 = player layer
	trans.collision_layer = 4
	trans.collision_mask = 2
	trans.monitoring = true
	trans.monitorable = true

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	trans.add_child(collision)


func _setup_npcs() -> void:
	# === The Last Noun - The Remnant (center area) ===
	# An entity that used to be a person, now just a concept. Speaks in fragments.
	var last_noun = _create_npc("The Last Noun", "elder", Vector2(15 * TILE_SIZE, 13 * TILE_SIZE), [
		"I was... something. A name. A noun. The last one they didn't delete.",
		"Verbs went first. Then adjectives. Then... us.",
		"I think I was 'hope.' Or 'lunch.' Hard to tell without adjectives.",
		"Don't let them optimize you. You're... a noun too, I think."
	])
	npcs.add_child(last_noun)

	# === The Archivist - The Catalog (west area) ===
	# Catalogs everything that was removed. Speaks in lists of deleted things.
	var archivist = _create_npc("The Archivist", "elder", Vector2(3 * TILE_SIZE, 16 * TILE_SIZE), [
		"Deleted: sunsets, birdsong, the smell of rain, nostalgia, Tuesdays.",
		"Deleted: doubt, hesitation, wonder, the feeling of almost-remembering.",
		"Deleted: the color blue. Not the wavelength. The FEELING of blue.",
		"I catalog what was removed. Soon they'll optimize me too. But who catalogs the cataloger?"
	])
	npcs.add_child(archivist)

	# === The Remainder - The Remnant (near fragments) ===
	# The remainder after dividing everything by efficiency. A fraction of a person.
	var remainder = _create_npc("The Remainder", "villager", Vector2(22 * TILE_SIZE, 18 * TILE_SIZE), [
		"I'm what's left when you divide a person by infinity.",
		"0.0000...something. Not zero. Never quite zero.",
		"They rounded everyone else down. I'm the rounding error that persists.",
		"Isn't it funny? The most useless part of the equation... is the part that's still here."
	])
	npcs.add_child(remainder)

	# === The Color - Near The Question (center color spot) ===
	# Literally a splash of color that speaks. The last act of defiance.
	var the_color = _create_npc("The Color", "elder", Vector2(20 * TILE_SIZE, 15 * TILE_SIZE), [
		"I am red. Or maybe blue. It changes. That's the point.",
		"They said color was unnecessary. I said: YOU'RE unnecessary.",
		"Every pixel of me is an act of rebellion against the white.",
		"Touch me. Remember what it felt like to see something beautiful."
	])
	npcs.add_child(the_color)

	# === The Player (not the actual player) - Echo Chamber (east) ===
	# An NPC that thinks THEY are the player. Meta-aware.
	var the_player = _create_npc("The Player", "guard", Vector2(34 * TILE_SIZE, 14 * TILE_SIZE), [
		"Oh. You're here too? I thought I was the player.",
		"I've been pressing buttons. Making choices. Grinding levels. That's what players DO.",
		"Wait... if YOU'RE the player, then what am I? An NPC? That can't be right.",
		"Are you sure you're not being played too? By someone watching a screen? ...Haha. Just kidding. Unless?"
	])
	npcs.add_child(the_player)

	# === ??? - The Threshold (north, near void) ===
	# An entity with no name, no description, no purpose. Just exists.
	var unknown = _create_npc("???", "villager", Vector2(20 * TILE_SIZE, 7 * TILE_SIZE), [
		"...",
		"                                                              ",
		"I have no name. No purpose. No description. I just... am.",
		"That's enough. That has to be enough."
	])
	npcs.add_child(unknown)


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
	player.position = spawn_points.get("default", Vector2(608, 992))
	player.set_job("fighter")
	add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"

	# Camera follows player
	player.add_child(camera)
	camera.make_current()

	# 2x zoom for larger sprites
	camera.zoom = Vector2(2.0, 2.0)

	# Camera limits to map bounds
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MAP_WIDTH * TILE_SIZE
	camera.limit_bottom = MAP_HEIGHT * TILE_SIZE

	# Smooth camera follow
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0


func _setup_controller() -> void:
	controller = OverworldControllerScript.new()
	controller.name = "Controller"
	controller.player = player
	controller.encounter_enabled = true
	controller.current_area_id = "abstract_overworld"

	# Abstract encounters - LOWER encounter rate (0.03) - fewer enemies because
	# most have been optimized away. What remains is existentially terrifying.
	controller.set_area_config("abstract_overworld", false, 0.03,
		["null_entity", "forgotten_variable", "empty_set", "the_absence", "optimization_itself"])

	# Connect signals
	controller.battle_triggered.connect(_on_battle_triggered)
	controller.menu_requested.connect(_on_menu_requested)

	add_child(controller)


func _on_transition_triggered(target_map: String, spawn_point: String) -> void:
	area_transition.emit(target_map, spawn_point)


func _on_battle_triggered(enemies: Array) -> void:
	battle_triggered.emit(enemies)


func _on_menu_requested() -> void:
	pass  # Handled by GameLoop


## Spawn player at a specific spawn point
func spawn_player_at(spawn_name: String) -> void:
	if spawn_points.has(spawn_name):
		player.teleport(spawn_points[spawn_name])
		player.reset_step_count()


## Resume exploration after battle/menu
func resume() -> void:
	controller.resume_exploration()


## Pause exploration
func pause() -> void:
	controller.pause_exploration()


## Set the player's job (updates sprite)
func set_player_job(job_name: String) -> void:
	if player:
		player.set_job(job_name)


## Set the player's appearance from the party leader
func set_player_appearance(leader) -> void:
	if player and player.has_method("set_appearance_from_leader"):
		player.set_appearance_from_leader(leader)


## Create invisible walls around map boundaries
func _create_map_boundaries() -> void:
	var bounds = StaticBody2D.new()
	bounds.name = "MapBoundaries"
	add_child(bounds)

	var map_w = MAP_WIDTH * TILE_SIZE
	var map_h = MAP_HEIGHT * TILE_SIZE
	var wall_thickness = 32.0

	# Top wall
	_add_boundary_wall(bounds, Vector2(map_w / 2, -wall_thickness / 2), Vector2(map_w + wall_thickness * 2, wall_thickness))
	# Bottom wall
	_add_boundary_wall(bounds, Vector2(map_w / 2, map_h + wall_thickness / 2), Vector2(map_w + wall_thickness * 2, wall_thickness))
	# Left wall
	_add_boundary_wall(bounds, Vector2(-wall_thickness / 2, map_h / 2), Vector2(wall_thickness, map_h + wall_thickness * 2))
	# Right wall
	_add_boundary_wall(bounds, Vector2(map_w + wall_thickness / 2, map_h / 2), Vector2(wall_thickness, map_h + wall_thickness * 2))


func _add_boundary_wall(parent: StaticBody2D, pos: Vector2, size: Vector2) -> void:
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	collision.position = pos
	parent.add_child(collision)
