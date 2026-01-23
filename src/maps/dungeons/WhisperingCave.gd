extends Node2D
class_name WhisperingCaveScene

## WhisperingCave - Multi-floor dungeon with Cave Rat King boss on Floor 6
## Progressive difficulty with floor-specific enemy pools

const TileGeneratorScript = preload("res://src/exploration/TileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)
signal floor_changed(new_floor: int)

## Map dimensions (in tiles)
const MAP_WIDTH: int = 25
const MAP_HEIGHT: int = 20
const TILE_SIZE: int = 32

## Floor state
var current_floor: int = 1
var boss_defeated: bool = false
var _transitioning: bool = false  # Prevent rapid re-triggering

## Scene components
var tile_map: TileMapLayer
var player: Node2D  # OverworldPlayer
var camera: Camera2D
var controller: Node  # OverworldController
var tile_generator: Node  # TileGenerator

## Area transitions
var transitions: Node2D

## Stair sprites
var stair_sprites: Node2D

## Spawn points
var spawn_points: Dictionary = {}

## Floor layouts (U = stairs up, D = stairs down, B = boss)
var floor_layouts: Dictionary = {
	1: [  # Tutorial floor - entrance
		"MMMMMMMMMMMMMMMMMMMMMMMMM",
		"M.......................M",
		"M..MMMM......MMMM.......M",
		"M..M..........M.........M",
		"M..M....T.....M.........M",
		"M..MMMMMMMMMMMM.........M",
		"M.......................M",
		"M......MMM...MMM........M",
		"M......M.......M........M",
		"M......M...U...M........M",
		"M......M.......M........M",
		"M......MMM...MMM........M",
		"M.......................M",
		"M.......................M",
		"M.......................M",
		"M.......................M",
		"M.......................M",
		"M........DDDD...........M",
		"M........DDDD...........M",
		"MMMMMMMMMMMMMMMMMMMMMMMMM"
	],
	2: [  # Some corridors
		"MMMMMMMMMMMMMMMMMMMMMMMMM",
		"M.......................M",
		"M.MMMMMMMM.....MMMMMMMM.M",
		"M.M......M.....M.......M.M",
		"M.M..T...D.....M...T...M.M",
		"M.M......M.....M.......M.M",
		"M.MMMMMMMM.....MMMMMMMM.M",
		"M.......................M",
		"M.......................M",
		"M........MM.MM..........M",
		"M.........M.M...........M",
		"M.........M.U...........M",
		"M.........M.M...........M",
		"M........MM.MM..........M",
		"M.......................M",
		"M.......................M",
		"M.......................M",
		"M.......................M",
		"M.......................M",
		"MMMMMMMMMMMMMMMMMMMMMMMMM"
	],
	3: [  # Branching paths
		"MMMMMMMMMMMMMMMMMMMMMMMMM",
		"M.......................M",
		"M.MMM.....MMM.....MMM...M",
		"M.M.M.....M.M.....M.M...M",
		"M.M.M..T..M.M..T..M.M...M",
		"M.M.MMMMMMM.MMMMMMM.M...M",
		"M.M.................M...M",
		"M.M.................M...M",
		"M.MMMMMMMMM.MMMMMMMMM...M",
		"M...........D...........M",
		"M.......................M",
		"M.....MMM..U..MMM.......M",
		"M.....M.........M.......M",
		"M.....M.........M.......M",
		"M.....MMM.....MMM.......M",
		"M.......................M",
		"M.......................M",
		"M.......................M",
		"M.......................M",
		"MMMMMMMMMMMMMMMMMMMMMMMMM"
	],
	4: [  # Maze-like with optional areas
		"MMMMMMMMMMMMMMMMMMMMMMMMM",
		"M.......................M",
		"M.MMMMM.MMMMM.MMMMM.MMM.M",
		"M.M...M.M...M.M...M...M.M",
		"M.M.M.M.M.M.M.M.M.MMM.M.M",
		"M.M.M.M.M.M.M.M.M.....M.M",
		"M.M.M...M.M...M.MMMMMMM.M",
		"M.M.MMMMM.MMMMM.........M",
		"M.M.....................M",
		"M.MMMMMMMMM.........MMM.M",
		"M.....D...M.....U.......M",
		"M.MMMMMMMMM.........MMM.M",
		"M.........M.............M",
		"M.MMMMMM..M..MMMMMMMMMM.M",
		"M.M....M..M..M........M.M",
		"M.M.T..M.....M....T...M.M",
		"M.M....M.....M........M.M",
		"M.MMMMMM.....MMMMMMMMMM.M",
		"M.......................M",
		"MMMMMMMMMMMMMMMMMMMMMMMMM"
	],
	5: [  # Linear challenge gauntlet
		"MMMMMMMMMMMMMMMMMMMMMMMMM",
		"M.......................M",
		"M.MMMMMMMMMMMMMMMMMMMM..M",
		"M.M..................M..M",
		"M.M.MMMMMMMMMMMMMM...M..M",
		"M.M.M..............M.M..M",
		"M.M.M.MMMMMMMMMMMM.M.M..M",
		"M.M.M.M..........M.M.M..M",
		"M.M.M.M.MMMMMMM..M.M.M..M",
		"M.M.M.M.M.....M....M.M..M",
		"M.M.M.D.M..T..M..U.M.M..M",
		"M.M.M.M.M.....M....M.M..M",
		"M.M.M.M.MMMMMMM..M.M.M..M",
		"M.M.M.M..........M.M.M..M",
		"M.M.M.MMMMMMMMMMMM.M.M..M",
		"M.M.M..............M.M..M",
		"M.M.MMMMMMMMMMMMMMMM.M..M",
		"M.M..................M..M",
		"M.MMMMMMMMMMMMMMMMMMMM..M",
		"MMMMMMMMMMMMMMMMMMMMMMMMM"
	],
	6: [  # Boss arena
		"MMMMMMMMMMMMMMMMMMMMMMMMM",
		"M.......................M",
		"M.......................M",
		"M.......................M",
		"M.....MMMMMMMMMMM.......M",
		"M.....M.........M.......M",
		"M.....M.........M.......M",
		"M.....M....B....M.......M",
		"M.....M.........M.......M",
		"M.....M.........M.......M",
		"M.....MMMMMMMMMMM.......M",
		"M.......................M",
		"M.......................M",
		"M.......................M",
		"M.......................M",
		"M.......................M",
		"M..........D............M",
		"M.......................M",
		"M.......................M",
		"MMMMMMMMMMMMMMMMMMMMMMMMM"
	]
}

## Floor spawn points for stairs
var floor_spawn_points: Dictionary = {
	1: {"entrance": Vector2(12, 14)},
	2: {"down_stairs": Vector2(12, 4)},
	3: {"down_stairs": Vector2(11, 9)},
	4: {"down_stairs": Vector2(6, 10)},
	5: {"down_stairs": Vector2(8, 10)},
	6: {"down_stairs": Vector2(11, 16)}
}


func _ready() -> void:
	_setup_scene()
	_generate_map_for_floor(current_floor)
	_setup_player()
	_setup_camera()
	_setup_controller()

	# Load boss defeated state from GameState
	_load_boss_state()

	# Start cave music
	if SoundManager:
		SoundManager.play_area_music("cave")

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

	# Create stair sprites container
	stair_sprites = Node2D.new()
	stair_sprites.name = "StairSprites"
	add_child(stair_sprites)


func _generate_map_for_floor(floor_num: int) -> void:
	"""Generate map for specific floor"""
	spawn_points.clear()

	var map_data = floor_layouts.get(floor_num, floor_layouts[1])

	# Convert map_data to tiles
	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "M"
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			# Mark special locations
			if char == "U":  # Stairs up
				spawn_points["stairs_up"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)
			elif char == "D":  # Stairs down / exit
				spawn_points["stairs_down"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)
			elif char == "T":  # Treasure
				var key = "treasure_%d" % spawn_points.size()
				spawn_points[key] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)
			elif char == "B":  # Boss
				spawn_points["boss"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)

	# Set default spawn for this floor
	var spawn_pos = floor_spawn_points.get(floor_num, {}).get("entrance", Vector2(12, 14))
	spawn_points["default"] = Vector2(spawn_pos.x * TILE_SIZE, spawn_pos.y * TILE_SIZE)

	# Setup transitions for this floor
	_setup_transitions_for_floor(floor_num)

	# Add visual markers for stairs
	_add_stair_visuals()


