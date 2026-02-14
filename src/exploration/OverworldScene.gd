extends Node2D
class_name OverworldScene

## OverworldScene - Main overworld exploration scene
## 100x70 tile world with 6 terrain biomes, villages, caves, and regional encounters

const TileGeneratorScript = preload("res://src/exploration/TileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)

## Map dimensions (in tiles)
const MAP_WIDTH: int = 100
const MAP_HEIGHT: int = 70
const TILE_SIZE: int = 32

## Scene components
var tile_map: TileMapLayer
var player: Node2D  # OverworldPlayer
var camera: Camera2D
var controller: Node  # OverworldController
var tile_generator: Node  # TileGenerator

## Area transitions
var transitions: Node2D

## Spawn points
var spawn_points: Dictionary = {}

## Current encounter zone
var _current_zone: String = "central"


func _ready() -> void:
	_setup_scene()
	_generate_map()
	_setup_transitions()
	_setup_player()
	_setup_camera()
	_setup_controller()

	# Start overworld music
	if SoundManager:
		SoundManager.play_area_music("overworld")

	exploration_ready.emit()


func _process(_delta: float) -> void:
	if player:
		_update_encounter_zone(player.position)


func _setup_scene() -> void:
	tile_generator = TileGeneratorScript.new()
	add_child(tile_generator)

	# Background behind tilemap (covers beyond map edges)
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.12, 0.18, 0.28)  # Dark blue-gray water/void
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

	# Create boundary walls
	_create_map_boundaries()


