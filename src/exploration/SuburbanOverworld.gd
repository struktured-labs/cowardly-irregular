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
signal battle_triggered(enemies: Array, terrain: String)
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

## Mode 7 perspective
var mode7_enabled: bool = true
var _mode7: Mode7Overlay
var _minimap: OverworldMinimap

## Zone particles
var _zone_particles: ZoneParticles

var _quest_tracker: QuestTracker
var _weather: WeatherSystem
var _border_indicator: MapBorderIndicator
var _objective_arrow: ObjectiveArrow
var _threat_meter: ThreatMeter
var monster_spawner: MonsterSpawner
var _save_point: SavePoint

## Rain effect state
var _rain_particles: CPUParticles2D
var _rain_timer: float = 0.0
var _rain_interval: float = 0.0
var _rain_active: bool = false


func _ready() -> void:
	_setup_scene()
	_generate_map()
	_setup_transitions()
	_setup_npcs()
	_setup_player()
	_setup_camera()
	_setup_controller()

	if mode7_enabled:
		_mode7 = Mode7Overlay.new()
		add_child(_mode7)
		_mode7.apply_preset("suburban")
		_mode7.setup(self, player)

	# Zone name popup
	var _zone_popup = ZoneNamePopup.new()
	add_child(_zone_popup)
	_zone_popup.setup(self)
	_zone_popup.show_zone("suburban_overworld")

	_zone_particles = ZoneParticles.new()
	add_child(_zone_particles)
	_zone_particles.setup(self, player)
	_zone_particles.update_zone("suburban_overworld")

	GameState.set_story_flag("w2_entered")
	_quest_tracker = QuestTracker.new()
	add_child(_quest_tracker)
	_quest_tracker.setup(self)

	_weather = WeatherSystem.new()
	add_child(_weather)
	_weather.setup(self, player, "suburban")

	_place_signposts()
	_place_landmarks()
	_place_wanderers()
	_place_village_markers()
	_place_treasure_chests()
	_place_save_point()
	_place_ambient_effects()

	# Start suburban overworld music
	if SoundManager:
		SoundManager.play_area_music("overworld_suburban")

	_setup_effects()
	_minimap = OverworldMinimap.new()
	add_child(_minimap)
	_minimap.setup(self, player, MAP_WIDTH, MAP_HEIGHT, TILE_SIZE, spawn_points)
	_minimap.set_objective(_get_objective_position())

	monster_spawner = MonsterSpawner.new()
	monster_spawner.name = "MonsterSpawner"
	add_child(monster_spawner)
	monster_spawner.setup(player, ["spiteful_crow", "new_age_retro_hippie", "skate_punk", "unassuming_dog", "cranky_lady"])

	_threat_meter = ThreatMeter.new()
	add_child(_threat_meter)
	_threat_meter.setup(self, player, monster_spawner)

	_border_indicator = MapBorderIndicator.new()
	add_child(_border_indicator)
	_border_indicator.setup(self, player, MAP_WIDTH, MAP_HEIGHT, TILE_SIZE)

	_objective_arrow = ObjectiveArrow.new()
	add_child(_objective_arrow)
	_objective_arrow.setup(self, player)
	_objective_arrow.set_target(_get_objective_position())

	TutorialHints.show(self, "world_transition")
	exploration_ready.emit()


func _get_objective_position() -> Vector2:
	## W2 quest objective: reach steampunk portal (Forward) after exploring
	if GameState.get_story_flag("w2_boss_defeated"):
		return spawn_points.get("from_industrial", Vector2.ZERO)
	if GameState.get_story_flag("visited_maple_heights"):
		return Vector2(45 * TILE_SIZE, 20 * TILE_SIZE)  # Forward Portal
	return spawn_points.get("maple_heights_entrance", Vector2.ZERO)


func _place_village_markers() -> void:
	var pos = spawn_points.get("maple_heights_entrance", Vector2.ZERO)
	if pos != Vector2.ZERO:
		var marker = VillageMarker.new()
		marker.village_name = "MAPLE HEIGHTS"
		marker.roof_color = Color(0.5, 0.35, 0.25)  # Brown suburban rooftops
		marker.position = pos
		add_child(marker)


