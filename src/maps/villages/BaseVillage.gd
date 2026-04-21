extends Node2D
class_name BaseVillage

## Shared base class for all village exploration scenes.
##
## Eliminates ~150 lines of duplicated boilerplate across ~11 VillageScene
## scripts (scene setup, camera/controller wiring, save point, public API).
##
## Subclasses MUST override:
##   _get_area_id()              — "harmonia_village", etc (also used for config key)
##   _get_village_display_name() — human name used in save-log message
##   _get_map_pixel_size()       — Vector2i(MAP_WIDTH, MAP_HEIGHT) * TILE_SIZE for camera limits
##   _generate_map()             — populate tile_map, set spawn_points["default"]/["exit"]
##   _setup_transitions()        — create AreaTransition portals
##   _setup_buildings()          — inn/shop/bar/etc
##   _setup_treasures()          — chests
##   _setup_npcs()               — Area2D NPCs with dialogue
##
## Subclasses MAY override:
##   _get_save_point_position()  — defaults to (10,8) * TILE_SIZE
##   _get_player_spawn_fallback() — position used if spawn_points["default"] missing
##
## The base class owns:
##   exploration_ready / battle_triggered / area_transition signals
##   scene components (tile_map, player, camera, controller, tile_generator, spawn_points)
##   containers (transitions, npcs, buildings, treasures)
##   public API: spawn_player_at / resume / pause / set_player_job / set_player_appearance
##   helpers: _setup_transition_collision / _create_npc

const TileGeneratorScript = preload("res://src/exploration/TileGenerator.gd")
const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const OverworldControllerScript = preload("res://src/exploration/OverworldController.gd")
const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")
const OverworldNPCScript = preload("res://src/exploration/OverworldNPC.gd")

signal exploration_ready()
signal battle_triggered(enemies: Array)
signal area_transition(target_map: String, spawn_point: String)

## Tile size (consistent across all villages)
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

## Spawn points (populated by subclass _generate_map)
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
	_setup_save_point()

	if SoundManager:
		SoundManager.play_area_music("village")

	exploration_ready.emit()


## ---- Virtual hooks — subclasses override ----

func _get_area_id() -> String:
	return "village"


func _get_village_display_name() -> String:
	return "Village"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(24 * TILE_SIZE, 18 * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(10 * TILE_SIZE, 8 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(400, 400)


func _generate_map() -> void:
	push_warning("BaseVillage._generate_map() not overridden by subclass")


func _setup_transitions() -> void:
	pass


func _setup_buildings() -> void:
	pass


func _setup_treasures() -> void:
	pass


func _setup_npcs() -> void:
	pass


## ---- Shared scene/node setup ----

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
	player.position = spawn_points.get("default", _get_player_spawn_fallback())
	player.set_job("fighter")
	add_child(player)


func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	camera.make_current()

	camera.zoom = Vector2(2.0, 2.0)

	var map_pixel_size = _get_map_pixel_size()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = map_pixel_size.x
	camera.limit_bottom = map_pixel_size.y

	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0


func _setup_controller() -> void:
	controller = OverworldControllerScript.new()
	controller.name = "Controller"
	controller.player = player
	controller.encounter_enabled = false  # villages are safe zones by default
	controller.current_area_id = _get_area_id()

	controller.set_area_config(_get_area_id(), true, 0.0, [])

	controller.battle_triggered.connect(_on_battle_triggered)
	controller.menu_requested.connect(_on_menu_requested)

	add_child(controller)


func _setup_save_point() -> void:
	var save_pt = SavePoint.new()
	save_pt.position = _get_save_point_position()
	save_pt.save_requested.connect(_on_save_requested)
	add_child(save_pt)


func _on_save_requested() -> void:
	if SaveSystem and SaveSystem.has_method("quick_save"):
		SaveSystem.quick_save()
		print("[SAVE] Quick save triggered from %s save point" % _get_village_display_name())


func _on_transition_triggered(target_map: String, spawn_point: String) -> void:
	area_transition.emit(target_map, spawn_point)


func _on_battle_triggered(enemies: Array) -> void:
	battle_triggered.emit(enemies)


func _on_menu_requested() -> void:
	pass


## ---- Public API (consumed by GameLoop/MapSystem) ----

## Spawn player at a named spawn point (does nothing if unknown)
func spawn_player_at(spawn_name: String) -> void:
	if spawn_points.has(spawn_name) and player:
		player.teleport(spawn_points[spawn_name])
		if player.has_method("reset_step_count"):
			player.reset_step_count()


## Resume exploration input
func resume() -> void:
	if controller and controller.has_method("resume_exploration"):
		controller.resume_exploration()


## Pause exploration input
func pause() -> void:
	if controller and controller.has_method("pause_exploration"):
		controller.pause_exploration()


## Set the player's job id
func set_player_job(job_name: String) -> void:
	if player:
		player.set_job(job_name)


## Set the player's appearance from the party leader combatant
func set_player_appearance(leader) -> void:
	if player and player.has_method("set_appearance_from_leader"):
		player.set_appearance_from_leader(leader)