func _char_to_tile_type(char: String) -> int:
	match char:
		"M": return TileGeneratorScript.TileType.MOUNTAIN
		".": return TileGeneratorScript.TileType.FLOOR
		"T": return TileGeneratorScript.TileType.FLOOR  # Treasure (floor)
		"B": return TileGeneratorScript.TileType.FLOOR  # Boss (floor)
		"U": return TileGeneratorScript.TileType.FLOOR  # Stairs up (floor)
		"D": return TileGeneratorScript.TileType.FLOOR  # Stairs down (floor)
		"X": return TileGeneratorScript.TileType.FLOOR  # Exit (floor)
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 4, tile_id / 4)


func _setup_transitions_for_floor(floor_num: int) -> void:
	"""Setup area transitions for current floor"""
	# Clear existing transitions
	for child in transitions.get_children():
		child.queue_free()

	# Stairs up (to next floor)
	if spawn_points.has("stairs_up"):
		var up_trans = AreaTransitionScript.new()
		up_trans.name = "StairsUp"
		up_trans.require_interaction = false
		up_trans.position = spawn_points["stairs_up"]
		_setup_transition_collision(up_trans, Vector2(TILE_SIZE, TILE_SIZE))
		up_trans.body_entered.connect(_on_stairs_up_entered)
		transitions.add_child(up_trans)

	# Stairs down / exit
	if spawn_points.has("stairs_down"):
		var down_trans = AreaTransitionScript.new()
		down_trans.name = "StairsDown"
		down_trans.require_interaction = false
		down_trans.position = spawn_points["stairs_down"]
		_setup_transition_collision(down_trans, Vector2(TILE_SIZE * 2, TILE_SIZE * 2))

		if floor_num == 1:
			# Floor 1 exit goes to overworld
			down_trans.target_map = "overworld"
			down_trans.target_spawn = "cave_entrance"
			down_trans.transition_triggered.connect(_on_transition_triggered)
		else:
			# Other floors go down one floor
			down_trans.body_entered.connect(_on_stairs_down_entered)

		transitions.add_child(down_trans)

	# Boss trigger on floor 6
	if floor_num == 6 and spawn_points.has("boss") and not boss_defeated:
		var boss_trans = AreaTransitionScript.new()
		boss_trans.name = "BossTrigger"
		boss_trans.require_interaction = true
		boss_trans.position = spawn_points["boss"]
		_setup_transition_collision(boss_trans, Vector2(TILE_SIZE, TILE_SIZE))
		boss_trans.body_entered.connect(_on_boss_trigger_entered)
		transitions.add_child(boss_trans)


