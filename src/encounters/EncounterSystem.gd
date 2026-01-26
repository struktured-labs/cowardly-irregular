extends Node

## EncounterSystem - Manages random encounters during exploration
## Classic JRPG step-based encounter system

signal encounter_triggered(enemy_data: Array, terrain_type: String)
signal encounter_check_passed()
signal encounter_rate_changed(new_rate: float)

## Current terrain type for encounters
var current_terrain: String = "plains"

## Encounter configuration
var encounters_enabled: bool = true
var encounter_rate: float = 0.05  # 5% chance per step
var encounter_rate_modifier: float = 1.0  # Multiplier for items/abilities

## Step tracking
var steps_since_last_encounter: int = 0
var minimum_steps_between_encounters: int = 5

## Enemy pools for different areas
var current_enemy_pool: Array[String] = ["slime", "bat"]  # Default enemies
var enemy_pools: Dictionary = {}  # {area_id: [enemy_ids]}

## Special encounter modifiers
var repel_steps_remaining: int = 0  # Steps with no encounters (from repel item)
var forced_encounter_next_step: bool = false  # Force encounter on next step


func _ready() -> void:
	_load_enemy_pools()

	# Connect to player movement
	# Note: Player will emit moved signal, we'll connect when player is available


## Encounter checking
func check_for_encounter() -> bool:
	"""Check if an encounter should trigger. Returns true if encounter triggered."""
	if not encounters_enabled:
		return false

	if repel_steps_remaining > 0:
		repel_steps_remaining -= 1
		encounter_check_passed.emit()
		return false

	# Forced encounter
	if forced_encounter_next_step:
		forced_encounter_next_step = false
		_trigger_encounter()
		return true

	# Minimum steps check
	if steps_since_last_encounter < minimum_steps_between_encounters:
		steps_since_last_encounter += 1
		encounter_check_passed.emit()
		return false

	# Roll for encounter
	var chance = encounter_rate * encounter_rate_modifier
	var roll = randf()

	if roll < chance:
		_trigger_encounter()
		return true
	else:
		steps_since_last_encounter += 1
		encounter_check_passed.emit()
		return false


func _trigger_encounter() -> void:
	"""Trigger a random encounter"""
	steps_since_last_encounter = 0

	# Generate enemy party
	var enemy_data = _generate_enemy_party()

	encounter_triggered.emit(enemy_data, current_terrain)
	print("=== ENCOUNTER! (%s terrain) ===" % current_terrain)
	for enemy in enemy_data:
		print("  - %s" % enemy.get("name", "Unknown"))


func set_terrain(terrain: String) -> void:
	"""Set the current terrain type for encounters"""
	current_terrain = terrain
	print("Terrain set to: %s" % terrain)


func _generate_enemy_party() -> Array:
	"""Generate a random enemy party from the current pool"""
	if current_enemy_pool.is_empty():
		# Fallback to default enemies
		return [_create_enemy_data("slime")]

	# Decide party size (1-3 enemies, weighted toward smaller groups)
	var party_size = 1
	var size_roll = randf()
	if size_roll < 0.3:  # 30% chance for 2 enemies
		party_size = 2
	elif size_roll < 0.4:  # 10% chance for 3 enemies
		party_size = 3

	var enemy_party = []
	for i in range(party_size):
		var enemy_id = current_enemy_pool[randi() % current_enemy_pool.size()]
		enemy_party.append(_create_enemy_data(enemy_id))

	return enemy_party


