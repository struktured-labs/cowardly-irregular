extends GutTest

## Regression tests for Job System
## Covers: job assignment, secondary job, job profiles, stat modifiers
## Loads data directly from JSON - no autoload singletons needed

const CombatantScript = preload("res://src/battle/Combatant.gd")

var _jobs: Dictionary
var _abilities: Dictionary
var _combatant: Combatant


func _load_json(path: String) -> Variant:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()
	if error != OK:
		return null
	return json.data


func before_all() -> void:
	_jobs = _load_json("res://data/jobs.json")
	if _jobs == null:
		_jobs = {}
	_abilities = _load_json("res://data/abilities.json")
	if _abilities == null:
		_abilities = {}


func before_each() -> void:
	_combatant = CombatantScript.new()
	_combatant.combatant_name = "Test Hero"
	_combatant.max_hp = 100
	_combatant.current_hp = 100
	_combatant.max_mp = 50
	_combatant.current_mp = 50
	add_child_autofree(_combatant)


## ---- Manual Job Assignment (No Autoload) ----

func _assign_job_manually(combatant: Combatant, job_id: String) -> bool:
	"""Mimics what JobSystem.assign_job() does, using raw data"""
	if not _jobs.has(job_id):
		return false
	var job_data = _jobs[job_id]
	combatant.job = job_data
	# Apply stat modifiers
	var mods = job_data.get("stat_modifiers", {})
	combatant.max_hp = int(mods.get("max_hp", 100))
	combatant.max_mp = int(mods.get("max_mp", 50))
	combatant.attack = int(mods.get("attack", 10))
	combatant.defense = int(mods.get("defense", 10))
	combatant.magic = int(mods.get("magic", 10))
	combatant.speed = int(mods.get("speed", 10))
	combatant.current_hp = combatant.max_hp
	combatant.current_mp = combatant.max_mp
	return true


## ---- Job Assignment ----

func test_assign_valid_primary_job() -> void:
	var result = _assign_job_manually(_combatant, "fighter")
	assert_true(result, "Assigning fighter should succeed")
	assert_not_null(_combatant.job, "Combatant should have a job after assignment")
	assert_eq(_combatant.job["id"], "fighter", "Job ID should be fighter")


func test_assign_invalid_job_returns_false() -> void:
	var result = _assign_job_manually(_combatant, "nonexistent_job_xyz")
	assert_false(result, "Assigning nonexistent job should fail")


func test_assign_all_starter_jobs() -> void:
	for job_id in ["fighter", "white_mage", "black_mage", "thief"]:
		var c = CombatantScript.new()
		add_child_autofree(c)
		var result = _assign_job_manually(c, job_id)
		assert_true(result, "Should be able to assign starter job: %s" % job_id)
		assert_eq(c.job["id"], job_id, "Job ID should match: %s" % job_id)


func test_assign_all_advanced_jobs() -> void:
	for job_id in ["guardian", "ninja", "summoner"]:
		var c = CombatantScript.new()
		add_child_autofree(c)
		var result = _assign_job_manually(c, job_id)
		assert_true(result, "Should be able to assign advanced job: %s" % job_id)


func test_assign_all_meta_jobs() -> void:
	for job_id in ["scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter"]:
		var c = CombatantScript.new()
		add_child_autofree(c)
		var result = _assign_job_manually(c, job_id)
		assert_true(result, "Should be able to assign meta job: %s" % job_id)


## ---- Secondary Job ----

func test_assign_secondary_job() -> void:
	_assign_job_manually(_combatant, "fighter")
	_combatant.secondary_job_id = "thief"
	_combatant.secondary_job = _jobs.get("thief", null)

	assert_eq(_combatant.secondary_job_id, "thief", "Secondary job ID should be thief")
	assert_not_null(_combatant.secondary_job, "Secondary job data should exist")


func test_clear_secondary_job() -> void:
	"""Regression: clearing secondary job should work via __none__ sentinel"""
	_assign_job_manually(_combatant, "fighter")
	_combatant.secondary_job_id = "thief"
	_combatant.secondary_job = _jobs.get("thief", null)

	# Simulate what JobMenu does for __none__
	_combatant.secondary_job = null
	_combatant.secondary_job_id = ""

	assert_null(_combatant.secondary_job, "Secondary job should be null after clearing")
	assert_eq(_combatant.secondary_job_id, "", "Secondary job ID should be empty after clearing")


func test_secondary_job_profile_key_changes() -> void:
	"""Profile key should update when secondary changes"""
	_assign_job_manually(_combatant, "fighter")
	_combatant.secondary_job_id = ""
	var key1 = _combatant.get_profile_key()

	_combatant.secondary_job_id = "thief"
	_combatant.secondary_job = _jobs.get("thief", null)
	var key2 = _combatant.get_profile_key()

	assert_eq(key1, "fighter:", "Key without secondary should be fighter:")
	assert_eq(key2, "fighter:thief", "Key with secondary should be fighter:thief")


func test_switch_secondary_changes_profile_key() -> void:
	_assign_job_manually(_combatant, "fighter")
	_combatant.secondary_job_id = "thief"
	var key1 = _combatant.get_profile_key()

	_combatant.secondary_job_id = "white_mage"
	var key2 = _combatant.get_profile_key()

	assert_ne(key1, key2, "Switching secondary should produce different key")
	assert_eq(key2, "fighter:white_mage")


## ---- Job Stats ----

