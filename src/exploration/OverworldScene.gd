extends Node2D
class_name OverworldScene

## OverworldScene - Main overworld exploration scene
## 100x70 tile world with 6 terrain biomes, villages, caves, and regional encounters

const TileGeneratorScript = preload("res://src/exploration/TileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")
const MonsterSpawnerScript = preload("res://src/exploration/MonsterSpawner.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array, terrain: String)
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

## Roaming monster spawner
var monster_spawner: Node  # MonsterSpawner

## Spawn points
var spawn_points: Dictionary = {}

## Current encounter zone
var _current_zone: String = "central"
var _last_tile_pos: Vector2i = Vector2i(-1, -1)

## Mode 7 perspective
var mode7_enabled: bool = true
var _mode7: Mode7Overlay
var _zone_popup: ZoneNamePopup
var _danger_zone: DangerZone
var _minimap: OverworldMinimap
var _zone_particles: ZoneParticles
var _quest_tracker: QuestTracker
var _weather: WeatherSystem
var _border_indicator: MapBorderIndicator


func _ready() -> void:
	_setup_scene()
	_generate_map()
	_setup_transitions()
	_setup_player()
	_setup_camera()
	_setup_controller()
	_setup_monster_spawner()

	if mode7_enabled:
		_mode7 = Mode7Overlay.new()
		add_child(_mode7)
		_mode7.apply_preset("medieval")
		_mode7.setup(self, player)

	_zone_popup = ZoneNamePopup.new()
	add_child(_zone_popup)
	_zone_popup.setup(self)

	# Danger zone warnings near boss caves
	var danger_pts: Array[Vector2] = []
	for key in ["cave_entrance", "ice_dragon_cave", "shadow_dragon_cave", "lightning_dragon_cave", "fire_dragon_cave"]:
		if spawn_points.has(key):
			danger_pts.append(spawn_points[key])
	if not danger_pts.is_empty():
		_danger_zone = DangerZone.new()
		add_child(_danger_zone)
		_danger_zone.setup(self, player, danger_pts)

	# Minimap with transition dots
	_minimap = OverworldMinimap.new()
	add_child(_minimap)
	_minimap.setup(self, player, MAP_WIDTH, MAP_HEIGHT, TILE_SIZE, spawn_points)
	_minimap.set_objective(_get_objective_position())

	# Zone ambient particles (leaves, snow, dust, etc.)
	_zone_particles = ZoneParticles.new()
	add_child(_zone_particles)
	_zone_particles.setup(self, player)

	# Quest objective tracker
	_quest_tracker = QuestTracker.new()
	add_child(_quest_tracker)
	_quest_tracker.setup(self)

	# Weather effects (rain, fog, etc.)
	_weather = WeatherSystem.new()
	add_child(_weather)
	_weather.setup(self, player, "medieval")

	# Map edge indicators
	_border_indicator = MapBorderIndicator.new()
	add_child(_border_indicator)
	_border_indicator.setup(self, player, MAP_WIDTH, MAP_HEIGHT, TILE_SIZE)

	# Signposts at key intersections for navigation
	_place_signposts()

	# Visual landmarks between towns
	_place_landmarks()

	# Wandering NPCs on paths between towns
	_place_wanderers()

	# Ambient details (chimney smoke, campfire glow)
	_place_ambient_effects()

	if SoundManager:
		SoundManager.play_area_music("overworld")

	# First-time tutorial hints
	TutorialHints.show(self, "quest_log")

	exploration_ready.emit()


func _process(_delta: float) -> void:
	if player:
		_update_encounter_zone(player.position)
		if _minimap:
			_minimap.update(player.position)
		if _zone_particles:
			_zone_particles.update_position(player.position)
		if _border_indicator:
			_border_indicator.update(player.position)
	if _danger_zone:
		_danger_zone.process(_delta)
	if _quest_tracker:
		_quest_tracker.update()
	if _mode7:
		_mode7.process_frame()
	if _weather:
		_weather.process(_delta)


func _exit_tree() -> void:
	if _mode7:
		_mode7.cleanup()


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
		"~~~~MMMii~~~~~..B..~~g..............gFFFFFFF~~~~~~~~~~~~~~~~~~~Sddddd......ddddddd~~~~~~~~~~~~~~~~~~",  # 12
		"~~~~~MMi~~~~~~.....~~g..............gFFFFFF~~~~~~~~~~~~~~~~~~~~SSddd.....ddddddd~~~~~~~~~~~~~~~~~~~~",  # 13
		"~~~~~~M~~~~~~~..B..~~................FFFFF~~~~~~~~~~~~~~~~~~~~~SSdd....ddddddd~~~~~~~~~~~~~~~~~~~~~~",  # 14
		"~~~~~~~~~~~~~~~~~~~~~~~~~.........................................dd..ddddd~~~~~~~~~~~~~~~~~~~~~~~~~",  # 15
		"~~~~~~~~~~~~~~~~~~~~~~~~~~.........................................................................",  # 16
		"~~~~~~~~~~~~~~~~~~~~~~~~~~.........................................................................",  # 17
		"~~~~~~~~~~~~~~~~~~~~~~~~~~.........................................................................",  # 18
		"~~~~~~~~~~~~~~~~~~~~~~~~~~.........................................................................",  # 19
		# Row 20-29: Central grassland (Harmonia Village + Whispering Cave)
		"~~MMMMM~~~~~~~~~~~~~~~~~~~~~~~....gggggggggggg.........gggggg......................................",  # 20
		"~~.C..........~~~~~~~~~~~~~~~~~...ggggggggggggg........gggggggg.....................................",  # 21
		"~~M...........~~~~~~~~~~~~~~~~....ggggggggggggggg.....gggggggggg...................................",  # 22
		"~~~~.............BB........BB.....ggggggggggggggg....ggggggggggg................................ccc",  # 23
		"~~~~.............BB........BB.....gggggggggggggg....gggggggggggg...............................cccc",  # 24
		"~~~~...V.........BB........BB.....ggggggggggggg....ggggggggggg................................ccccc",  # 25
		"~~~~~~~..........BB........BB.....gggggggggggg....gggggggggg.................................cccccc",  # 26
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
		"ssssssssss..sssssss........~~~~~~~~~~~...~~~~~~~~~~.........................MMMMlllllll.MMMMM~~~~~~~",  # 53
		"sssssssss....sssssss.......~~~~~~~~~~~...~~~~~~~~~~........................MMMlllll.llll.MMMM~~~~~~~",  # 54
		"ssssssss..D...ssssss.......~~~~~~~~~~~...~~~~~~~~~~.......................MMMlllll...lll..MM~~~~~~~~",  # 55
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

	# Default spawn: central grassland (column 40, row 25 — clear of water)
	spawn_points["default"] = Vector2(40 * TILE_SIZE + TILE_SIZE / 2, 25 * TILE_SIZE + TILE_SIZE / 2)


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

	# World progression portal — leads to next world (W2 Suburban)
	# Only visible after W1 boss is defeated (or world 2+ is unlocked)
	if GameState.is_world_unlocked(2) or GameState.get_story_flag("w1_boss_defeated"):
		_add_area_transition("WorldPortal", "suburban_overworld", "entrance",
			spawn_points.get("steampunk_portal", Vector2.ZERO), "Enter the Mundane Sprawl")


func _add_area_transition(trans_name: String, target_map: String, target_spawn: String,
		pos: Vector2, indicator: String) -> void:
	if pos == Vector2.ZERO:
		return  # Skip if spawn point not found in map
	print("[SETUP] Transition '%s' → %s at pos %s" % [trans_name, target_map, pos])
	var trans = AreaTransitionScript.new()
	trans.name = trans_name
	trans.target_map = target_map
	trans.target_spawn = target_spawn
	trans.require_interaction = false  # Auto-enter on contact (no button press needed)
	trans.indicator_text = indicator
	trans.position = pos
	_setup_transition_collision(trans, Vector2(TILE_SIZE * 5, TILE_SIZE * 5))  # 5x5 tiles for generous entry
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
	var leader = GameState.get_party_leader()
	var job_id = leader.get("job_id", "fighter") if leader else "fighter"
	player.set_job(job_id)
	add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"

	player.add_child(camera)
	camera.make_current()

	Mode7Overlay.apply_camera(camera, mode7_enabled)
	Mode7Overlay.apply_camera_limits(camera, MAP_WIDTH, MAP_HEIGHT, TILE_SIZE)

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


func _setup_monster_spawner() -> void:
	monster_spawner = MonsterSpawnerScript.new()
	monster_spawner.name = "MonsterSpawner"
	monster_spawner.monster_touched.connect(_on_roaming_monster_touched)
	add_child(monster_spawner)
	monster_spawner.setup(player, ["slime", "bat", "goblin"])


## Regional encounter zones based on player position
func _update_encounter_zone(pos: Vector2) -> void:
	var tile_pos = Vector2i(int(pos.x / TILE_SIZE), int(pos.y / TILE_SIZE))
	if tile_pos == _last_tile_pos:
		return
	_last_tile_pos = tile_pos
	var new_zone = _get_zone_for_tile(tile_pos.x, tile_pos.y)
	if new_zone != _current_zone:
		_current_zone = new_zone
		_apply_zone_encounters(new_zone)
		if _zone_popup:
			_zone_popup.show_zone(new_zone)
		if _zone_particles:
			_zone_particles.update_zone(new_zone)
		_update_zone_ambient(new_zone)


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
	var pool: Array = []
	match zone:
		"central":
			pool = ["slime", "bat", "goblin"]
			controller.set_area_config("overworld_central", false, 0.05, pool)
		"forest":
			pool = ["wolf", "spider", "goblin"]
			controller.set_area_config("overworld_forest", false, 0.06, pool)
		"ice":
			pool = ["skeleton", "wolf", "goblin"]
			controller.set_area_config("overworld_ice", false, 0.06, pool)
		"swamp":
			pool = ["snake", "ghost", "imp"]
			controller.set_area_config("overworld_swamp", false, 0.07, pool)
		"desert":
			pool = ["skeleton", "snake", "goblin"]
			controller.set_area_config("overworld_desert", false, 0.07, pool)
		"volcanic":
			pool = ["imp", "skeleton", "troll"]
			controller.set_area_config("overworld_volcanic", false, 0.08, pool)
		"coast":
			pool = ["slime", "bat", "spider"]
			controller.set_area_config("overworld_coast", false, 0.05, pool)
	if monster_spawner and not pool.is_empty():
		monster_spawner.set_enemy_pool(pool)


func _place_wanderers() -> void:
	var wanderers = [
		{
			"name": "Merchant",
			"dialogue": "Harmonia's got the best prices... if you can find it.",
			"color": Color(0.5, 0.35, 0.2),
			"path": [Vector2(30, 23), Vector2(20, 23), Vector2(20, 26), Vector2(30, 26)],
			"hints": [
				{"flag": "", "text": "Head west across the bridges — Harmonia Village is just past them."},
				{"flag": "prologue_complete", "text": "Elder Theron mentioned a cave northwest of the village. Sounds dangerous."},
				{"flag": "chapter1_complete", "text": "The Whispering Cave? Northwest of here. Bring potions."},
				{"flag": "rat_king_defeated", "text": "A strange light appeared to the south... some kind of portal?"},
				{"flag": "w1_boss_defeated", "text": "That portal south of the bridge leads somewhere... different."},
			],
		},
		{
			"name": "Lost Pilgrim",
			"dialogue": "I've been walking north for hours... is there a village up here?",
			"color": Color(0.4, 0.4, 0.6),
			"path": [Vector2(28, 10), Vector2(28, 14), Vector2(30, 14), Vector2(30, 10)],
			"hints": [
				{"flag": "", "text": "I heard there's a village to the west. Follow the bridges!"},
				{"flag": "prologue_complete", "text": "Frosthold is up north in the ice fields. Eldertree is in the forest."},
				{"flag": "chapter3_complete", "text": "Something terrible lurks in that cave... the ground shakes at night."},
				{"flag": "w1_boss_defeated", "text": "The world feels... wider now. Like a door opened somewhere."},
			],
		},
		{
			"name": "Retired Guard",
			"dialogue": "Don't go near the cave. Trust me on this one.",
			"color": Color(0.55, 0.45, 0.35),
			"path": [Vector2(12, 20), Vector2(12, 24), Vector2(8, 24), Vector2(8, 20)],
			"hints": [
				{"flag": "", "text": "Harmonia Village is just south of here. Talk to Elder Theron."},
				{"flag": "prologue_complete", "text": "The cave northwest of the village... it whispers at night."},
				{"flag": "chapter1_complete", "text": "That cave goes deep. Five floors, they say. A king of rats at the bottom."},
				{"flag": "rat_king_defeated", "text": "You actually beat it? Head south — a portal appeared near the river."},
				{"flag": "w1_boss_defeated", "text": "Beyond the portal... they say the world looks completely different."},
			],
		},
	]
	for w in wanderers:
		var npc = WanderingNPC.new()
		npc.npc_name = w["name"]
		npc.dialogue = w["dialogue"]
		npc.sprite_color = w["color"]
		if w.has("hints"):
			npc.dialogue_hints = w["hints"]
		var patrol: Array[Vector2] = []
		for pt in w["path"]:
			patrol.append(Vector2(pt.x * TILE_SIZE + TILE_SIZE / 2, pt.y * TILE_SIZE + TILE_SIZE / 2))
		npc.set_patrol(patrol)
		add_child(npc)


func _place_ambient_effects() -> void:
	## Chimney smoke at village locations + campfire flicker at rest areas
	var smoke_positions = [
		spawn_points.get("village_entrance", Vector2.ZERO),
		spawn_points.get("frosthold_entrance", Vector2.ZERO),
		spawn_points.get("eldertree_entrance", Vector2.ZERO),
		spawn_points.get("grimhollow_entrance", Vector2.ZERO),
		spawn_points.get("sandrift_entrance", Vector2.ZERO),
		spawn_points.get("ironhaven_entrance", Vector2.ZERO),
	]
	for pos in smoke_positions:
		if pos == Vector2.ZERO:
			continue
		var smoke = CPUParticles2D.new()
		smoke.name = "ChimneySmoke"
		smoke.position = pos + Vector2(0, -12)
		smoke.amount = 6
		smoke.lifetime = 2.5
		smoke.one_shot = false
		smoke.explosiveness = 0.0
		smoke.randomness = 0.4
		smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		smoke.emission_rect_extents = Vector2(8, 2)
		smoke.gravity = Vector2(3.0, -18.0)
		smoke.initial_velocity_min = 2.0
		smoke.initial_velocity_max = 6.0
		smoke.scale_amount_min = 0.4
		smoke.scale_amount_max = 1.0
		smoke.color = Color(0.6, 0.6, 0.6, 0.25)
		smoke.z_index = 2
		add_child(smoke)


func _update_zone_ambient(zone: String) -> void:
	if not SoundManager:
		return
	var ambient_key = ""
	match zone:
		"forest": ambient_key = "ambient_forest"
		"ice": ambient_key = "ambient_cave"
		"coast": ambient_key = "ambient_coast"
		"central": ambient_key = "ambient_plains"
		"desert": ambient_key = "ambient_plains"
		"swamp": ambient_key = "ambient_forest"
		"volcanic": ambient_key = "ambient_dungeon"
	if ambient_key != "":
		SoundManager.play_ambient(ambient_key)
	else:
		SoundManager.stop_ambient()


func _place_landmarks() -> void:
	var landmarks = [
		# Ruins along the northern forest path
		{"pos": Vector2(28, 12), "type": Landmark.Type.RUINS},
		# Campfire at the central rest area
		{"pos": Vector2(38, 22), "type": Landmark.Type.CAMPFIRE},
		# Stone circle in the swamp region
		{"pos": Vector2(68, 10), "type": Landmark.Type.STONE_CIRCLE},
		# Well near Harmonia village approach
		{"pos": Vector2(15, 24), "type": Landmark.Type.WELL},
		# Ancient statue near the ice region bridge
		{"pos": Vector2(18, 13), "type": Landmark.Type.STATUE},
		# Campfire on the southern desert road
		{"pos": Vector2(20, 45), "type": Landmark.Type.CAMPFIRE},
		# Ruins near the volcanic approach
		{"pos": Vector2(65, 48), "type": Landmark.Type.RUINS},
		# Stone circle near the bridge
		{"pos": Vector2(38, 50), "type": Landmark.Type.STONE_CIRCLE},
	]
	for l in landmarks:
		var lm = Landmark.new()
		lm.landmark_type = l["type"]
		lm.position = Vector2(l["pos"].x * TILE_SIZE + TILE_SIZE / 2, l["pos"].y * TILE_SIZE + TILE_SIZE / 2)
		add_child(lm)


func _get_objective_position() -> Vector2:
	## Return the world position of the current quest objective for minimap highlighting.
	if GameState.get_story_flag("rat_king_defeated") or GameState.get_story_flag("w1_boss_defeated"):
		return spawn_points.get("steampunk_portal", Vector2.ZERO)
	if GameState.get_story_flag("chapter1_complete"):
		return spawn_points.get("cave_entrance", Vector2.ZERO)
	return spawn_points.get("village_entrance", Vector2.ZERO)


func _place_signposts() -> void:
	var signs = [
		# Near default spawn — point toward village and cave
		{"pos": Vector2(35, 24), "text": "← Harmonia Village"},
		{"pos": Vector2(35, 20), "text": "↑ Whispering Cave"},
		# Central crossroads
		{"pos": Vector2(30, 15), "text": "↑ Eldertree / ← Frosthold"},
		{"pos": Vector2(50, 15), "text": "→ Grimhollow / Dark Lands"},
		# Southern crossroads
		{"pos": Vector2(25, 40), "text": "↓ Sandrift / Desert"},
		{"pos": Vector2(40, 48), "text": "↓ Bridge / Portal South"},
		# Near bridge
		{"pos": Vector2(38, 52), "text": "← Desert  →Volcanic"},
	]
	for s in signs:
		var post = Signpost.new()
		post.sign_text = s["text"]
		post.position = Vector2(s["pos"].x * TILE_SIZE + TILE_SIZE / 2, s["pos"].y * TILE_SIZE + TILE_SIZE / 2)
		add_child(post)


func _on_transition_triggered(target_map: String, spawn_point: String) -> void:
	# Dissolve effect for world-to-world portal transitions
	if "overworld" in target_map and _mode7:
		InputLockManager.push_lock("world_transition")
		await _mode7.play_dissolve_out()
		InputLockManager.pop_lock("world_transition")
	area_transition.emit(target_map, spawn_point)


func _on_battle_triggered(enemies: Array) -> void:
	print("[OVERWORLD] Re-emitting battle_triggered: %s" % [enemies])
	# NOTE: GameLoop expects (enemies, terrain) — pass terrain to match signature
	var terrain = _get_terrain_for_zone(_current_zone)
	battle_triggered.emit(enemies, terrain)


func _get_terrain_for_zone(zone: String) -> String:
	match zone:
		"forest": return "forest"
		"ice": return "ice"
		"swamp": return "swamp"
		"desert": return "desert"
		"volcanic": return "volcanic"
		"coast": return "coast"
		_: return "plains"


func _on_roaming_monster_touched(monster_id: String, _monster_types: Array) -> void:
	# GameLoop sets LoopState.BATTLE — no need for can_move
	var enemies = [monster_id]
	var extra = randi_range(0, 2)
	for _i in range(extra):
		enemies.append(monster_id)
	battle_triggered.emit(enemies, _get_terrain_for_zone(_current_zone))


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
	if monster_spawner:
		monster_spawner.set_enabled(true)


## Pause exploration
func pause() -> void:
	controller.pause_exploration()
	if monster_spawner:
		monster_spawner.set_enabled(false)


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