func _add_stair_visuals() -> void:
	"""Add visual markers for stairs"""
	# Clear existing stair sprites
	for child in stair_sprites.get_children():
		child.queue_free()

	# Stairs up marker
	if spawn_points.has("stairs_up"):
		var up_marker = _create_stair_marker(spawn_points["stairs_up"], true)
		stair_sprites.add_child(up_marker)

	# Stairs down marker
	if spawn_points.has("stairs_down"):
		var down_marker = _create_stair_marker(spawn_points["stairs_down"], false)
		stair_sprites.add_child(down_marker)


func _create_stair_marker(position: Vector2, is_up: bool) -> Node2D:
	"""Create a visual marker for stairs"""
	var marker = Node2D.new()
	marker.position = position

	# Background tile with different color
	var bg = ColorRect.new()
	bg.size = Vector2(TILE_SIZE, TILE_SIZE)
	bg.position = Vector2(-TILE_SIZE/2, -TILE_SIZE/2)
	bg.color = Color(0.3, 0.4, 0.5, 0.7) if is_up else Color(0.5, 0.4, 0.3, 0.7)
	marker.add_child(bg)

	# Arrow indicator
	var label = Label.new()
	label.text = "▲" if is_up else "▼"
	label.position = Vector2(-8, -12)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color.WHITE)
	marker.add_child(label)

	# Pulsing animation
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(label, "modulate:a", 0.5, 0.8)
	tween.tween_property(label, "modulate:a", 1.0, 0.8)

	return marker


func _setup_transition_collision(trans: Area2D, size: Vector2) -> void:
	# Set collision layers for interaction
	trans.collision_layer = 4  # Interactable layer
	trans.collision_mask = 2   # Detect player
	trans.monitoring = true
	trans.monitorable = true

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	trans.add_child(collision)


func _on_stairs_up_entered(body: Node2D) -> void:
	"""Player entered stairs up - transition to next floor"""
	if body.has_method("set_can_move") and not _transitioning:
		_transition_to_floor(current_floor + 1, "up")


func _on_stairs_down_entered(body: Node2D) -> void:
	"""Player entered stairs down - transition to previous floor"""
	if body.has_method("set_can_move") and not _transitioning:
		_transition_to_floor(current_floor - 1, "down")