func _generate_map() -> void:
	## 100x70 overworld with terrain biomes:
	## NW=Ice/Snow  N=Forest  NE=Swamp/Spooky
	## W=Mountains  CENTER=Grassland  E=Coast
	## SW=Desert    S=Rivers/Bridges  SE=Volcanic
	##
	## Legend:
	## ~ = water, M = mountain, . = path, g = grass, F = forest, B = bridge
	## C = whispering cave, V = harmonia village
	## i = ice/snow, s = sand/desert, S = swamp, d = dark/corrupted
	## 1 = ice dragon cave, 2 = shadow dragon cave
	## 3 = lightning dragon cave, 4 = fire dragon cave
	## W = frosthold, E = eldertree, G = grimhollow, D = sandrift, I = ironhaven
	## P = steampunk portal

	print("Generating overworld map %dx%d..." % [MAP_WIDTH, MAP_HEIGHT])

	var map_data: Array[String] = [
		# Row 0-9: Northern region (Ice NW, Forest N, Swamp NE)
		"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~",  # 0
		"~~MMMMMMiiiiiiiiii~~~FFFFFFFFFFFFFFFFFFFFFFFFFFFFF~~~~~~~~~~~~~SSSSSSSSSSdddddddddddd~~~~~~~~~~~~~~~",  # 1
		"~~MMMMMiiiiiiiiiii~~~FFFFFFFFFFFFFFFFFFFFFFFFFFFF~~~~~~~~~~~~~~SSSSSSSSSdddddddddddddd~~~~~~~~~~~~~~",  # 2
		"~~MMMMiiii.iiiiiii~~FFFFFFFFFFgFFFFFFFFFFFFFFFFF~~~~~~~~~~~~~~~SSSSSSSSddddddddddddddd~~~~~~~~~~~~~~",  # 3
		"~~MMMiii..1.iiiiii~~FFFFFFFgggggFFFFFFFFFFFFFFFF~~~~~~~~~~~~~~~SSSSSSSdddddd..ddddddddd~~~~~~~~~~~~~",  # 4
		"~~MMiiii....iiiiiii~FFFFFFgggggggFFFFFFFFFFFFFFF~~~~~~~~~~~~~~~SSSSSSddddd.....dddddddd~~~~~~~~~~~~~",  # 5
		"~~MMiii..W..iiiiii~~FFFFFggggEggggFFFFFFFFFFFFF~~~~~~~~~~~~~~~~SSSSSdddd...2...ddddddd~~~~~~~~~~~~~~",  # 6
		"~~MMiiii....iiiii~~~FFFFggggg.gggggFFFFFFFFFFFF~~~~~~~~~~~~~~~~SSSSdddd.........dddddd~~~~~~~~~~~~~~",  # 7
		"~~MMMiii..iiiii~~~~~FFFgggg.....ggggFFFFFFFFFFF~~~~~~~~~~~~~~~~SSSddddd..G......ddddd~~~~~~~~~~~~~~~",  # 8
		"~~MMMMiiiiiiii~~~~~~FFggg.........gggFFFFFFFFFF~~~~~~~~~~~~~~~~SSdddddd.........ddddd~~~~~~~~~~~~~~~",  # 9
		# Row 10-19: Transition from north to central
		"~~MMMMMiiiii~~~~~~~~~Fgg...........ggFFFFFFFFF~~~~~~~~~~~~~~~~~Sddddddd........dddddd~~~~~~~~~~~~~~~",  # 10
		"~~~MMMMiii~~~~~~~~~~~Fg.............gFFFFFFFF~~~~~~~~~~~~~~~~~~Sdddddd.......dddddd~~~~~~~~~~~~~~~~~",  # 11
		"~~~~MMMii~~~~~~~~~~~~g..............gFFFFFFF~~~~~~~~~~~~~~~~~~~Sddddd......ddddddd~~~~~~~~~~~~~~~~~~",  # 12
		"~~~~~MMi~~~~~~~~~~~~~g..............gFFFFFF~~~~~~~~~~~~~~~~~~~~SSddd.....ddddddd~~~~~~~~~~~~~~~~~~~~",  # 13
		"~~~~~~M~~~~~~~~~~~~~~................FFFFF~~~~~~~~~~~~~~~~~~~~~SSdd....ddddddd~~~~~~~~~~~~~~~~~~~~~~",  # 14
		"~~~~~~~~~~~~~~~~~~~~~~~~~.........................................dd..ddddd~~~~~~~~~~~~~~~~~~~~~~~~~",  # 15
		"~~~~~~~~~~~~~~~~~~~~~~~~~~.........................................................................",  # 16
		"~~~~~~~~~~~~~~~~~~~~~~~~~~.........................................................................",  # 17
		"~~~~~~~~~~~~~~~~~~~~~~~~~~.........................................................................",  # 18
		"~~~~~~~~~~~~~~~~~~~~~~~~~~.........................................................................",  # 19
		# Row 20-29: Central grassland (Harmonia Village + Whispering Cave)
		"~~MMMMM~~~~~~~~~~~~~~~~~~~~~~~....gggggggggggg.........gggggg......................................",  # 20
		"~~MC..........~~~~~~~~~~~~~~~~~...ggggggggggggg........gggggggg.....................................",  # 21
		"~~MM..~~~~~~~~~~~~~~~~~~~~~~~~....ggggggggggggggg.....gggggggggg...................................",  # 22
		"~~~~..~~~~.....~~~~~~~~~~~~~~~~...ggggggggggggggg....ggggggggggg................................ccc",  # 23
		"~~~~..~~.......~~~~~~~~~~~~~~~~...gggggggggggggg....gggggggggggg...............................cccc",  # 24
		"~~~~...V.......~~~~~~~~~~~~~~~~...ggggggggggggg....ggggggggggg................................ccccc",  # 25
		"~~~~~~~.......~~~~~~~~~~~~~~~~~...gggggggggggg....gggggggggg.................................cccccc",  # 26
		"~~~~~~~........~~~~~~~~~~~~~~~~...ggggggggggg....ggggggggg..................................ccccccc",  # 27
		"~~~~~~~.......gggggg...............gggggggggg...gggggggg...................................cccccccc",  # 28
		"~~~~~~~~.....gggggggg..............ggggggggg...ggggggg....................................ccccccccc",  # 29
		# Row 30-39: Central-south transition
		"~~~~~~~~....ggggggggggg.............gggggggg..ggggggg....................................cccccccccc",  # 30
		"~~~~~~~~~..ggggggggggggg............ggggggg..gggggg.....................................ccccccccccc",  # 31
		"~~~~~~~~~~ggggggggggggggg...........gggggg..ggggg......................................cccccccccccc",  # 32
		"~~~~~~~~~~ggggggggggggggg............ggggg.gggg.......................................ccccccc~~~ccc",  # 33
		"~~~~~~~~~ggggggggggggggg.............gggg.ggg........................................cccccc~~~~~cc",  # 34
		"~~~~~~~~gggggggggggggg................ggg.gg........................................ccccc~~~~~~~~c",  # 35
		"~~~~~~~ggggggggggggg...................gg.g........................................ccccc~~~~~~~~~~",  # 36
		"~~~~~~gggggggggggg..........................................................................~~~~~~",  # 37
		"~~~~~ggggggggg.................................................................................~~~~",  # 38
		"~~~~gggggggg....................................................................................~~~",  # 39
		# Row 40-49: Southern transition (Desert SW, Rivers, Volcanic SE)
		"~~~ggggggg.......................................................................................~~",  # 40
		"~~gggggg.........................................................................................~",  # 41
		"~ggggg............................................................................................",  # 42
		"gggg..............................................................................................",  # 43
		"ggg...............................................................................................",  # 44
		"gg................................................................................................",  # 45
		"g..............................~~...............~~.............................................~~~~",  # 46
		"..............................~~~~.............~~~~...........................................~~~~~~",  # 47
		".............................~~~~~~...........~~~~~~.........................................~~~~~~~~",  # 48
		"............................~~~~~~~~.........~~~~~~~~........................................~~~~~~~~",  # 49
		# Row 50-59: Desert and Volcanic regions
		"ssssssssssssssss............~~~~~~~~~~BBB~~~~~~~~~~............................MMMMMM~~~~MMM~~~~~~~~",  # 50
		"sssssssssssssssss..........~~~~~~~~~~~...~~~~~~~~~~...........................MMMMMMlllMMMMM~~~~~~~~",  # 51
		"ssssssssssssssssss.........~~~~~~~~~~~...~~~~~~~~~~..........................MMMMMlllllMMMMM~~~~~~~~",  # 52
		"ssssssssss..sssssss........~~~~~~~~~~~...~~~~~~~~~~.........................MMMMlllllllMMMMMM~~~~~~~",  # 53
		"sssssssss....sssssss.......~~~~~~~~~~~...~~~~~~~~~~........................MMMMllll.llllMMMMM~~~~~~~",  # 54
		"ssssssss..D...ssssss.......~~~~~~~~~~~...~~~~~~~~~~.......................MMMlllll...lllMMMM~~~~~~~~",  # 55
		"sssssss.......ssssss.......~~~~~~~~~~~...~~~~~~~~~~......................MMlllll..4..lllMMM~~~~~~~~~",  # 56
		"ssssssss..3..sssssss.......~~~~~~~~~~~.P.~~~~~~~~~~.....................MMlllll......lllMM~~~~~~~~~~",  # 57
		"sssssssss....sssssss.......~~~~~~~~~~~...~~~~~~~~~~....................MMllllll..I..llllMM~~~~~~~~~~",  # 58
		"ssssssssss..sssssssss......~~~~~~~~~~~...~~~~~~~~~~...................MMlllllll.....lllMM~~~~~~~~~~~",  # 59
		# Row 60-69: Southern edge
		"sssssssssssssssssssss......~~~~~~~~~~~~.~~~~~~~~~~~~..................MMMllllllllllllllMM~~~~~~~~~~~",  # 60
		"ssssssssssssssssssssss.....~~~~~~~~~~~~~~~~~~~~~~~~~.................MMMMlllllllllllMMM~~~~~~~~~~~~",  # 61
		"sssssssssssssssssssssss....~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.............MMMMMlllllllMMMMM~~~~~~~~~~~~~",  # 62
		"ssssssssssssssssssssssss...~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~............MMMMMMlllllMMMMMM~~~~~~~~~~~~~",  # 63
		"sssssssssssssssssssssssss..~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~...........MMMMMMMlllMMMMMMM~~~~~~~~~~~~~~",  # 64
		"ssssssssssssssssssssssssss.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~..........MMMMMMMMMMMMMMMM~~~~~~~~~~~~~~",  # 65
		"ssssssssssssssssssssssssss~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.........MMMMMMMMMMMMMM~~~~~~~~~~~~~~~~",  # 66
		"ssssssssssssssssssssssssss~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~........MMMMMMMMMMMMM~~~~~~~~~~~~~~~~~",  # 67
		"ssssssssssssssssssssssssss~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.......MMMMMMMMMMMM~~~~~~~~~~~~~~~~~~",  # 68
		"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~",  # 69
	]

	# Ensure map_data matches expected dimensions
	while map_data.size() < MAP_HEIGHT:
		var pad = ""
		for _x in range(MAP_WIDTH):
			pad += "~"
		map_data.append(pad)

	# Convert map_data to tiles
	var tile_counts = {}
	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "~"
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			tile_counts[tile_type] = tile_counts.get(tile_type, 0) + 1

			# Mark special locations
			_register_spawn_point(char, x, y)

	print("Tile counts: ", tile_counts)

	# Default spawn point (near Harmonia village)
	spawn_points["default"] = spawn_points.get("village_entrance", Vector2(MAP_WIDTH / 2 * TILE_SIZE, MAP_HEIGHT / 2 * TILE_SIZE))