func _place_treasure_chests() -> void:
	const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")
	# 10 chests across W2 zones: residential, strip mall, park, playground
	var chests = [
		# Residential — backyard loot
		{"id": "w2_backyard_potion", "pos": Vector2(4, 7), "type": "item", "item": "hi_potion", "amount": 3},
		{"id": "w2_backyard_gold", "pos": Vector2(44, 4), "type": "gold", "gold": 200},
		# Strip mall — vending machine finds
		{"id": "w2_mall_ether", "pos": Vector2(18, 17), "type": "item", "item": "ether", "amount": 3},
		{"id": "w2_mall_antidote", "pos": Vector2(30, 18), "type": "item", "item": "antidote", "amount": 4},
		{"id": "w2_mall_gold", "pos": Vector2(42, 17), "type": "gold", "gold": 350},
		# Park / playground — kid hidden stashes
		{"id": "w2_park_phoenix", "pos": Vector2(6, 28), "type": "item", "item": "phoenix_down", "amount": 1},
		{"id": "w2_park_remedy", "pos": Vector2(14, 30), "type": "item", "item": "remedy", "amount": 3},
		{"id": "w2_court_elixir", "pos": Vector2(22, 28), "type": "item", "item": "elixir", "amount": 1},
		# South edge — near forward portal
		{"id": "w2_portal_gold", "pos": Vector2(48, 24), "type": "gold", "gold": 600},
		# Bus stop hidden
		{"id": "w2_bus_hipotion", "pos": Vector2(40, 32), "type": "item", "item": "hi_potion", "amount": 4},
	]
	for c in chests:
		var chest = TreasureChestScript.new()
		chest.chest_id = c["id"]
		chest.position = Vector2(c["pos"].x * TILE_SIZE + TILE_SIZE / 2, c["pos"].y * TILE_SIZE + TILE_SIZE / 2)
		if c["type"] == "gold":
			chest.contents_type = "gold"
			chest.gold_amount = c["gold"]
		else:
			chest.contents_type = "item"
			chest.contents_id = c["item"]
			chest.contents_amount = c["amount"]
		add_child(chest)


func _place_save_point() -> void:
	# Save point near main road crossroads
	_save_point = SavePoint.new()
	_save_point.position = Vector2(25 * TILE_SIZE + TILE_SIZE / 2, 14 * TILE_SIZE + TILE_SIZE / 2)
	add_child(_save_point)


func _place_ambient_effects() -> void:
	# Chimney smoke over the two house rows
	var smoke_positions = [
		Vector2(4, 2), Vector2(14, 2), Vector2(26, 2), Vector2(37, 2),
		Vector2(4, 7), Vector2(14, 7), Vector2(26, 7), Vector2(37, 7),
	]
	for p in smoke_positions:
		var smoke = CPUParticles2D.new()
		smoke.name = "ChimneySmoke"
		smoke.position = Vector2(p.x * TILE_SIZE + TILE_SIZE / 2, p.y * TILE_SIZE - 4)
		smoke.amount = 5
		smoke.lifetime = 2.0
		smoke.one_shot = false
		smoke.randomness = 0.4
		smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		smoke.emission_rect_extents = Vector2(6, 2)
		smoke.gravity = Vector2(2.0, -15.0)
		smoke.initial_velocity_min = 2.0
		smoke.initial_velocity_max = 5.0
		smoke.scale_amount_min = 0.3
		smoke.scale_amount_max = 0.9
		smoke.color = Color(0.7, 0.7, 0.72, 0.22)
		smoke.z_index = 2
		add_child(smoke)


func _place_signposts() -> void:
	var signs = [
		{"pos": Vector2(25, 10), "text": "↑ Maple Heights"},
		{"pos": Vector2(25, 36), "text": "↓ Return Portal"},
		{"pos": Vector2(45, 20), "text": "→ Forward Portal"},
		{"pos": Vector2(8, 25), "text": "← Park / Playground"},
	]
	for s in signs:
		var post = Signpost.new()
		post.sign_text = s["text"]
		post.position = Vector2(s["pos"].x * TILE_SIZE + TILE_SIZE / 2, s["pos"].y * TILE_SIZE + TILE_SIZE / 2)
		add_child(post)