func _transition_to_floor(target_floor: int, direction: String = "") -> void:
	"""Transition to a different floor"""
	if target_floor < 1 or target_floor > 6:
		return

	# Set transition lock
	_transitioning = true

	# Disable player movement immediately
	if player and player.has_method("set_can_move"):
		player.set_can_move(false)

	# Fade out
	controller.pause_exploration()

	# Update floor
	current_floor = target_floor

	# Clear and regenerate map
	tile_map.clear()
	_generate_map_for_floor(current_floor)

	# Update encounter settings
	_update_floor_encounters(current_floor)

	# Spawn player at appropriate stairs based on direction
	var spawn_key = "default"
	if direction == "up":
		# Going up: spawn at stairs_down of new floor (away from up stairs)
		spawn_key = "stairs_down"
	elif direction == "down":
		# Going down: spawn at stairs_up of new floor (away from down stairs)
		# For floor 1, there are no up stairs, so use default/entrance
		if target_floor == 1:
			spawn_key = "entrance"
		else:
			spawn_key = "stairs_up"

	if spawn_points.has(spawn_key):
		player.teleport(spawn_points[spawn_key])
	else:
		# Fallback to default
		player.teleport(spawn_points.get("default", Vector2(400, 400)))

	player.reset_step_count()

	# Re-enable player movement after a short delay
	await get_tree().create_timer(0.3).timeout
	if player and player.has_method("set_can_move"):
		player.set_can_move(true)

	# Fade in
	controller.resume_exploration()
	floor_changed.emit(current_floor)

	print("Transitioned to Whispering Cave Floor %d" % current_floor)

	# Release transition lock after additional delay (prevent immediate re-trigger)
	await get_tree().create_timer(0.5).timeout
	_transitioning = false


func _update_floor_encounters(floor: int) -> void:
	"""Update encounter rate and enemy pool for floor"""
	var base_rate = 0.05
	var encounter_rate = base_rate + (floor - 1) * 0.01  # 0.05 -> 0.10
	var enemy_pool_id = "cave_floor_%d" % floor

	controller.set_area_config("whispering_cave_f%d" % floor, false, encounter_rate, [])
	controller.set_enemy_pool(enemy_pool_id)
	controller.current_area_id = "whispering_cave_f%d" % floor

	print("Floor %d encounters: rate=%.2f, pool=%s" % [floor, encounter_rate, enemy_pool_id])


func _on_boss_trigger_entered(body: Node2D) -> void:
	"""Player triggered boss fight"""
	if body.has_method("set_can_move") and not boss_defeated:
		_trigger_boss_battle()


func _trigger_boss_battle() -> void:
	"""Start the Cave Rat King boss battle"""
	controller.pause_exploration()

	# Show boss dialogue
	_show_boss_intro()

	# Trigger battle with Cave Rat King
	await get_tree().create_timer(2.0).timeout
	battle_triggered.emit(["cave_rat_king"])


func _show_boss_intro() -> void:
	"""Display boss intro dialogue"""
	print("=== BOSS ENCOUNTER ===")
	print("The party climbs the final stairs, expecting a dragon...")
	print("...it's just a really big rat.")
	print("Hero: 'Are you serious?'")
	print("Cave Rat King SQUEAKS defiantly!")
	print("======================")


func _on_boss_defeated() -> void:
	"""Handle boss defeat"""
	boss_defeated = true
	_save_boss_state()

	# Spawn exit stairs
	print("Cave Rat King defeated! Exit stairs appear.")
	_setup_transitions_for_floor(current_floor)


func _load_boss_state() -> void:
	"""Load boss defeated state from GameState"""
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.player_party.size() > 0:
		var flags = game_state.player_party[0].get("dungeon_flags", {})
		boss_defeated = flags.get("cave_rat_king_defeated", false)


func _save_boss_state() -> void:
	"""Save boss defeated state to GameState"""
	var game_state = get_node_or_null("/root/GameState")
	if game_state and game_state.player_party.size() > 0:
		if not game_state.player_party[0].has("dungeon_flags"):
			game_state.player_party[0]["dungeon_flags"] = {}
		game_state.player_party[0]["dungeon_flags"]["cave_rat_king_defeated"] = true


func _setup_player() -> void:
	player = OverworldPlayerScript.new()
	player.name = "Player"
	player.position = spawn_points.get("default", Vector2(400, 544))
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
	controller.encounter_enabled = true
	controller.current_area_id = "whispering_cave_f1"

	# Configure initial floor (floor 1)
	_update_floor_encounters(current_floor)

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