func _register_spawn_point(char: String, x: int, y: int) -> void:
	var pos = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)
	match char:
		"C": spawn_points["cave_entrance"] = pos
		"V": spawn_points["village_entrance"] = pos
		"1": spawn_points["ice_dragon_cave"] = pos
		"2": spawn_points["shadow_dragon_cave"] = pos
		"3": spawn_points["lightning_dragon_cave"] = pos
		"4": spawn_points["fire_dragon_cave"] = pos
		"W": spawn_points["frosthold_entrance"] = pos
		"E": spawn_points["eldertree_entrance"] = pos
		"G": spawn_points["grimhollow_entrance"] = pos
		"D": spawn_points["sandrift_entrance"] = pos
		"I": spawn_points["ironhaven_entrance"] = pos
		"P": spawn_points["steampunk_portal"] = pos


func _char_to_tile_type(char: String) -> int:
	match char:
		"~": return TileGeneratorScript.TileType.WATER
		"M": return TileGeneratorScript.TileType.MOUNTAIN
		".": return TileGeneratorScript.TileType.PATH
		"g": return TileGeneratorScript.TileType.GRASS
		"C": return TileGeneratorScript.TileType.CAVE_ENTRANCE
		"V": return TileGeneratorScript.TileType.VILLAGE_GATE
		"F": return TileGeneratorScript.TileType.FOREST
		"B": return TileGeneratorScript.TileType.BRIDGE
		# Biome tiles
		"s": return TileGeneratorScript.TileType.SAND if TileGeneratorScript.TileType.has("SAND") else TileGeneratorScript.TileType.PATH
		"i": return TileGeneratorScript.TileType.ICE if TileGeneratorScript.TileType.has("ICE") else TileGeneratorScript.TileType.PATH
		"S": return TileGeneratorScript.TileType.SWAMP if TileGeneratorScript.TileType.has("SWAMP") else TileGeneratorScript.TileType.GRASS
		"d": return TileGeneratorScript.TileType.DARK_GROUND if TileGeneratorScript.TileType.has("DARK_GROUND") else TileGeneratorScript.TileType.PATH
		"c": return TileGeneratorScript.TileType.COAST if TileGeneratorScript.TileType.has("COAST") else TileGeneratorScript.TileType.PATH
		"l": return TileGeneratorScript.TileType.LAVA if TileGeneratorScript.TileType.has("LAVA") else TileGeneratorScript.TileType.MOUNTAIN
		# Special locations map to visual tiles
		"1", "2", "3", "4": return TileGeneratorScript.TileType.CAVE_ENTRANCE
		"W", "E", "G", "D", "I": return TileGeneratorScript.TileType.VILLAGE_GATE
		"P": return TileGeneratorScript.TileType.BRIDGE  # Portal uses bridge tile
		_: return TileGeneratorScript.TileType.GRASS


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	# Harmonia Village
	_add_area_transition("VillageEntrance", "harmonia_village", "entrance",
		spawn_points.get("village_entrance", Vector2(320, 224)), "Enter Harmonia")

	# Whispering Cave - spawn on adjacent path, not inside mountain
	var cave_pos = spawn_points.get("cave_entrance", Vector2(96, 96))
	_add_area_transition("CaveEntrance", "whispering_cave", "entrance", cave_pos, "Enter Cave")
	spawn_points["cave_entrance"] = cave_pos + Vector2(TILE_SIZE, 0)  # Path next to cave

	# Dragon caves
	_add_area_transition("IceDragonCave", "ice_dragon_cave", "entrance",
		spawn_points.get("ice_dragon_cave", Vector2.ZERO), "Enter Glacial Sanctum")
	_add_area_transition("ShadowDragonCave", "shadow_dragon_cave", "entrance",
		spawn_points.get("shadow_dragon_cave", Vector2.ZERO), "Enter Abyssal Hollow")
	_add_area_transition("LightningDragonCave", "lightning_dragon_cave", "entrance",
		spawn_points.get("lightning_dragon_cave", Vector2.ZERO), "Enter Stormspire")
	_add_area_transition("FireDragonCave", "fire_dragon_cave", "entrance",
		spawn_points.get("fire_dragon_cave", Vector2.ZERO), "Enter Infernal Grotto")

	# Villages
	_add_area_transition("FrostholdEntrance", "frosthold_village", "entrance",
		spawn_points.get("frosthold_entrance", Vector2.ZERO), "Enter Frosthold")
	_add_area_transition("EldertreeEntrance", "eldertree_village", "entrance",
		spawn_points.get("eldertree_entrance", Vector2.ZERO), "Enter Eldertree")
	_add_area_transition("GrimhollowEntrance", "grimhollow_village", "entrance",
		spawn_points.get("grimhollow_entrance", Vector2.ZERO), "Enter Grimhollow")
	_add_area_transition("SandriftEntrance", "sandrift_village", "entrance",
		spawn_points.get("sandrift_entrance", Vector2.ZERO), "Enter Sandrift")
	_add_area_transition("IronhavenEntrance", "ironhaven_village", "entrance",
		spawn_points.get("ironhaven_entrance", Vector2.ZERO), "Enter Ironhaven")

	# Steampunk portal
	_add_area_transition("SteampunkPortal", "steampunk_overworld", "entrance",
		spawn_points.get("steampunk_portal", Vector2.ZERO), "??? Gateway ???")


