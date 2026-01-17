extends Node
class_name OverworldController

## OverworldController - Manages exploration state, encounters, and transitions
## Orchestrates the exploration → encounter → battle → exploration loop

const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")

signal battle_triggered(enemies: Array)
signal area_transition_requested(target_map: String, spawn_point: String)
signal menu_requested()

@export var player: CharacterBody2D  # OverworldPlayer
@export var encounter_enabled: bool = true
@export var current_area_id: String = "overworld"

## Area configuration
var _is_safe_zone: bool = false
var _encounter_rate: float = 0.05
var _enemy_pool: Array = ["slime", "bat"]


func _ready() -> void:
	if player:
		player.moved.connect(_on_player_moved)
		player.menu_requested.connect(_on_menu_requested)
		player.interaction_requested.connect(_on_interaction_requested)


func _on_player_moved(steps: int) -> void:
	if not encounter_enabled or _is_safe_zone:
		return

	# Check for random encounter
	if _check_encounter():
		_trigger_battle()


func _check_encounter() -> bool:
	# Use EncounterSystem if available, otherwise simple random
	if Engine.has_singleton("EncounterSystem"):
		var es = Engine.get_singleton("EncounterSystem")
		return es.check_for_encounter()

	# Fallback: simple random check
	return randf() < _encounter_rate


func _trigger_battle() -> void:
	# Stop player movement
	if player:
		player.set_can_move(false)

	# Generate enemy party
	var enemies = _generate_enemies()

	# Emit signal for GameLoop to handle
	battle_triggered.emit(enemies)


func _generate_enemies() -> Array:
	# Use EncounterSystem if available
	if Engine.has_singleton("EncounterSystem"):
		var es = Engine.get_singleton("EncounterSystem")
		return es.generate_enemy_party()

	# Fallback: generate 1-3 random enemies from pool
	var count = randi_range(1, 3)
	var enemies = []
	for i in range(count):
		var enemy_type = _enemy_pool[randi() % _enemy_pool.size()]
		enemies.append({"type": enemy_type})
	return enemies


func _on_menu_requested() -> void:
	menu_requested.emit()


func _on_interaction_requested() -> void:
	# Check for nearby interactables
	if not player:
		return

	# Get nearby Area2D nodes and try to interact
	var space = player.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()

	# Check slightly in front of player based on facing direction
	var check_offset = Vector2.ZERO
	match player.current_direction:
		OverworldPlayerScript.Direction.DOWN:
			check_offset = Vector2(0, 24)
		OverworldPlayerScript.Direction.UP:
			check_offset = Vector2(0, -24)
		OverworldPlayerScript.Direction.LEFT:
			check_offset = Vector2(-24, 0)
		OverworldPlayerScript.Direction.RIGHT:
			check_offset = Vector2(24, 0)

	query.position = player.global_position + check_offset
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var results = space.intersect_point(query)
	for result in results:
		var collider = result["collider"]
		if collider.has_method("interact"):
			collider.interact(player)
			return


## Configure area for encounters
func set_area_config(area_id: String, safe_zone: bool, encounter_rate: float, enemy_pool: Array) -> void:
	current_area_id = area_id
	_is_safe_zone = safe_zone
	_encounter_rate = encounter_rate
	_enemy_pool = enemy_pool


## Resume player control after battle or menu
func resume_exploration() -> void:
	if player:
		player.set_can_move(true)


## Pause player control
func pause_exploration() -> void:
	if player:
		player.set_can_move(false)
