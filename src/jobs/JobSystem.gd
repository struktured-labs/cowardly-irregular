extends Node

## JobSystem - Manages job data, abilities, and job-specific mechanics
## Jobs define what abilities a combatant can use and their stat modifiers

signal job_changed(combatant: Combatant, old_job: Dictionary, new_job: Dictionary)

## Loaded job data
var jobs: Dictionary = {}
var abilities: Dictionary = {}

## Job categories
enum JobType {
	STARTER,      # Basic jobs (Fighter, White Mage, etc.)
	ADVANCED,     # Unlockable jobs
	META          # Meta jobs (Scriptweaver, Time Mage, etc.)
}


func _ready() -> void:
	_load_job_data()
	_load_ability_data()


func _load_job_data() -> void:
	"""Load job definitions from data/jobs.json"""
	var file_path = "res://data/jobs.json"

	if not FileAccess.file_exists(file_path):
		print("Warning: jobs.json not found, using default jobs")
		_create_default_jobs()
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()

		var json = JSON.new()
		var parse_result = json.parse(json_string)

		if parse_result == OK:
			jobs = json.data
			print("Loaded %d jobs" % jobs.size())
		else:
			print("Error parsing jobs.json: ", json.get_error_message())
			_create_default_jobs()
	else:
		_create_default_jobs()


func _load_ability_data() -> void:
	"""Load ability definitions from data/abilities.json"""
	var file_path = "res://data/abilities.json"

	if not FileAccess.file_exists(file_path):
		print("Warning: abilities.json not found, using default abilities")
		_create_default_abilities()
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()

		var json = JSON.new()
		var parse_result = json.parse(json_string)

		if parse_result == OK:
			abilities = json.data
			print("Loaded %d abilities" % abilities.size())
		else:
			print("Error parsing abilities.json: ", json.get_error_message())
			_create_default_abilities()
	else:
		_create_default_abilities()


func _create_default_jobs() -> void:
	"""Create default starter jobs if file doesn't exist"""
	jobs = {
		"fighter": {
			"id": "fighter",
			"name": "Fighter",
			"type": JobType.STARTER,
			"description": "A warrior skilled in physical combat",
			"stat_modifiers": {
				"max_hp": 120,
				"attack": 15,
				"defense": 12,
				"magic": 5,
				"speed": 8
			},
			"abilities": ["power_strike", "provoke"],
			"passive_abilities": ["weapon_mastery"]
		},
		"white_mage": {
			"id": "white_mage",
			"name": "White Mage",
			"type": JobType.STARTER,
			"description": "A healer who uses restorative magic",
			"stat_modifiers": {
				"max_hp": 80,
				"attack": 5,
				"defense": 8,
				"magic": 18,
				"speed": 10
			},
			"abilities": ["cure", "cura", "raise"],
			"passive_abilities": ["healing_boost"]
		},
		"black_mage": {
			"id": "black_mage",
			"name": "Black Mage",
			"type": JobType.STARTER,
			"description": "A mage who wields destructive magic",
			"stat_modifiers": {
				"max_hp": 70,
				"attack": 5,
				"defense": 6,
				"magic": 20,
				"speed": 9
			},
			"abilities": ["fire", "blizzard", "thunder"],
			"passive_abilities": ["magic_boost"]
		},
		"scriptweaver": {
			"id": "scriptweaver",
			"name": "Scriptweaver",
			"type": JobType.META,
			"description": "A meta job that can edit game formulas and constants",
			"stat_modifiers": {
				"max_hp": 90,
				"attack": 10,
				"defense": 10,
				"magic": 15,
				"speed": 12
			},
			"abilities": ["edit_formula", "modify_constant", "analyze_code"],
			"passive_abilities": ["formula_sight", "autobattle_verbs"],
			"meta_powers": {
				"can_edit_damage_formulas": true,
				"can_modify_exp_rates": true,
				"can_view_game_constants": true
			}
		}
	}