func test_job_applies_stat_modifiers() -> void:
	_assign_job_manually(_combatant, "fighter")
	# Fighter stats from jobs.json
	var fighter = _jobs["fighter"]
	var mods = fighter.get("stat_modifiers", {})
	assert_eq(_combatant.max_hp, int(mods.get("max_hp", 100)),
		"Fighter should have correct max HP from stat_modifiers")
	assert_eq(_combatant.attack, int(mods.get("attack", 10)),
		"Fighter should have correct attack from stat_modifiers")


func test_job_change_updates_stats() -> void:
	_assign_job_manually(_combatant, "fighter")
	var fighter_attack = _combatant.attack

	_assign_job_manually(_combatant, "white_mage")
	var wm_attack = _combatant.attack

	assert_ne(fighter_attack, wm_attack,
		"Stats should change on job switch (fighter atk=%d, white_mage atk=%d)" % [fighter_attack, wm_attack])


func test_fighter_has_higher_attack_than_white_mage() -> void:
	var fighter_atk = int(_jobs.get("fighter", {}).get("stat_modifiers", {}).get("attack", 0))
	var wm_atk = int(_jobs.get("white_mage", {}).get("stat_modifiers", {}).get("attack", 0))
	assert_gt(fighter_atk, wm_atk,
		"Fighter should have higher attack than White Mage (%d vs %d)" % [fighter_atk, wm_atk])


func test_white_mage_has_higher_magic_than_fighter() -> void:
	var fighter_mag = int(_jobs.get("fighter", {}).get("stat_modifiers", {}).get("magic", 0))
	var wm_mag = int(_jobs.get("white_mage", {}).get("stat_modifiers", {}).get("magic", 0))
	assert_gt(wm_mag, fighter_mag,
		"White Mage should have higher magic than Fighter (%d vs %d)" % [wm_mag, fighter_mag])


## ---- Data Integrity (loaded from JSON) ----

func test_all_jobs_exist_in_data() -> void:
	"""Ensure all 12 expected jobs are loaded"""
	var expected_jobs = [
		"fighter", "white_mage", "black_mage", "thief",
		"guardian", "ninja", "summoner",
		"scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter"
	]
	for job_id in expected_jobs:
		assert_true(_jobs.has(job_id),
			"jobs.json should have job: %s" % job_id)


func test_all_jobs_have_required_fields() -> void:
	for job_id in _jobs:
		var job = _jobs[job_id]
		assert_true(job.has("id"), "Job %s should have id" % job_id)
		assert_true(job.has("name"), "Job %s should have name" % job_id)
		assert_true(job.has("type"), "Job %s should have type" % job_id)
		assert_true(job.has("stat_modifiers"), "Job %s should have stat_modifiers" % job_id)
		assert_true(job.has("abilities"), "Job %s should have abilities" % job_id)
		assert_true(job.has("visual"), "Job %s should have visual" % job_id)


func test_job_types_are_valid() -> void:
	"""Job types: 0=starter, 1=advanced, 2=meta"""
	for job_id in _jobs:
		var job = _jobs[job_id]
		var job_type = int(job["type"])
		assert_true(job_type in [0, 1, 2],
			"Job %s type should be 0, 1, or 2 (got %d)" % [job_id, job_type])


func test_starter_jobs_have_type_zero() -> void:
	for job_id in ["fighter", "white_mage", "black_mage", "thief"]:
		if _jobs.has(job_id):
			assert_eq(int(_jobs[job_id]["type"]), 0,
				"%s should be type 0 (starter)" % job_id)


func test_all_job_abilities_exist() -> void:
	"""Regression: every ability referenced by a job must exist in abilities.json"""
	for job_id in _jobs:
		var job = _jobs[job_id]
		for ability_id in job.get("abilities", []):
			assert_true(_abilities.has(ability_id),
				"Job %s references ability '%s' which doesn't exist" % [job_id, ability_id])


func test_all_job_stat_modifiers_have_valid_keys() -> void:
	var valid_stats = ["max_hp", "max_mp", "attack", "defense", "magic", "speed"]
	for job_id in _jobs:
		var mods = _jobs[job_id].get("stat_modifiers", {})
		for stat in mods:
			assert_true(stat in valid_stats,
				"Job %s has invalid stat modifier: %s" % [job_id, stat])


## ---- Profile Save/Load with Job Data ----

func test_profile_saves_equipment_after_job_assign() -> void:
	_assign_job_manually(_combatant, "fighter")
	_combatant.secondary_job_id = ""
	_combatant.equipped_weapon = "iron_sword"
	_combatant.equipped_armor = "leather_armor"
	_combatant.save_current_profile()

	assert_true(_combatant.job_profiles.has("fighter:"),
		"Profile should be saved with key fighter:")
	assert_eq(_combatant.job_profiles["fighter:"]["weapon"], "iron_sword")


func test_profile_preserved_on_job_switch() -> void:
	_assign_job_manually(_combatant, "fighter")
	_combatant.secondary_job_id = ""
	_combatant.equipped_weapon = "iron_sword"
	_combatant.save_current_profile()

	_assign_job_manually(_combatant, "white_mage")
	_combatant.secondary_job_id = ""
	_combatant.equipped_weapon = "wooden_staff"
	_combatant.save_current_profile()

	# Switch back to fighter
	_assign_job_manually(_combatant, "fighter")
	_combatant.secondary_job_id = ""
	_combatant.load_profile("fighter:")

	assert_eq(_combatant.equipped_weapon, "iron_sword",
		"Loading fighter profile should restore iron_sword")
