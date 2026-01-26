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
	# Apply settings multiplier from GameState
	var rate_multiplier = 1.0
	if GameState:
		rate_multiplier = GameState.encounter_rate_multiplier

	# If multiplier is 0, no encounters
	if rate_multiplier <= 0.0:
		return false

	# Use EncounterSystem if available, otherwise simple random
	if Engine.has_singleton("EncounterSystem"):
		var es = Engine.get_singleton("EncounterSystem")
		# EncounterSystem should also respect the multiplier
		return es.check_for_encounter() and randf() < rate_multiplier

	# Fallback: simple random check with multiplier
	return randf() < (_encounter_rate * rate_multiplier)


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

	# Return empty if no enemies in pool (boss-only floors)
	if _enemy_pool.is_empty():
		return []

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

	DebugLogOverlay.log("[INTERACT] At pos: %s" % player.global_position)

	# Get nearby Area2D nodes and try to interact
	var space = player.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()

	# Check slightly in front of player based on facing direction
	var check_offset = Vector2.ZERO
	match player.current_direction:
		OverworldPlayerScript.Direction.DOWN:
			check_offset = Vector2(0, 20)
		OverworldPlayerScript.Direction.UP:
			check_offset = Vector2(0, -20)
		OverworldPlayerScript.Direction.LEFT:
			check_offset = Vector2(-20, 0)
		OverworldPlayerScript.Direction.RIGHT:
			check_offset = Vector2(20, 0)

	query.position = player.global_position + check_offset
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 4  # Layer 4 = interactables (NPCs, transitions, etc.)

	var results = space.intersect_point(query)
	for result in results:
		var collider = result["collider"]
		if collider.has_method("interact"):
			DebugLogOverlay.log("[INTERACT] Found: %s (physics)" % collider.name)
			collider.interact(player)
			return

	# Also check at player's position (for when standing on/in interactable)
	query.position = player.global_position
	results = space.intersect_point(query)
	for result in results:
		var collider = result["collider"]
		if collider.has_method("interact"):
			DebugLogOverlay.log("[INTERACT] Found: %s (standing)" % collider.name)
			collider.interact(player)
			return

	# Fallback: check interactables group by distance (more reliable than physics queries)
	var interactables = player.get_tree().get_nodes_in_group("interactables")
	var interaction_range = 48.0  # ~1.5 tiles
	for interactable in interactables:
		if interactable.has_method("interact"):
			var dist = player.global_position.distance_to(interactable.global_position)
			if dist <= interaction_range:
				DebugLogOverlay.log("[INTERACT] Found: %s (dist: %.0f)" % [interactable.name, dist])
				interactable.interact(player)
				return

	DebugLogOverlay.log("[INTERACT] Nothing found")


## Configure area for encounters
func set_area_config(area_id: String, safe_zone: bool, encounter_rate: float, enemy_pool: Array) -> void:
	current_area_id = area_id
	_is_safe_zone = safe_zone
	_encounter_rate = encounter_rate
	_enemy_pool = enemy_pool


## Set enemy pool directly (convenience method)
func set_enemy_pool(pool_id: String) -> void:
	"""Load enemy pool from enemy_pools.json by ID"""
	var pools = _load_enemy_pools()
	if pools.has(pool_id):
		_enemy_pool = pools[pool_id]
		print("Loaded enemy pool '%s': %s" % [pool_id, _enemy_pool])
	else:
		print("Warning: Enemy pool '%s' not found" % pool_id)


func _load_enemy_pools() -> Dictionary:
	"""Load enemy pools from data file"""
	var file_path = "res://data/enemy_pools.json"
	if not FileAccess.file_exists(file_path):
		return {}

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) == OK:
		return json.data
	return {}


## Resume player control after battle or menu
func resume_exploration() -> void:
	if player:
		player.set_can_move(true)


## Pause player control
func pause_exploration() -> void:
	if player:
		player.set_can_move(false)
