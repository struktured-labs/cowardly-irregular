extends Node2D
class_name SuburbanOverworld

## SuburbanOverworld - 16-bit EarthBound-style suburban neighborhood
## Features residential blocks, strip mall, park/playground, basketball court

const SuburbanTileGeneratorScript = preload("res://src/exploration/SuburbanTileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")
const OverworldNPCScript = preload("res://src/exploration/OverworldNPC.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)

## Map dimensions (in tiles)
const MAP_WIDTH: int = 50
const MAP_HEIGHT: int = 40
const TILE_SIZE: int = 32

## Scene components
var tile_map: TileMapLayer
var player: Node2D  # OverworldPlayer
var camera: Camera2D
var controller: Node  # OverworldController
var tile_generator: Node  # SuburbanTileGenerator

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

	# Start suburban overworld music
	if SoundManager:
		SoundManager.play_area_music("overworld_suburban")

	exploration_ready.emit()


func _setup_scene() -> void:
	tile_generator = SuburbanTileGeneratorScript.new()
	add_child(tile_generator)

	# Background behind tilemap (bright sky blue)
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.45, 0.65, 0.85)
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
	# Suburban neighborhood layout (50x40):
	# Rows 0-12:  RESIDENTIAL NORTH - Two rows of 4 houses with lawns, fences, trees
	# Rows 13-14: MAIN ROAD - 2-tile wide asphalt road
	# Rows 15-20: STRIP MALL - Sidewalk, parking lot, 5 storefronts
	# Rows 21-22: SIDE ROAD - 2-tile wide road
	# Rows 23-32: PARK / PLAYGROUND - playground, basketball court, benches, trees
	# Rows 33-39: SOUTH EDGE - Lawn with sidewalk strip for return portal
	#
	# Legend:
	# s=SIDEWALK, r=ROAD, h=HOUSE_WALL, l=LAWN, t=STORE_FRONT, d=HOUSE_DOOR
	# w=HOUSE_WINDOW, f=PICKET_FENCE, m=MAILBOX, y=FIRE_HYDRANT, p=PLAYGROUND
	# k=PARKING_LOT, e=SHADE_TREE, b=PARK_BENCH, c=BASKETBALL_COURT
	# g=FLOWER_BED

	print("Generating suburban overworld map %dx%d..." % [MAP_WIDTH, MAP_HEIGHT])

	var map_data: Array[String] = [
		# Row 0: North edge - lawns with shade trees
		"lllelllllllllelllllllllllllllllllllelllllllellllll",
		# Row 1: Picket fences around houses
		"lfffffffffflffffffffffffffflffffffffffffffffflllll",
		# Row 2: House row 1 - 4 houses
		"lfhwhdhwhfllfhwhdhwhflllfhwhdhwhflfhwhdhwhflllllll",
		# Row 3: House walls continued
		"lfhhhhhhhfllfhhhhhhhflllfhhhhhhhflfhhhhhhhflllllll",
		# Row 4: Fence bottoms, mailboxes
		"lffmffffffllfffffffmflllfffffffmflffffffmfllllllll",
		# Row 5: Open yard with trees
		"lllelllllllllellllllllelllllellllllellllllllelllll",
		# Row 6: Second row fences
		"lfffffffffflffffffffffffffflffffffffffffffffflllll",
		# Row 7: House row 2 - 4 houses
		"lfhwhdhwhfllfhwhdhwhflllfhwhdhwhflfhwhdhwhflllllll",
		# Row 8: House walls continued
		"lfhhhhhhhfllfhhhhhhhflllfhhhhhhhflfhhhhhhhflllllll",
		# Row 9: Fence bottoms, mailboxes
		"lffmffffffllfffffffmflllfffffffmflffffffmfllllllll",
		# Row 10: Yards between houses and road
		"lllelllllllllellllllllelllllellllllellllllllelllll",
		# Row 11: Sidewalk along north side of main road
		"ssssssssssssssssssssssssssssssssssssssssssssssssss",
		# Row 12: Sidewalk with fire hydrants
		"sssssssssyssssssssssssssyssssssssssssysssssssyssss",
		# Row 13: Main road
		"rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr",
		# Row 14: Main road
		"rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr",
		# Row 15: Sidewalk south side of road
		"ssssssssssssssssssssssssssssssssssssssssssssssssss",
		# Row 16: Parking lot in front of stores
		"kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkssss",
		# Row 17: Store fronts - Pizza, Arcade, Burger, Mart, School
		"tttdtttttttdttttttdttttttdtttttttdttttttttttssssss",
		# Row 18: Store walls
		"ttttttttttttttttttttttttttttttttttttttttttttttssss",
		# Row 19: Parking lot south
		"kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkssss",
		# Row 20: Sidewalk between strip mall and side road
		"ssssssssssssssssssssssssssssssssssssssssssssssssss",
		# Row 21: Side road
		"rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr",
		# Row 22: Side road
		"rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr",
		# Row 23: Park entrance - sidewalk and grass
		"ssssssssssssssssssssssssssssssssssssssssssssssssss",
		# Row 24: Park with trees and flower beds
		"llleggglllellllllllllllllllllllllllleggglllellllll",
		# Row 25: Basketball court area and playground start
		"llllllllllllccccccccccccllppppppppppllllblelllllll",
		# Row 26: Basketball court and playground
		"llelllbllllcccccccccccclpppppppppppplelllllellllll",
		# Row 27: Basketball court and playground
		"lllllllllllccccccccccccllppppppppppllbllllllllllll",
		# Row 28: Open park area
		"llleggglllellllllllblllllllllllllllleggglllelllbll",
		# Row 29: Park benches and trees
		"llellbllelllelllllllllelllellblllelllellllllelllll",
		# Row 30: Open grass with flower beds
		"lllggglllllllgggllelllllggglllllllggglllleglllllll",
		# Row 31: Park south edge
		"llellllellllelllllllelllllellllellllellllllellllll",
		# Row 32: Transition to south area
		"llllllllllllllllllllllllllllllllllllllllllllllllll",
		# Row 33: Lawn
		"lllelllllllllelllllllelllllellllllllelllllelllllll",
		# Row 34: Sidewalk strip
		"ssssssssssssssssssssssssssssssssssssssssssssssssss",
		# Row 35: Sidewalk with portal area
		"ssssssssssssssssssssssssssssssssssssssssssssssssss",
		# Row 36: Portal row
		"lllllllllllllllllllllllllsslllllllllllllllllllllll",
		# Row 37: South lawn
		"lllelllllllllelllllllelllllellllllllelllllelllllll",
		# Row 38: South edge
		"llllllllllllllllllllllllllllllllllllllllllllllllll",
		# Row 39: South boundary
		"llllllllllllllllllllllllllllllllllllllllllllllllll",
	]

	# Ensure map_data matches expected dimensions
	while map_data.size() < MAP_HEIGHT:
		map_data.append("l".repeat(50))

	# Convert map_data to tiles
	var tile_counts = {}
	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "l"
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			# Count tiles for debug
			tile_counts[tile_type] = tile_counts.get(tile_type, 0) + 1

	print("Suburban tile counts: ", tile_counts)

	# Define spawn points
	spawn_points["entrance"] = Vector2(25 * TILE_SIZE + TILE_SIZE / 2, 2 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["suburban_portal"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"s": return SuburbanTileGeneratorScript.TileType.SIDEWALK
		"r": return SuburbanTileGeneratorScript.TileType.ROAD
		"h": return SuburbanTileGeneratorScript.TileType.HOUSE_WALL
		"l": return SuburbanTileGeneratorScript.TileType.LAWN
		"t": return SuburbanTileGeneratorScript.TileType.STORE_FRONT
		"d": return SuburbanTileGeneratorScript.TileType.HOUSE_DOOR
		"w": return SuburbanTileGeneratorScript.TileType.HOUSE_WINDOW
		"f": return SuburbanTileGeneratorScript.TileType.PICKET_FENCE
		"m": return SuburbanTileGeneratorScript.TileType.MAILBOX
		"y": return SuburbanTileGeneratorScript.TileType.FIRE_HYDRANT
		"p": return SuburbanTileGeneratorScript.TileType.PLAYGROUND
		"k": return SuburbanTileGeneratorScript.TileType.PARKING_LOT
		"e": return SuburbanTileGeneratorScript.TileType.SHADE_TREE
		"b": return SuburbanTileGeneratorScript.TileType.PARK_BENCH
		"c": return SuburbanTileGeneratorScript.TileType.BASKETBALL_COURT
		"g": return SuburbanTileGeneratorScript.TileType.FLOWER_BED
		_: return SuburbanTileGeneratorScript.TileType.LAWN


func _get_atlas_coords(tile_type: int) -> Vector2i:
	# Map tile types to atlas coordinates (4-column layout)
	var tile_id = SuburbanTileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 4, tile_id / 4)


func _setup_transitions() -> void:
	# Return portal at south edge (row 36, center)
	var portal_trans = AreaTransitionScript.new()
	portal_trans.name = "OverworldPortal"
	portal_trans.target_map = "overworld"
	portal_trans.target_spawn = "suburban_portal"
	portal_trans.require_interaction = true
	portal_trans.indicator_text = "Return to Overworld"
	portal_trans.position = Vector2(25 * TILE_SIZE + TILE_SIZE / 2, 36 * TILE_SIZE + TILE_SIZE / 2)
	_setup_transition_collision(portal_trans, Vector2(TILE_SIZE, TILE_SIZE))
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
	# === Brad the Skateboarder - park area ===
	var brad = _create_npc("Brad the Skateboarder", "villager", Vector2(20 * TILE_SIZE, 27 * TILE_SIZE), [
		"Dude... have you checked behind the school?",
		"There's supposed to be some hidden debug menu or something.",
		"My friend's cousin's roommate unlocked like... secret jobs.",
		"Radical."
	])
	npcs.add_child(brad)

	# === Karen - strip mall ===
	var karen = _create_npc("Karen", "villager", Vector2(8 * TILE_SIZE, 17 * TILE_SIZE), [
		"I want to speak to whoever designed this town.",
		"The encounter rate is UNACCEPTABLE.",
		"I've been complaining to NPCs for HOURS.",
		"Where. Is. Your. Manager."
	])
	npcs.add_child(karen)

	# === Mall Rat Mike - near arcade store ===
	var mike = _create_npc("Mall Rat Mike", "villager", Vector2(12 * TILE_SIZE, 17 * TILE_SIZE), [
		"Yo, you know about autobattle? Press F5, dude.",
		"I set up my scripts to farm crows all day.",
		"The XP isn't great but the drops are SICK.",
		"Pro tip: condition 'Enemy HP < 25%' \u2192 Steal. Trust me."
	])
	npcs.add_child(mike)

	# === Coach Thompson - basketball court ===
	var coach = _create_npc("Coach Thompson", "guard", Vector2(16 * TILE_SIZE, 25 * TILE_SIZE), [
		"Listen up! Combat is like basketball.",
		"Sometimes you gotta DEFER - pass the ball, wait for an opening.",
		"Build up that AP, then ADVANCE with everything you got!",
		"Full-court press, baby! That's how you win!"
	])
	npcs.add_child(coach)

	# === Suspicious Dave - behind houses, east lawn ===
	var dave = _create_npc("Suspicious Dave", "villager", Vector2(38 * TILE_SIZE, 3 * TILE_SIZE), [
		"Psst... don't tell anyone I told you this...",
		"The monsters? They're stored in JSON files.",
		"abilities.json... passives.json... it's all RIGHT THERE.",
		"The devs didn't even ENCRYPT it. Wake up, people!"
	])
	npcs.add_child(dave)

	# === Pizza Delivery Pete - near pizza store ===
	var pete = _create_npc("Pizza Delivery Pete", "villager", Vector2(3 * TILE_SIZE, 18 * TILE_SIZE), [
		"30 minutes or it's free! That's my motto.",
		"My Speed stat is maxed out. Gotta go fast!",
		"You know what ruins a delivery? Random encounters.",
		"I swear those crows target me specifically."
	])
	npcs.add_child(pete)

	# === Principal Sinclair - near school store ===
	var principal = _create_npc("Principal Sinclair", "elder", Vector2(38 * TILE_SIZE, 18 * TILE_SIZE), [
		"Welcome to Suburbia Public School... sort of.",
		"This entire neighborhood appeared overnight.",
		"One day, medieval village. Next day, parking lots.",
		"The elders call it a '16-bit anomaly.' I call it Tuesday."
	])
	npcs.add_child(principal)

	# === The Dog - park area ===
	var dog = _create_npc("The Dog", "villager", Vector2(30 * TILE_SIZE, 30 * TILE_SIZE), [
		"*The dog stares at you*",
		"*It seems to understand save files*",
		"*It wags its tail knowingly*",
		"*You feel judged*"
	])
	npcs.add_child(dog)


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
	player.position = spawn_points.get("default", Vector2(800, 80))
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
	controller.current_area_id = "suburban_overworld"

	# Suburban encounters - EarthBound-style enemies
	controller.set_area_config("suburban_overworld", false, 0.05,
		["new_age_retro_hippie", "spiteful_crow", "skate_punk", "unassuming_dog", "cranky_lady"])

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