func _create_enemy_data(enemy_id: String) -> Dictionary:
	"""Create enemy data from enemy ID"""
	# In full implementation, would load from enemy database
	# For now, create basic enemy data

	match enemy_id:
		"slime":
			return {
				"id": "slime",
				"name": "Slime",
				"max_hp": 80,
				"max_mp": 20,
				"attack": 10,
				"defense": 8,
				"magic": 5,
				"speed": 8,
				"elemental_weaknesses": ["fire"],
				"elemental_resistances": ["ice"]
			}

		"bat":
			return {
				"id": "bat",
				"name": "Cave Bat",
				"max_hp": 60,
				"max_mp": 15,
				"attack": 12,
				"defense": 6,
				"magic": 8,
				"speed": 15
			}

		"goblin":
			return {
				"id": "goblin",
				"name": "Goblin",
				"max_hp": 100,
				"max_mp": 10,
				"attack": 15,
				"defense": 10,
				"magic": 5,
				"speed": 12
			}

		"wolf":
			return {
				"id": "wolf",
				"name": "Feral Wolf",
				"max_hp": 120,
				"max_mp": 5,
				"attack": 18,
				"defense": 12,
				"magic": 3,
				"speed": 16
			}

		"corrupted_sprite":
			return {
				"id": "corrupted_sprite",
				"name": "Corrupted Sprite",
				"max_hp": 90,
				"max_mp": 40,
				"attack": 10,
				"defense": 8,
				"magic": 20,
				"speed": 14,
				"corruption_effects": ["reality_bending"]
			}

		_:
			# Unknown enemy, return basic slime
			return _create_enemy_data("slime")


## Configuration
func set_encounters_enabled(enabled: bool) -> void:
	"""Enable or disable random encounters"""
	encounters_enabled = enabled
	print("Encounters %s" % ("enabled" if enabled else "disabled"))


func set_encounter_rate(rate: float) -> void:
	"""Set the base encounter rate (0.0 to 1.0)"""
	encounter_rate = clamp(rate, 0.0, 1.0)
	encounter_rate_changed.emit(encounter_rate)
	print("Encounter rate set to %.1f%%" % (encounter_rate * 100))


func set_enemy_pool(enemy_ids: Array[String]) -> void:
	"""Set the current enemy pool"""
	current_enemy_pool = enemy_ids.duplicate()
	print("Enemy pool set: %s" % str(enemy_ids))


func set_enemy_pool_for_area(area_id: String) -> void:
	"""Set enemy pool based on area/dungeon"""
	if enemy_pools.has(area_id):
		current_enemy_pool = enemy_pools[area_id].duplicate()
		print("Enemy pool loaded for area: %s" % area_id)
	else:
		print("Warning: No enemy pool defined for area: %s" % area_id)


func set_encounter_rate_modifier(modifier: float) -> void:
	"""Set encounter rate modifier (for items/abilities that affect encounter rate)"""
	encounter_rate_modifier = modifier
	print("Encounter rate modifier: %.1fx" % modifier)


## Special encounters
func force_next_encounter() -> void:
	"""Force an encounter on the next step"""
	forced_encounter_next_step = true
	print("Next step will trigger an encounter")


func use_repel(steps: int) -> void:
	"""Prevent encounters for a number of steps (from repel item)"""
	repel_steps_remaining = steps
	print("Repel active for %d steps" % steps)


## Enemy pool loading
func _load_enemy_pools() -> void:
	"""Load enemy pools for different areas"""
	var data_path = "res://data/enemy_pools.json"

	if FileAccess.file_exists(data_path):
		var file = FileAccess.open(data_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()

			var json = JSON.new()
			if json.parse(json_string) == OK:
				enemy_pools = json.data
				print("Loaded %d enemy pools" % enemy_pools.size())
				return

	# Create default enemy pools
	_create_default_enemy_pools()


func _create_default_enemy_pools() -> void:
	"""Create default enemy pools for areas"""
	enemy_pools = {
		"cave_dungeon": ["slime", "bat", "goblin"],
		"forest_dungeon": ["wolf", "corrupted_sprite"],
		"overworld_plains": ["slime", "goblin"],
		"overworld_forest": ["wolf", "bat"]
	}

	print("Created default enemy pools for %d areas" % enemy_pools.size())


## Utility
func get_steps_until_guaranteed_encounter() -> int:
	"""Get approximate steps until an encounter is very likely (statistical)"""
	if encounter_rate <= 0:
		return -1  # Never
	# After N steps, probability of at least one encounter is high
	# P(encounter in N steps) = 1 - (1 - rate)^N
	# For 99% chance: N = log(0.01) / log(1 - rate)
	return int(ceil(log(0.01) / log(1.0 - encounter_rate * encounter_rate_modifier)))


func reset_encounter_counter() -> void:
	"""Reset the encounter counter"""
	steps_since_last_encounter = 0
