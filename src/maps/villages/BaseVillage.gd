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
const WanderingNPCScript = preload("res://src/exploration/WanderingNPC.gd")

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
		SoundManager.play_area_music(_get_music_area_id())

	# Tick 279: ratchet visited_<village> story_flag. Pre-fix the
	# *Overworld scripts read visited_maple_heights / visited_brasston /
	# visited_rivet_row / visited_node_prime to switch the objective
	# arrow from "go to <village>" → "head to the forward portal", but
	# NOTHING anywhere set these flags. Result: the arrow stayed pointed
	# at the village even after the player had already been there.
	# Derived flag name = area_id minus the "_village" suffix so the
	# existing reads (visited_brasston, etc.) just work.
	if GameState:
		var aid: String = _get_area_id()
		if aid.ends_with("_village"):
			GameState.set_story_flag("visited_" + aid.replace("_village", ""), true)

	exploration_ready.emit()


## ---- Virtual hooks — subclasses override ----

func _get_area_id() -> String:
	return "village"


## Tick 92: per-village music routing. Default returns "village"
## which SoundManager.play_area_music maps to Harmonia medieval
## music (correct for W1 villages without their own track). W2-W6
## village subclasses MUST override this to return their manifest
## key (maple_heights_village / brasston_village / rivet_row_village
## / node_prime_village / vertex_village) — otherwise stepping into
## Maple Heights plays Harmonia medieval music instead of the
## suburban village track that was specifically composed for it.
func _get_music_area_id() -> String:
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


## Shared interior-door builder. Subclasses (Harmonia, Eldertree, ...)
## call this from _setup_buildings to drop an AreaTransition that
## warps to a BaseInterior subclass with a single line.
## Pre-extraction (tick 36) HarmoniaVillage had ~20 lines of inline
## scaffolding per door; tick 37 moved the helper up to BaseVillage so
## any village can reuse it. The interior is expected to spawn the
## player at its `entrance` spawn_point.
func _add_interior_door(node_name: String, target_map: String, label: String, pos: Vector2) -> void:
	if not buildings:
		return
	var door = AreaTransitionScript.new()
	door.name = node_name
	door.target_map = target_map
	door.target_spawn = "entrance"
	door.require_interaction = false
	door.indicator_text = label
	door.show_gate_visual = true
	door.position = pos
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
	collision.shape = shape
	door.add_child(collision)
	door.collision_layer = 4
	door.collision_mask = 2
	door.monitoring = true
	door.transition_triggered.connect(_on_transition_triggered)
	buildings.add_child(door)


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


## Create a WanderingNPC that patrols a small loop. Use for ambient
## villagers who should walk between landmarks. The sprite_archetype must
## match an asset in `assets/sprites/npcs/<name>/overworld.png` (one of
## the 20 GPT-Image-1 archetype sheets shipped in 1557f89). Patrol points
## describe a closed loop including the starting position.
##
## (User feedback 2026-05-02: "village characters should walk around,
## at least some of them" — head-lock constraints already satisfied by
## the bb60068 sprite pass.)
func _create_wandering_npc(npc_name: String, archetype: String, dialogue: String, patrol_loop: Array[Vector2], dialogue_theme: String = "elder", dialogue_portrait: String = "elder") -> Area2D:
	var w = WanderingNPCScript.new()
	w.npc_name = npc_name
	w.dialogue = dialogue
	w.sprite_archetype = archetype
	w.dialogue_theme = dialogue_theme
	w.dialogue_portrait = dialogue_portrait
	w.set_patrol(patrol_loop)
	return w


func _setup_player() -> void:
	player = OverworldPlayerScript.new()
	player.name = "Player"
	player.position = spawn_points.get("default", _get_player_spawn_fallback())
	player.set_job("fighter")
	# Villages always use the slower interior speed (50% of overworld). The
	# parent-name keyword scan in OverworldPlayer is a defensive heuristic
	# but isn't guaranteed to fire before the first move (parent assignment
	# happens after add_child). Set the flag explicitly here so the first
	# step is at the correct speed. (User feedback 2026-05-02: "village walk
	# speed should be 50% slower (similar to how we made dungeon walk speed)".)
	player._is_interior = true
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