func _add_area_transition(trans_name: String, target_map: String, target_spawn: String,
		pos: Vector2, indicator: String) -> void:
	if pos == Vector2.ZERO:
		return  # Skip if spawn point not found in map
	var trans = AreaTransitionScript.new()
	trans.name = trans_name
	trans.target_map = target_map
	trans.target_spawn = target_spawn
	trans.require_interaction = true
	trans.indicator_text = indicator
	trans.position = pos
	_setup_transition_collision(trans, Vector2(TILE_SIZE, TILE_SIZE))
	trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(trans)


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


func _setup_player() -> void:
	player = OverworldPlayerScript.new()
	player.name = "Player"
	player.position = spawn_points.get("default", Vector2(320, 256))
	player.set_job("fighter")
	add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"

	player.add_child(camera)
	camera.make_current()

	camera.zoom = Vector2(2.0, 2.0)

	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = MAP_WIDTH * TILE_SIZE
	camera.limit_bottom = MAP_HEIGHT * TILE_SIZE

	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0


func _setup_controller() -> void:
	controller = OverworldControllerScript.new()
	controller.name = "Controller"
	controller.player = player
	controller.encounter_enabled = true
	controller.current_area_id = "overworld"

	# Default central zone encounters
	controller.set_area_config("overworld_central", false, 0.05, ["slime", "bat", "goblin"])

	controller.battle_triggered.connect(_on_battle_triggered)
	controller.menu_requested.connect(_on_menu_requested)

	add_child(controller)


