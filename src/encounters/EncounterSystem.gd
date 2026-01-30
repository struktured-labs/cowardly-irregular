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

## Miniboss system
var miniboss_chance: float = 0.05  # 5% chance a random encounter is a miniboss instead
var miniboss_pools: Dictionary = {}  # {area_prefix: [miniboss_ids]}
var current_area_prefix: String = "cave"  # Used to pick relevant miniboss pool

## Monster database (loaded from JSON)
var monster_database: Dictionary = {}


func _ready() -> void:
	_load_enemy_pools()
	_load_monster_database()

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
	# 2% chance for rare Hero Mimics encounter
	if randf() < 0.02:
		return _generate_hero_mimics_party()

	# Miniboss chance - solo miniboss encounter
	if randf() < miniboss_chance:
		var miniboss = _try_generate_miniboss()
		if miniboss.size() > 0:
			return miniboss

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


func _try_generate_miniboss() -> Array:
	"""Try to generate a miniboss encounter based on current area"""
	# Find matching miniboss pool for current area
	var pool_key = "miniboss_" + current_area_prefix
	var miniboss_pool: Array = []

	if enemy_pools.has(pool_key):
		miniboss_pool = enemy_pools[pool_key]
	else:
		# Fallback: try all miniboss pools
		for key in enemy_pools:
			if key.begins_with("miniboss_"):
				miniboss_pool.append_array(enemy_pools[key])

	if miniboss_pool.is_empty():
		return []

	var miniboss_id = miniboss_pool[randi() % miniboss_pool.size()]
	var miniboss_data = _create_enemy_data(miniboss_id)

	if miniboss_data.get("id", "") == "slime" and miniboss_id != "slime":
		# Fallback triggered, miniboss not in database
		return []

	print("[MINIBOSS ENCOUNTER] %s appears!" % miniboss_data.get("name", "???"))
	return [miniboss_data]


func set_area_prefix(prefix: String) -> void:
	"""Set the current area prefix for miniboss pool selection"""
	current_area_prefix = prefix
	print("Area prefix set to: %s" % prefix)


func _generate_hero_mimics_party() -> Array:
	"""Generate the rare Hero Mimics encounter - 4 mimics that copy player abilities"""
	print("[RARE ENCOUNTER] Hero Mimics!")

	var enemy_party = []

	# Get player party data from GameLoop
	var player_party = []
	if get_tree().root.has_node("GameLoop"):
		var game_loop = get_tree().root.get_node("GameLoop")
		player_party = game_loop.party

	# Create 4 Hero Mimics, each copying a party member
	for i in range(4):
		var mimic_data = {
			"id": "hero_mimic",
			"name": "Hero Mimic %d" % (i + 1),
			"max_hp": 100,
			"max_mp": 50,
			"attack": 15,
			"defense": 12,
			"magic": 15,
			"speed": 14,
			"is_mimic": true,
			"mimic_index": i,
			"reward_multiplier": 2.5  # 2.5x rewards
		}

		# Copy stats from corresponding party member if available
		if i < player_party.size():
			var member = player_party[i]
			mimic_data["name"] = "%s Mimic" % member.combatant_name
			mimic_data["max_hp"] = int(member.max_hp * 0.8)  # Slightly weaker
			mimic_data["max_mp"] = member.max_mp
			mimic_data["attack"] = member.attack
			mimic_data["defense"] = int(member.defense * 0.9)
			mimic_data["magic"] = member.magic
			mimic_data["speed"] = member.speed
			# Copy job abilities
			if member.job:
				mimic_data["copied_job"] = member.job.get("id", "fighter")
				mimic_data["copied_abilities"] = member.job.get("abilities", [])

		enemy_party.append(mimic_data)

	return enemy_party


func _create_enemy_data(enemy_id: String) -> Dictionary:
	"""Create enemy data from monster database or fallback"""
	# Load from monster database first
	if monster_database.has(enemy_id):
		var db_entry = monster_database[enemy_id]
		var stats = db_entry.get("stats", {})
		var data = {
			"id": db_entry.get("id", enemy_id),
			"name": db_entry.get("name", enemy_id.capitalize()),
			"max_hp": stats.get("max_hp", 80),
			"max_mp": stats.get("max_mp", 20),
			"attack": stats.get("attack", 10),
			"defense": stats.get("defense", 8),
			"magic": stats.get("magic", 5),
			"speed": stats.get("speed", 8),
			"elemental_weaknesses": db_entry.get("weaknesses", []),
			"elemental_resistances": db_entry.get("resistances", []),
			"abilities": db_entry.get("abilities", []),
			"exp_reward": db_entry.get("exp_reward", 10),
			"gold_reward": db_entry.get("gold_reward", 5),
			"drop_table": db_entry.get("drop_table", [])
		}
		# Copy special flags
		for flag in ["boss", "miniboss", "undead", "meta_enemy", "adaptive",
					"autogrind_spawned", "corruption_spawned", "is_mimic",
					"self_aware", "very_dangerous", "extremely_dangerous",
					"can_cause_permadeath", "dialogue"]:
			if db_entry.has(flag):
				data[flag] = db_entry[flag]
		return data

	# Legacy hardcoded fallbacks for enemies not yet in database
	match enemy_id:
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

		"glitch_entity":
			return {
				"id": "glitch_entity",
				"name": "Glitch Entity",
				"max_hp": 110,
				"max_mp": 50,
				"attack": 15,
				"defense": 10,
				"magic": 25,
				"speed": 13,
				"meta_enemy": true
			}

		_:
			# Unknown enemy, return basic slime from database or hardcoded
			if monster_database.has("slime"):
				return _create_enemy_data("slime")
			return {
				"id": "slime",
				"name": "Slime",
				"max_hp": 80,
				"max_mp": 20,
				"attack": 10,
				"defense": 8,
				"magic": 5,
				"speed": 8
			}


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
		"forest_dungeon": ["wolf", "corrupted_sprite", "mushroom"],
		"overworld_plains": ["slime", "goblin", "bat"],
		"overworld_forest": ["wolf", "bat", "mushroom"],
		"miniboss_cave": ["cave_troll", "treasure_mimic", "cursed_armor", "crystal_golem"],
		"miniboss_forest": ["blood_wolf_alpha", "ironback_beetle", "elder_mushroom"],
		"miniboss_corrupted": ["rogue_automaton", "shadow_knight"]
	}

	print("Created default enemy pools for %d areas" % enemy_pools.size())


func _load_monster_database() -> void:
	"""Load monster data from monsters.json"""
	var data_path = "res://data/monsters.json"

	if FileAccess.file_exists(data_path):
		var file = FileAccess.open(data_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()

			var json = JSON.new()
			if json.parse(json_string) == OK:
				monster_database = json.data
				print("Loaded %d monsters from database" % monster_database.size())
				return

	print("Warning: Could not load monster database")


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
