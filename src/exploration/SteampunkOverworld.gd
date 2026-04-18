extends Node2D
class_name SteampunkOverworld

## SteampunkOverworld - Steampunk/EarthBound 90s suburban-industrial overworld
## Features central plaza, residential blocks, industrial district, rail station, and park

const SteampunkTileGeneratorScript = preload("res://src/exploration/SteampunkTileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")
const OverworldNPCScript = preload("res://src/exploration/OverworldNPC.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array, terrain: String)
signal area_transition(target_map: String, spawn_point: String)

## Map dimensions (in tiles) - larger urban area
const MAP_WIDTH: int = 60
const MAP_HEIGHT: int = 50
const TILE_SIZE: int = 32

## Scene components
var tile_map: TileMapLayer
var player: Node2D  # OverworldPlayer
var camera: Camera2D
var controller: Node  # OverworldController
var tile_generator: Node  # SteampunkTileGenerator

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

## Steam vent effect state
var _steam_emitters: Array = []
var _steam_timers: Array = []
var _steam_intervals: Array = []


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
		_mode7.apply_preset("steampunk")
		_mode7.setup(self, player)

	# Zone name popup
	var _zone_popup = ZoneNamePopup.new()
	add_child(_zone_popup)
	_zone_popup.setup(self)
	_zone_popup.show_zone("steampunk_overworld")

	_zone_particles = ZoneParticles.new()
	add_child(_zone_particles)
	_zone_particles.setup(self, player)
	_zone_particles.update_zone("steampunk_overworld")

	GameState.set_story_flag("w3_entered")
	_quest_tracker = QuestTracker.new()
	add_child(_quest_tracker)
	_quest_tracker.setup(self)

	_weather = WeatherSystem.new()
	add_child(_weather)
	_weather.setup(self, player, "steampunk")

	_place_signposts()
	_place_landmarks()
	_place_wanderers()
	_place_village_markers()
	_place_treasure_chests()
	_place_save_point()

	# Start steampunk overworld music
	if SoundManager:
		SoundManager.play_area_music("overworld_steampunk")

	_setup_effects()
	_minimap = OverworldMinimap.new()
	add_child(_minimap)
	_minimap.setup(self, player, MAP_WIDTH, MAP_HEIGHT, TILE_SIZE, spawn_points)
	_minimap.set_objective(_get_objective_position())

	monster_spawner = MonsterSpawner.new()
	monster_spawner.name = "MonsterSpawner"
	add_child(monster_spawner)
	monster_spawner.setup(player, ["steam_rat", "cog_swarm", "clockwork_sentinel", "pipe_phantom", "brass_golem"])

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
	## W3: reach rail station (Forward Portal) after visiting Brasston
	if GameState.get_story_flag("w3_boss_defeated"):
		return spawn_points.get("station", Vector2.ZERO)
	if GameState.get_story_flag("visited_brasston"):
		return spawn_points.get("station", Vector2.ZERO)
	return spawn_points.get("brasston_entrance", Vector2.ZERO)


func _place_village_markers() -> void:
	var pos = spawn_points.get("brasston_entrance", Vector2.ZERO)
	if pos != Vector2.ZERO:
		var marker = VillageMarker.new()
		marker.village_name = "BRASSTON"
		marker.roof_color = Color(0.55, 0.4, 0.2)  # Copper/brass rooftops
		marker.position = pos
		add_child(marker)


func _place_treasure_chests() -> void:
	const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")
	# 10 chests across plaza, industrial district, rail station, residential
	var chests = [
		# Central plaza — fountain / clock tower area
		{"id": "w3_plaza_ether", "pos": Vector2(18, 18), "type": "item", "item": "ether", "amount": 4},
		{"id": "w3_plaza_gold", "pos": Vector2(26, 19), "type": "gold", "gold": 400},
		# Industrial district (NE/SE) — machinery caches
		{"id": "w3_industrial_hipotion", "pos": Vector2(48, 10), "type": "item", "item": "hi_potion", "amount": 4},
		{"id": "w3_industrial_elixir", "pos": Vector2(52, 18), "type": "item", "item": "elixir", "amount": 1},
		{"id": "w3_industrial_gold", "pos": Vector2(45, 30), "type": "gold", "gold": 500},
		# Rail station approach — commuter lost-and-found
		{"id": "w3_station_remedy", "pos": Vector2(22, 40), "type": "item", "item": "remedy", "amount": 3},
		{"id": "w3_station_phoenix", "pos": Vector2(30, 40), "type": "item", "item": "phoenix_down", "amount": 2},
		# Residential blocks — tenement backyards
		{"id": "w3_tenement_antidote", "pos": Vector2(8, 22), "type": "item", "item": "antidote", "amount": 4},
		{"id": "w3_tenement_gold", "pos": Vector2(5, 10), "type": "gold", "gold": 250},
		# Park / steam pipes
		{"id": "w3_park_ether", "pos": Vector2(15, 33), "type": "item", "item": "ether", "amount": 3},
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
	# Save crystal at central plaza (safe hub area)
	_save_point = SavePoint.new()
	_save_point.position = Vector2(22 * TILE_SIZE + TILE_SIZE / 2, 20 * TILE_SIZE + TILE_SIZE / 2)
	add_child(_save_point)


func _place_signposts() -> void:
	var signs = [
		{"pos": Vector2(10, 26), "text": "← Brasston Village"},
		{"pos": Vector2(27, 3), "text": "↑ Return Portal"},
		{"pos": Vector2(27, 43), "text": "↓ Rail Station / Forward"},
		{"pos": Vector2(22, 17), "text": "→ Central Plaza"},
	]
	for s in signs:
		var post = Signpost.new()
		post.sign_text = s["text"]
		post.position = Vector2(s["pos"].x * TILE_SIZE + TILE_SIZE / 2, s["pos"].y * TILE_SIZE + TILE_SIZE / 2)
		add_child(post)


func _place_landmarks() -> void:
	var landmarks = [
		{"pos": Vector2(45, 8), "type": Landmark.Type.GEAR_PILE},
		{"pos": Vector2(15, 35), "type": Landmark.Type.STEAM_PIPE},
		{"pos": Vector2(30, 25), "type": Landmark.Type.GEAR_PILE},
		{"pos": Vector2(50, 20), "type": Landmark.Type.STEAM_PIPE},
	]
	for l in landmarks:
		var lm = Landmark.new()
		lm.landmark_type = l["type"]
		lm.position = Vector2(l["pos"].x * TILE_SIZE + TILE_SIZE / 2, l["pos"].y * TILE_SIZE + TILE_SIZE / 2)
		add_child(lm)


func _place_wanderers() -> void:
	var wanderers = [
		{
			"name": "Clockwinder",
			"dialogue": "If I stop winding, the whole district stops.",
			"color": Color(0.55, 0.4, 0.25),
			"path": [Vector2(25, 20), Vector2(30, 20), Vector2(30, 25), Vector2(25, 25)],
			"hints": [
				{"flag": "w3_entered", "text": "Brasston is west of here. The Grand Mechanism runs everything."},
				{"flag": "w3_boss_defeated", "text": "The mechanism broke. Something opened up... smells like soot and iron."},
			],
		},
		{
			"name": "Steam Collector",
			"dialogue": "Good steam is hard to find these days.",
			"color": Color(0.5, 0.5, 0.5),
			"path": [Vector2(40, 10), Vector2(45, 10), Vector2(45, 15), Vector2(40, 15)],
			"hints": [
				{"flag": "w3_entered", "text": "The pipes all lead to the Mechanism. Follow them if you're brave."},
				{"flag": "w3_boss_defeated", "text": "Beyond the Dominion lies a world of pure industry. No craftsmanship. Just output."},
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
	var vent_positions: Array[Vector2] = [
		Vector2(47 * TILE_SIZE + TILE_SIZE / 2, 9 * TILE_SIZE),
		Vector2(50 * TILE_SIZE + TILE_SIZE / 2, 11 * TILE_SIZE),
		Vector2(48 * TILE_SIZE + TILE_SIZE / 2, 12 * TILE_SIZE),
		Vector2(19 * TILE_SIZE + TILE_SIZE / 2, 19 * TILE_SIZE),
		Vector2(27 * TILE_SIZE + TILE_SIZE / 2, 43 * TILE_SIZE),
		Vector2(22 * TILE_SIZE + TILE_SIZE / 2, 43 * TILE_SIZE),
	]
	for i in range(vent_positions.size()):
		var emitter = CPUParticles2D.new()
		emitter.name = "SteamVent_%d" % i
		emitter.z_index = 6
		emitter.emitting = false
		emitter.amount = 10
		emitter.lifetime = 1.0
		emitter.one_shot = true
		emitter.explosiveness = 0.7
		emitter.randomness = 0.4
		emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		emitter.emission_sphere_radius = 3.0
		emitter.gravity = Vector2(0.0, 0.0)
		emitter.initial_velocity_min = 20.0
		emitter.initial_velocity_max = 45.0
		emitter.direction = Vector2(0.0, -1.0)
		emitter.spread = 25.0
		emitter.scale_amount_min = 1.5
		emitter.scale_amount_max = 3.5
		emitter.color = Color(0.92, 0.92, 0.95, 0.70)
		var grad = Gradient.new()
		grad.add_point(0.0, Color(0.95, 0.95, 1.0, 0.75))
		grad.add_point(1.0, Color(0.85, 0.85, 0.90, 0.0))
		emitter.color_ramp = grad
		emitter.position = vent_positions[i]
		add_child(emitter)
		_steam_emitters.append(emitter)
		_steam_timers.append(randf_range(0.0, 8.0))
		_steam_intervals.append(randf_range(5.0, 12.0))


func _process(delta: float) -> void:
	if _quest_tracker: _quest_tracker.update()
	if _mode7:
		_mode7.process_frame()
	if _weather:
		_weather.process(delta)
	for i in range(_steam_emitters.size()):
		_steam_timers[i] += delta
		if _steam_timers[i] >= _steam_intervals[i]:
			_steam_timers[i] = 0.0
			_steam_intervals[i] = randf_range(5.0, 12.0)
			_steam_emitters[i].restart()
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
	tile_generator = SteampunkTileGeneratorScript.new()
	add_child(tile_generator)

	# Background behind tilemap (dark industrial void)
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.10, 0.10, 0.12)  # Dark industrial gray
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
	# Steampunk city layout (60x50):
	# Top: Portal back to medieval overworld
	# Center: Plaza with fountain
	# East: Industrial district (factories, pipes, metal)
	# West: Residential blocks (buildings, doors, fences)
	# South: Rail station
	# Southwest: Park area
	#
	# Legend:
	# c = concrete, a = asphalt, b = brick_wall, m = metal_floor
	# p = pipe, g = park_grass, w = building_wall, d = door
	# i = window, r = rail_track, n = neon_sign, F = water_feature (fountain)
	# f = fence, y = alley, l = lamppost, h = manhole

	print("Generating steampunk overworld map %dx%d..." % [MAP_WIDTH, MAP_HEIGHT])

	var map_data: Array[String] = [
		"bbbbbbbbbbbbccccccccccccccchccccccccccccccccbbbbbbbbbbbbbbbb",
		"bwwwwwwwwwbcccccccccccccccccccccccccccccccccbwwwwwwwwwwwwcbc",
		"bwdwiwdwiwbcclcccccclcccccccccclcccccccclcccbwiwdwiwdwiwwcbc",
		"bwwwwwwwwwbccaaaaaaaaaaaaaaaaaaaaaaaaaaaaaacbwwwwwwwwwwwwcbc",
		"bfffffffbbccaacccccccccccccccccccccccccccaaccbbfffffffbbbbcc",
		"bgggggggccccaaccclcccccccccccccccccclccaaaccccccgggggggccccc",
		"bgggggggccccaaccccccccccccclcccccccccaaacccccccgggggggcccccc",
		"bgggggggccccaacccccccccccccccccccccccaacccccccccmmmmmmmmmmcc",
		"bfffffffccccaacccclcccccccccccccclcccaacccccccccmppppppppcmc",
		"cccccccccccaaaccccccccccccccccccccccaaaccccccccccmpppppppcmc",
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaammmmmmmmcm",
		"cccccccccccaaaccccccccccccccccccccccaaacccccccccccmpppppmcmc",
		"cclcccccclcaaccccccccccccccccccccccccaacccccccccccmpppmpmcmc",
		"cccccccccccaaccccccccccccccccccccccccaaccccccccccccmmmmmmcmc",
		"cccccccccccaaccclcccccccccccclcccccccaaccccccccccccccccccmcc",
		"cccccccccccaaccccccccccccccccccccccccaacccccccccccccnnnncmcc",
		"cclcccccclcaaccccccccccccccccccccccccaaccccccccccccnnnnnnccc",
		"cccccccccccaacccccccccccFccccccccccccaaccccccccccccnnnnccccc",
		"cccccccccccaaccccccccccFFFcccccccccccaaccccccccccccccccccccc",
		"cccccccccccaacccccccccccFccccccccccccaaccccccccchccccccccccc",
		"cccccccccccaacccccclccccccccccclccccaaaccccccccccccclccccccc",
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"cccccccccccaaccccccccccccccccccccccccaaccccccccccccccccccccc",
		"ccbwwwwwbccaaccccccccccccccccccccccccaaccbwwwwwbcccccccccccc",
		"ccbwdwiwbccaaccclcccccccccccccclcccccaaccbwidwwbcccccccccccc",
		"ccbwwccccccaaccccccccccccccccccccccccaaccbwwwwwbcccccccccccc",
		"ccbffccccccaaccccccccccccccccccccccccaaccbfffffbcccccccccccc",
		"ccbgggggbccaaccccccccccccccccccccccccaaccbgggggbcccccccccccc",
		"ccbgggggbccaaccclcccccclcccclcccclcccaaccbgggggbcccccccccccc",
		"ccbfffffbccaaccccccccccccccccccccccccaaccbfffffbcccccccccccc",
		"ccccccccccaaacccccccccccccccccccccccaaaccccccccccccccccccccc",
		"cccccccccaaaccccccccccccccccccccccccaaaccccccccccccccccccccc",
		"ccccccccaaacccccccccclccccccclccccccaaacccccccclcccccccclccc",
		"ccggggggccaacccccccccccccccccccccccccaaccccccccccccccccccccc",
		"cgggggggccaacccccccccccccccccccccccccaaccccccccccccccccccccc",
		"cggggFgggcaacccccccccccccccccccccccccaaccccccccccccccccccccc",
		"cgggFFFggcaaccclcccccccccccccclcccccaaaccccccccccccccccccccc",
		"cggggFgggcaacccccccccccccccccccccccaaacccccccccccccccccccccc",
		"cgggggggccaacccccccccclcccclcccccccaaccccccccccccccccccccccc",
		"ccggggggccaacccccccccccccccccccccccaaclcccccccccccccccclcccc",
		"cfffffffccaaaccccccccccccccccccccccaaacccccccccccccccccccccc",
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
		"cccccccccccccccccclcccccccccclcccccccccccccccccclccccccccccc",
		"ccccccccccrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrcccccccccccccc",
		"ccccccccccrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrcccccccccccccc",
		"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
		"ccccccccccccccbwwdwwbccccccccccccbwwdwwbcccccccccccccccccccc",
		"ccccccccccccccbwwwwwbccccccccccccbwwwwwbcccccccccccccccccccc",
		"ccccccccccccccbbbbbbbbcccccccccccbbbbbbbbccccccccccccccccccc",
	]

	# Ensure map_data matches expected dimensions
	while map_data.size() < MAP_HEIGHT:
		map_data.append("cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")

	# Convert map_data to tiles
	var tile_counts = {}
	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "c"
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			# Count tiles for debug
			tile_counts[tile_type] = tile_counts.get(tile_type, 0) + 1

	print("Steampunk tile counts: ", tile_counts)

	# Define spawn points
	spawn_points["entrance"] = Vector2(27 * TILE_SIZE + TILE_SIZE / 2, 2 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["plaza"] = Vector2(22 * TILE_SIZE + TILE_SIZE / 2, 17 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["station"] = Vector2(25 * TILE_SIZE + TILE_SIZE / 2, 43 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["steampunk_portal"] = Vector2(27 * TILE_SIZE + TILE_SIZE / 2, 1 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["default"] = spawn_points["entrance"]
	# Spawn point for returning from Brasston village (west residential quarter, row 26)
	spawn_points["brasston_entrance"] = Vector2(11 * TILE_SIZE + TILE_SIZE / 2, 26 * TILE_SIZE + TILE_SIZE / 2)


func _char_to_tile_type(char: String) -> int:
	match char:
		"c": return SteampunkTileGeneratorScript.TileType.CONCRETE
		"a": return SteampunkTileGeneratorScript.TileType.ASPHALT
		"b": return SteampunkTileGeneratorScript.TileType.BRICK_WALL
		"m": return SteampunkTileGeneratorScript.TileType.METAL_FLOOR
		"p": return SteampunkTileGeneratorScript.TileType.PIPE
		"g": return SteampunkTileGeneratorScript.TileType.PARK_GRASS
		"w": return SteampunkTileGeneratorScript.TileType.BUILDING_WALL
		"d": return SteampunkTileGeneratorScript.TileType.DOOR
		"i": return SteampunkTileGeneratorScript.TileType.WINDOW
		"r": return SteampunkTileGeneratorScript.TileType.RAIL_TRACK
		"n": return SteampunkTileGeneratorScript.TileType.NEON_SIGN
		"F": return SteampunkTileGeneratorScript.TileType.WATER_FEATURE
		"f": return SteampunkTileGeneratorScript.TileType.FENCE
		"y": return SteampunkTileGeneratorScript.TileType.ALLEY
		"l": return SteampunkTileGeneratorScript.TileType.LAMPPOST
		"h": return SteampunkTileGeneratorScript.TileType.MANHOLE
		_: return SteampunkTileGeneratorScript.TileType.CONCRETE


func _get_atlas_coords(tile_type: int) -> Vector2i:
	# Map tile types to atlas coordinates (4-column layout)
	var tile_id = SteampunkTileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 4, tile_id / 4)


func _setup_transitions() -> void:
	# Back portal to W2 Suburban
	var back_portal = AreaTransitionScript.new()
	back_portal.name = "BackPortal"
	back_portal.target_map = "suburban_overworld"
	back_portal.target_spawn = "entrance"
	back_portal.require_interaction = true
	back_portal.indicator_text = "Return to the Mundane Sprawl"
	back_portal.position = spawn_points.get("steampunk_portal", Vector2(864, 48))
	_setup_transition_collision(back_portal, Vector2(TILE_SIZE, TILE_SIZE))
	back_portal.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(back_portal)

	# Forward portal to W4 Industrial (gated on world unlock)
	if GameState.is_world_unlocked(4) or GameState.get_story_flag("w3_boss_defeated"):
		var forward_portal = AreaTransitionScript.new()
		forward_portal.name = "WorldPortal"
		forward_portal.target_map = "industrial_overworld"
		forward_portal.target_spawn = "entrance"
		forward_portal.require_interaction = true
		forward_portal.indicator_text = "Enter the Assembly Line"
		forward_portal.position = spawn_points.get("station", Vector2(864, 1400))
		_setup_transition_collision(forward_portal, Vector2(TILE_SIZE, TILE_SIZE))
		forward_portal.transition_triggered.connect(_on_transition_triggered)
		transitions.add_child(forward_portal)

	# Brasston village entrance (west residential quarter, row 26)
	var brasston_trans = AreaTransitionScript.new()
	brasston_trans.name = "BrasstonEntrance"
	brasston_trans.target_map = "brasston_village"
	brasston_trans.target_spawn = "entrance"
	brasston_trans.require_interaction = true
	brasston_trans.indicator_text = "Enter Brasston"
	brasston_trans.position = spawn_points.get("brasston_entrance", Vector2(176, 848))
	_setup_transition_collision(brasston_trans, Vector2(TILE_SIZE * 3, TILE_SIZE * 3))
	brasston_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(brasston_trans)


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
	# === Brigadier Flux - off-grid house, west residential ===
	var flux = _create_npc("Brigadier Flux", "elder", Vector2(4 * TILE_SIZE, 26 * TILE_SIZE), [
		"I keep my lamps lit by hand. No gear drives them.",
		"Everyone says I'm paranoid, but I've SEEN the gears skip.",
		"One skipped beat and the whole Mechanism resets.",
		"Mark my words — the Regulator knows exactly what he's doing."
	])
	npcs.add_child(flux)

	# === Sprocket - mechanic, near industrial pipes ===
	var sprocket = _create_npc("Sprocket", "villager", Vector2(50 * TILE_SIZE, 9 * TILE_SIZE), [
		"Name's Sprocket. I fix things that shouldn't break.",
		"The pipes in the east district? They're not carrying steam.",
		"I've heard... ticking. Like a countdown.",
		"Something inside the Mechanism is waking up."
	])
	npcs.add_child(sprocket)

	# === Cogsworth - plaza clocktower keeper ===
	var cogsworth = _create_npc("Cogsworth", "guard", Vector2(22 * TILE_SIZE, 17 * TILE_SIZE), [
		"The fountain plaza runs like clockwork. Literally.",
		"Every gear, every pipe, every cobblestone — synchronized.",
		"I maintain the central clock. If it stops, Brasston stops.",
		"Don't touch the gears. I mean it."
	])
	npcs.add_child(cogsworth)

	# === Ember - park area, southern gardens ===
	var ember = _create_npc("Ember", "villager", Vector2(6 * TILE_SIZE, 35 * TILE_SIZE), [
		"I grow flowers in the park. The only organic thing in Brasston.",
		"The gears underground make the soil warm. Perfect for roses.",
		"Sometimes the flowers bloom in perfect spirals. Fibonacci.",
		"The Mechanism is beautiful if you know where to look."
	])
	npcs.add_child(ember)

	# === Rail Master Piston - southern rail station ===
	var piston = _create_npc("Rail Master Piston", "guard", Vector2(28 * TILE_SIZE, 44 * TILE_SIZE), [
		"All aboard! The 3:47 to... well, nowhere, actually.",
		"The tracks go in a circle. Always have.",
		"Passengers get on, ride for an hour, get off where they started.",
		"Nobody complains. Efficiency doesn't require destinations."
	])
	npcs.add_child(piston)

	# === Whistler - mysterious figure near manholes ===
	var whistler = _create_npc("Whistler", "villager", Vector2(28 * TILE_SIZE, 19 * TILE_SIZE), [
		"*whistles tunelessly*",
		"You want to know what's under the manholes?",
		"Maintenance shafts. Gantries. Steam vents.",
		"And the Mechanism. The real one. Not the building — the idea.",
		"The Regulator built it to regulate... everything."
	])
	npcs.add_child(whistler)

	# === Tinkerer Wren - neon sign district, east ===
	var wren = _create_npc("Tinkerer Wren", "villager", Vector2(46 * TILE_SIZE, 16 * TILE_SIZE), [
		"I make the neon signs! Each one hand-bent brass tubing.",
		"The glow? That's pressurized aether, not electricity.",
		"My autobattle scripts? Oh, I wrote one that uses ONLY Defer.",
		"Just Defer. Forever. The monsters give up eventually."
	])
	npcs.add_child(wren)


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
	player.position = spawn_points.get("default", Vector2(864, 80))
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
	controller.current_area_id = "steampunk_overworld"

	# W3 Steampunk encounters — clockwork enemies, avg lv 5
	# Rate 0.04: fewer encounters, tougher per fight
	controller.set_area_config("steampunk_overworld", false, 0.04,
		["steam_rat", "cog_swarm", "clockwork_sentinel", "pipe_phantom", "brass_golem"])

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
	battle_triggered.emit(enemies, "steampunk")


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