## Regional encounter zones based on player position
func _update_encounter_zone(pos: Vector2) -> void:
	var tile_x = int(pos.x / TILE_SIZE)
	var tile_y = int(pos.y / TILE_SIZE)
	var new_zone = _get_zone_for_tile(tile_x, tile_y)
	if new_zone != _current_zone:
		_current_zone = new_zone
		_apply_zone_encounters(new_zone)


func _get_zone_for_tile(tx: int, ty: int) -> String:
	# NW quadrant: Ice/Snow (top-left)
	if tx < 30 and ty < 15:
		return "ice"
	# N quadrant: Forest (top-center)
	if tx >= 20 and tx < 65 and ty < 15:
		return "forest"
	# NE quadrant: Swamp/Spooky (top-right)
	if tx >= 60 and ty < 15:
		return "swamp"
	# SW quadrant: Desert (bottom-left)
	if tx < 35 and ty >= 50:
		return "desert"
	# SE quadrant: Volcanic (bottom-right)
	if tx >= 65 and ty >= 50:
		return "volcanic"
	# E side: Coast
	if tx >= 85 and ty >= 20 and ty < 45:
		return "coast"
	# Central: Grassland
	return "central"


func _apply_zone_encounters(zone: String) -> void:
	match zone:
		"central":
			controller.set_area_config("overworld_central", false, 0.05, ["slime", "bat", "goblin"])
		"forest":
			controller.set_area_config("overworld_forest", false, 0.06, ["wolf", "spider", "fungoid"])
		"ice":
			controller.set_area_config("overworld_ice", false, 0.06, ["ice_wolf", "skeleton", "specter"])
		"swamp":
			controller.set_area_config("overworld_swamp", false, 0.07, ["snake", "ghost", "imp"])
		"desert":
			controller.set_area_config("overworld_desert", false, 0.07, ["viper", "elemental", "skeleton"])
		"volcanic":
			controller.set_area_config("overworld_volcanic", false, 0.08, ["imp", "skeleton", "troll"])
		"coast":
			controller.set_area_config("overworld_coast", false, 0.05, ["slime", "bat", "spider"])


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

	_add_boundary_wall(bounds, Vector2(map_w / 2, -wall_thickness / 2), Vector2(map_w + wall_thickness * 2, wall_thickness))
	_add_boundary_wall(bounds, Vector2(map_w / 2, map_h + wall_thickness / 2), Vector2(map_w + wall_thickness * 2, wall_thickness))
	_add_boundary_wall(bounds, Vector2(-wall_thickness / 2, map_h / 2), Vector2(wall_thickness, map_h + wall_thickness * 2))
	_add_boundary_wall(bounds, Vector2(map_w + wall_thickness / 2, map_h / 2), Vector2(wall_thickness, map_h + wall_thickness * 2))


func _add_boundary_wall(parent: StaticBody2D, pos: Vector2, size: Vector2) -> void:
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	collision.position = pos
	parent.add_child(collision)