func _create_default_abilities() -> void:
	"""Create default abilities if file doesn't exist"""
	abilities = {
		"power_strike": {
			"id": "power_strike",
			"name": "Power Strike",
			"type": "physical",
			"mp_cost": 8,
			"description": "A powerful physical attack dealing 1.5x damage",
			"damage_multiplier": 1.5,
			"target_type": "single_enemy"
		},
		"provoke": {
			"id": "provoke",
			"name": "Provoke",
			"type": "support",
			"mp_cost": 5,
			"description": "Force an enemy to target you",
			"target_type": "single_enemy",
			"effect": "taunt"
		},
		"cure": {
			"id": "cure",
			"name": "Cure",
			"type": "healing",
			"mp_cost": 6,
			"description": "Restore HP to one ally",
			"heal_amount": 50,
			"target_type": "single_ally"
		},
		"cura": {
			"id": "cura",
			"name": "Cura",
			"type": "healing",
			"mp_cost": 12,
			"description": "Restore HP to one ally",
			"heal_amount": 120,
			"target_type": "single_ally"
		},
		"raise": {
			"id": "raise",
			"name": "Raise",
			"type": "revival",
			"mp_cost": 20,
			"description": "Revive a fallen ally with 50% HP",
			"target_type": "dead_ally"
		},
		"fire": {
			"id": "fire",
			"name": "Fire",
			"type": "magic",
			"mp_cost": 8,
			"description": "Fire magic damage to one enemy",
			"damage_multiplier": 2.0,
			"element": "fire",
			"target_type": "single_enemy"
		},
		"blizzard": {
			"id": "blizzard",
			"name": "Blizzard",
			"type": "magic",
			"mp_cost": 8,
			"description": "Ice magic damage to one enemy",
			"damage_multiplier": 2.0,
			"element": "ice",
			"target_type": "single_enemy"
		},
		"thunder": {
			"id": "thunder",
			"name": "Thunder",
			"type": "magic",
			"mp_cost": 8,
			"description": "Lightning magic damage to one enemy",
			"damage_multiplier": 2.0,
			"element": "lightning",
			"target_type": "single_enemy"
		},
		"edit_formula": {
			"id": "edit_formula",
			"name": "Edit Formula",
			"type": "meta",
			"mp_cost": 30,
			"description": "Temporarily modify a damage or healing formula",
			"target_type": "self",
			"meta_effect": "formula_modification"
		},
		"modify_constant": {
			"id": "modify_constant",
			"name": "Modify Constant",
			"type": "meta",
			"mp_cost": 25,
			"description": "Change a game constant (EXP rate, drop rate, etc.)",
			"target_type": "self",
			"meta_effect": "constant_modification"
		},
		"analyze_code": {
			"id": "analyze_code",
			"name": "Analyze Code",
			"type": "meta",
			"mp_cost": 15,
			"description": "View the actual game code for current battle logic",
			"target_type": "self",
			"meta_effect": "code_inspection"
		}
	}


## Job management
func assign_job(combatant: Combatant, job_id: String) -> bool:
	"""Assign a job to a combatant"""
	if not jobs.has(job_id):
		print("Error: Job '%s' not found" % job_id)
		return false

	var job = jobs[job_id]
	var old_job = combatant.job

	combatant.job = job
	_apply_job_stats(combatant, job)

	job_changed.emit(combatant, old_job, job)
	return true


func _apply_job_stats(combatant: Combatant, job: Dictionary) -> void:
	"""Apply job stat modifiers to combatant"""
	if not job.has("stat_modifiers"):
		return

	var mods = job["stat_modifiers"]

	if mods.has("max_hp"):
		combatant.max_hp = mods["max_hp"]
		combatant.current_hp = combatant.max_hp
	if mods.has("attack"):
		combatant.attack = mods["attack"]
	if mods.has("defense"):
		combatant.defense = mods["defense"]
	if mods.has("magic"):
		combatant.magic = mods["magic"]
	if mods.has("speed"):
		combatant.speed = mods["speed"]


func get_job(job_id: String) -> Dictionary:
	"""Get job data by ID"""
	return jobs.get(job_id, {})


func get_job_abilities(job_id: String) -> Array:
	"""Get all abilities for a job"""
	var job = get_job(job_id)
	if not job.has("abilities"):
		return []
	return job["abilities"]


func get_ability(ability_id: String) -> Dictionary:
	"""Get ability data by ID"""
	return abilities.get(ability_id, {})


func can_use_ability(combatant: Combatant, ability_id: String) -> bool:
	"""Check if combatant can use an ability"""
	var ability = get_ability(ability_id)
	if ability.is_empty():
		return false

	# Check MP cost
	if ability.has("mp_cost"):
		if combatant.current_mp < ability["mp_cost"]:
			return false

	# Check job restrictions
	if combatant.job and combatant.job.has("abilities"):
		if not ability_id in combatant.job["abilities"]:
			return false

	return true


## Utility
func get_jobs_by_type(type: JobType) -> Array:
	"""Get all jobs of a specific type"""
	var filtered_jobs = []
	for job_id in jobs:
		var job = jobs[job_id]
		if job.get("type", JobType.STARTER) == type:
			filtered_jobs.append(job)
	return filtered_jobs


func get_starter_jobs() -> Array:
	"""Get all starter jobs"""
	return get_jobs_by_type(JobType.STARTER)


func get_meta_jobs() -> Array:
	"""Get all meta jobs"""
	return get_jobs_by_type(JobType.META)