func _place_landmarks() -> void:
	var landmarks = [
		{"pos": Vector2(25, 5), "type": Landmark.Type.FIRE_HYDRANT},
		{"pos": Vector2(40, 30), "type": Landmark.Type.BUS_STOP},
		{"pos": Vector2(10, 35), "type": Landmark.Type.FIRE_HYDRANT},
		{"pos": Vector2(35, 15), "type": Landmark.Type.BUS_STOP},
	]
	for l in landmarks:
		var lm = Landmark.new()
		lm.landmark_type = l["type"]
		lm.position = Vector2(l["pos"].x * TILE_SIZE + TILE_SIZE / 2, l["pos"].y * TILE_SIZE + TILE_SIZE / 2)
		add_child(lm)


func _place_wanderers() -> void:
	var wanderers = [
		{
			"name": "Dog Walker",
			"dialogue": "Beautiful day for a walk. If you ignore the monsters.",
			"color": Color(0.6, 0.45, 0.3),
			"path": [Vector2(15, 15), Vector2(20, 15), Vector2(20, 20), Vector2(15, 20)],
			"hints": [
				{"flag": "w2_entered", "text": "Maple Heights is up north — nice neighborhood if you like picket fences."},
				{"flag": "w2_boss_defeated", "text": "Something weird opened up south of the park. Like a... gear-shaped hole?"},
			],
		},
		{
			"name": "Mail Carrier",
			"dialogue": "Nobody reads mail anymore. Nobody reads anything anymore.",
			"color": Color(0.3, 0.3, 0.65),
			"path": [Vector2(30, 10), Vector2(35, 10), Vector2(35, 15), Vector2(30, 15)],
			"hints": [
				{"flag": "w2_entered", "text": "The strip mall south of the main road has everything. Well, five stores."},
				{"flag": "w2_boss_defeated", "text": "Past the portal it smells like copper and oil. Not my kind of neighborhood."},
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


func _setup_effects() -> void:
	_rain_particles = CPUParticles2D.new()
	_rain_particles.name = "RainEffect"
	_rain_particles.z_index = 5
	_rain_particles.emitting = false
	_rain_particles.amount = 120
	_rain_particles.lifetime = 1.2
	_rain_particles.one_shot = false
	_rain_particles.explosiveness = 0.0
	_rain_particles.randomness = 0.2
	_rain_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_rain_particles.emission_rect_extents = Vector2(MAP_WIDTH * TILE_SIZE / 2.0, 8.0)
	_rain_particles.position = Vector2(MAP_WIDTH * TILE_SIZE / 2.0, -20.0)
	_rain_particles.gravity = Vector2(20.0, 600.0)
	_rain_particles.initial_velocity_min = 5.0
	_rain_particles.initial_velocity_max = 12.0
	_rain_particles.scale_amount_min = 0.5
	_rain_particles.scale_amount_max = 1.0
	_rain_particles.color = Color(0.75, 0.85, 1.0, 0.55)
	add_child(_rain_particles)
	_rain_interval = randf_range(30.0, 60.0)


func _process(delta: float) -> void:
	if _quest_tracker: _quest_tracker.update()
	if _mode7:
		_mode7.process_frame()
	if _weather:
		_weather.process(delta)
	_rain_timer += delta
	if _rain_timer >= _rain_interval:
		_rain_timer = 0.0
		_rain_active = !_rain_active
		_rain_particles.emitting = _rain_active
		if _rain_active:
			_rain_interval = randf_range(20.0, 40.0)
		else:
			_rain_interval = randf_range(30.0, 60.0)
	if player:
		if _zone_particles:
			_zone_particles.update_position(player.position)
		if _minimap:
			_minimap.update(player.position)
		if _objective_arrow:
			_objective_arrow.update(player.position)
		if _border_indicator:
			_border_indicator.update(player.position)
		if _threat_meter:
			_threat_meter.update(player.position)


func _exit_tree() -> void:
	if _mode7:
		_mode7.cleanup()


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
		# Row 1: Picket fences around houses (gap at cols 37-38 for MapleHeights path)
		"lfffffffffflffffffffffffffflfffffffffllfffffflllll",
		# Row 2: House row 1 - 4 houses
		"lfhwhdhwhfllfhwhdhwhflllfhwhdhwhflfhwllhwhflllllll",
		# Row 3: House walls continued (gap at cols 37-38 for MapleHeights path)
		"lfhhhhhhhfllfhhhhhhhflllfhhhhhhhflfhhllhhhflllllll",
		# Row 4: Fence bottoms, mailboxes (gap at cols 37-38 for MapleHeights path)
		"lffmffffffllfffffffmflllfffffffmflfffllfmfllllllll",
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
	spawn_points["entrance"] = Vector2(25 * TILE_SIZE + TILE_SIZE / 2, 11 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["suburban_portal"] = spawn_points["entrance"]
	# Spawn point for returning from industrial world (east side of map)
	spawn_points["from_industrial"] = Vector2(46 * TILE_SIZE + TILE_SIZE / 2, 20 * TILE_SIZE + TILE_SIZE / 2)
	# Spawn point for Maple Heights village — in open lawn east of house rows (was inside house wall)
	spawn_points["maple_heights_entrance"] = Vector2(43 * TILE_SIZE + TILE_SIZE / 2, 10 * TILE_SIZE + TILE_SIZE / 2)


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

	# Forward portal to W3 Steampunk (gated on world unlock)
	if GameState.is_world_unlocked(3) or GameState.get_story_flag("w2_boss_defeated"):
		var forward_portal = AreaTransitionScript.new()
		forward_portal.name = "WorldPortal"
		forward_portal.target_map = "steampunk_overworld"
		forward_portal.target_spawn = "steampunk_portal"
		forward_portal.require_interaction = true
		forward_portal.indicator_text = "Enter the Clockwork Dominion"
		forward_portal.position = Vector2(47 * TILE_SIZE + TILE_SIZE / 2, 20 * TILE_SIZE + TILE_SIZE / 2)
		_setup_transition_collision(forward_portal, Vector2(TILE_SIZE, TILE_SIZE))
		forward_portal.transition_triggered.connect(_on_transition_triggered)
		transitions.add_child(forward_portal)

	# Maple Heights village entrance (northeast residential corner, row 3)
	var maple_heights_trans = AreaTransitionScript.new()
	maple_heights_trans.name = "MapleHeightsEntrance"
	maple_heights_trans.target_map = "maple_heights_village"
	maple_heights_trans.target_spawn = "entrance"
	maple_heights_trans.require_interaction = true
	maple_heights_trans.indicator_text = "Enter Maple Heights"
	maple_heights_trans.position = spawn_points.get("maple_heights_entrance", Vector2(1232, 112))
	_setup_transition_collision(maple_heights_trans, Vector2(TILE_SIZE * 3, TILE_SIZE * 3))
	maple_heights_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(maple_heights_trans)


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
	var brad = _create_npc("Brad the Skateboarder", "villager", Vector2(8 * TILE_SIZE, 28 * TILE_SIZE), [
		"Dude... have you checked behind the school?",
		"There's supposed to be some hidden debug menu or something.",
		"My friend's cousin's roommate unlocked like... secret jobs.",
		"Radical."
	])
	npcs.add_child(brad)

	# === Karen - strip mall ===
	var karen = _create_npc("Karen", "villager", Vector2(8 * TILE_SIZE, 15 * TILE_SIZE), [
		"I want to speak to whoever designed this town.",
		"The encounter rate is UNACCEPTABLE.",
		"I've been complaining to NPCs for HOURS.",
		"Where. Is. Your. Manager."
	])
	npcs.add_child(karen)

	# === Mall Rat Mike - near arcade store ===
	var mike = _create_npc("Mall Rat Mike", "villager", Vector2(12 * TILE_SIZE, 15 * TILE_SIZE), [
		"Yo, you know about autobattle? Press F5, dude.",
		"I set up my scripts to farm crows all day.",
		"The XP isn't great but the drops are SICK.",
		"Pro tip: condition 'Enemy HP < 25%' \u2192 Steal. Trust me."
	])
	npcs.add_child(mike)

	# === Coach Thompson - basketball court ===
	var coach = _create_npc("Coach Thompson", "guard", Vector2(10 * TILE_SIZE, 24 * TILE_SIZE), [
		"Listen up! Combat is like basketball.",
		"Sometimes you gotta DEFER - pass the ball, wait for an opening.",
		"Build up that AP, then ADVANCE with everything you got!",
		"Full-court press, baby! That's how you win!"
	])
	npcs.add_child(coach)

	# === Suspicious Dave - behind houses, east lawn ===
	var dave = _create_npc("Suspicious Dave", "villager", Vector2(40 * TILE_SIZE, 5 * TILE_SIZE), [
		"Psst... don't tell anyone I told you this...",
		"The monsters? They're stored in JSON files.",
		"abilities.json... passives.json... it's all RIGHT THERE.",
		"The devs didn't even ENCRYPT it. Wake up, people!"
	])
	npcs.add_child(dave)

	# === Pizza Delivery Pete - near pizza store ===
	var pete = _create_npc("Pizza Delivery Pete", "villager", Vector2(3 * TILE_SIZE, 20 * TILE_SIZE), [
		"30 minutes or it's free! That's my motto.",
		"My Speed stat is maxed out. Gotta go fast!",
		"You know what ruins a delivery? Random encounters.",
		"I swear those crows target me specifically."
	])
	npcs.add_child(pete)

	# === Principal Sinclair - near school store ===
	var principal = _create_npc("Principal Sinclair", "elder", Vector2(38 * TILE_SIZE, 20 * TILE_SIZE), [
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
	var leader = GameState.get_party_leader()
	var job_id = leader.get("job_id", "fighter") if leader else "fighter"
	player.set_job(job_id)
	add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"

	# Camera follows player
	player.add_child(camera)
	camera.make_current()

	Mode7Overlay.apply_camera(camera, mode7_enabled)
	Mode7Overlay.apply_camera_limits(camera, MAP_WIDTH, MAP_HEIGHT, TILE_SIZE)

	# Smooth camera follow
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0


func _setup_controller() -> void:
	controller = OverworldControllerScript.new()
	controller.name = "Controller"
	controller.player = player
	controller.encounter_enabled = true
	controller.current_area_id = "suburban_overworld"

	# W2 Suburban encounters — EarthBound-style, avg lv 4
	# Rate 0.045: slightly lower than W1 (fewer but trickier enemies)
	controller.set_area_config("suburban_overworld", false, 0.045,
		["spiteful_crow", "new_age_retro_hippie", "skate_punk", "unassuming_dog", "cranky_lady"])

	# Connect signals
	controller.battle_triggered.connect(_on_battle_triggered)
	controller.menu_requested.connect(_on_menu_requested)

	add_child(controller)


func _on_transition_triggered(target_map: String, spawn_point: String) -> void:
	if "overworld" in target_map and _mode7:
		InputLockManager.push_lock("world_transition")
		await _mode7.play_dissolve_out()
		InputLockManager.pop_lock("world_transition")
	area_transition.emit(target_map, spawn_point)


func _on_battle_triggered(enemies: Array) -> void:
	battle_triggered.emit(enemies, _get_terrain_for_zone())


func _get_terrain_for_zone() -> String:
	# W2 zones: residential / strip mall / park — all map to suburban terrain
	var player_pos: Vector2 = player.global_position if player else Vector2.ZERO
	var tile_x: int = int(player_pos.x / TILE_SIZE)
	# Park/playground zone (leftmost third) → forest (trees, grass feel)
	if tile_x < MAP_WIDTH / 3:
		return "suburban"
	return "suburban"


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
