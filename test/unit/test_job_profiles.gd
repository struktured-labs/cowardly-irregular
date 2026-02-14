extends GutTest

## Comprehensive tests for the Job Profile System
## Covers: profile key generation, save/load/fork profiles,
## job switching with profile persistence, serialization

const CombatantScript = preload("res://src/battle/Combatant.gd")

var _combatant: Combatant


## Helper: set typed array via clear+append (GDScript typed arrays can't be assigned directly)
func _set_passives(c: Combatant, passives: Array) -> void:
	c.equipped_passives.clear()
	for p in passives:
		c.equipped_passives.append(p)


func before_each() -> void:
	_combatant = CombatantScript.new()
	_combatant.combatant_name = "Test Hero"
	_combatant.max_hp = 120
	_combatant.current_hp = 120
	_combatant.max_mp = 60
	_combatant.current_mp = 60
	_combatant.attack = 15
	_combatant.defense = 12
	_combatant.magic = 5
	_combatant.speed = 8
	_combatant.equipped_weapon = "iron_sword"
	_combatant.equipped_armor = "leather_armor"
	_combatant.equipped_accessory = "power_ring"
	_set_passives(_combatant, ["weapon_mastery"])
	add_child_autofree(_combatant)


## ---- Profile Key Generation ----

func test_profile_key_with_primary_only() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	var key = _combatant.get_profile_key()
	assert_eq(key, "fighter:", "Profile key with no secondary should be 'fighter:'")


func test_profile_key_with_primary_and_secondary() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = "thief"
	var key = _combatant.get_profile_key()
	assert_eq(key, "fighter:thief", "Profile key should be 'fighter:thief'")


func test_profile_key_with_different_primary() -> void:
	_combatant.job = {"id": "white_mage", "name": "White Mage"}
	_combatant.secondary_job_id = "black_mage"
	var key = _combatant.get_profile_key()
	assert_eq(key, "white_mage:black_mage", "Profile key should reflect actual jobs")


func test_profile_key_defaults_to_fighter_when_no_job() -> void:
	_combatant.job = null
	_combatant.secondary_job_id = ""
	var key = _combatant.get_profile_key()
	assert_eq(key, "fighter:", "Should default to fighter when job is null")


func test_profile_key_changes_after_job_change() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	var key1 = _combatant.get_profile_key()

	_combatant.job = {"id": "thief", "name": "Thief"}
	var key2 = _combatant.get_profile_key()

	assert_ne(key1, key2, "Key should change when primary job changes")
	assert_eq(key2, "thief:", "New key should reflect thief")


func test_profile_key_changes_after_secondary_change() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	var key1 = _combatant.get_profile_key()

	_combatant.secondary_job_id = "white_mage"
	var key2 = _combatant.get_profile_key()

	assert_ne(key1, key2, "Key should change when secondary job changes")
	assert_eq(key2, "fighter:white_mage", "New key should include secondary")


## ---- Save Profile ----

func test_save_current_profile_creates_entry() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	_combatant.save_current_profile()

	assert_true(_combatant.job_profiles.has("fighter:"), "Profile should be saved")


func test_save_current_profile_stores_equipment() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	_combatant.save_current_profile()

	var profile = _combatant.job_profiles["fighter:"]
	assert_eq(profile["weapon"], "iron_sword", "Weapon should be saved")
	assert_eq(profile["armor"], "leather_armor", "Armor should be saved")
	assert_eq(profile["accessory"], "power_ring", "Accessory should be saved")


func test_save_current_profile_stores_passives() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	_combatant.save_current_profile()

	var profile = _combatant.job_profiles["fighter:"]
	assert_eq(profile["passives"].size(), 1, "Should save 1 passive")
	assert_eq(profile["passives"][0], "weapon_mastery", "Should save weapon_mastery passive")


func test_save_profile_overwrites_previous() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""

	# Save with iron_sword
	_combatant.save_current_profile()
	assert_eq(_combatant.job_profiles["fighter:"]["weapon"], "iron_sword")

	# Change weapon and save again
	_combatant.equipped_weapon = "flame_sword"
	_combatant.save_current_profile()
	assert_eq(_combatant.job_profiles["fighter:"]["weapon"], "flame_sword",
		"Save should overwrite previous profile")


func test_save_profile_does_not_share_references() -> void:
	"""Regression: passives array must be duplicated, not referenced"""
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	_combatant.save_current_profile()

	# Modify the original passives
	_combatant.equipped_passives.append("critical_strike")

	# Saved profile should NOT have the new passive
	var saved_passives = _combatant.job_profiles["fighter:"]["passives"]
	assert_eq(saved_passives.size(), 1,
		"Saved profile passives should not be modified by later changes to equipped_passives")


func test_save_multiple_profiles() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	_combatant.save_current_profile()

	_combatant.secondary_job_id = "thief"
	_combatant.equipped_weapon = "poison_dagger"
	_combatant.save_current_profile()

	assert_true(_combatant.job_profiles.has("fighter:"), "First profile should exist")
	assert_true(_combatant.job_profiles.has("fighter:thief"), "Second profile should exist")
	assert_eq(_combatant.job_profiles["fighter:"]["weapon"], "iron_sword")
	assert_eq(_combatant.job_profiles["fighter:thief"]["weapon"], "poison_dagger")


## ---- Load Profile ----

func test_load_profile_restores_equipment() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""

	# Save current profile (iron_sword, leather_armor, power_ring)
	_combatant.save_current_profile()

	# Change equipment
	_combatant.equipped_weapon = "flame_sword"
	_combatant.equipped_armor = "mage_robe"
	_combatant.equipped_accessory = "magic_ring"

	# Load the saved profile
	_combatant.load_profile("fighter:")

	assert_eq(_combatant.equipped_weapon, "iron_sword", "Weapon should be restored")
	assert_eq(_combatant.equipped_armor, "leather_armor", "Armor should be restored")
	assert_eq(_combatant.equipped_accessory, "power_ring", "Accessory should be restored")


func test_load_profile_restores_passives() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""

	_combatant.save_current_profile()

	# Change passives
	_set_passives(_combatant, ["magic_boost", "healing_boost"])

	# Load saved profile
	_combatant.load_profile("fighter:")

	assert_eq(_combatant.equipped_passives.size(), 1, "Should restore 1 passive")
	assert_eq(_combatant.equipped_passives[0], "weapon_mastery", "Should restore weapon_mastery")


func test_load_nonexistent_profile_does_nothing() -> void:
	_combatant.equipped_weapon = "iron_sword"
	_combatant.load_profile("nonexistent:key")
	assert_eq(_combatant.equipped_weapon, "iron_sword",
		"Equipment should be unchanged when loading nonexistent profile")


func test_load_profile_with_empty_equipment() -> void:
	_combatant.job = {"id": "white_mage", "name": "White Mage"}
	_combatant.secondary_job_id = ""
	_combatant.equipped_weapon = ""
	_combatant.equipped_armor = ""
	_combatant.equipped_accessory = ""
	_set_passives(_combatant, [])
	_combatant.save_current_profile()

	# Change to something else
	_combatant.equipped_weapon = "holy_staff"
	_set_passives(_combatant, ["healing_boost"])

	# Load empty profile
	_combatant.load_profile("white_mage:")

	assert_eq(_combatant.equipped_weapon, "", "Should restore empty weapon")
	assert_eq(_combatant.equipped_passives.size(), 0, "Should restore empty passives")


## ---- Fork Profile ----

func test_fork_profile_copies_data() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	_combatant.save_current_profile()

	_combatant.fork_profile("fighter:", "fighter:thief")

	assert_true(_combatant.job_profiles.has("fighter:thief"), "Forked profile should exist")
	assert_eq(_combatant.job_profiles["fighter:thief"]["weapon"], "iron_sword",
		"Forked profile should have same weapon")
	assert_eq(_combatant.job_profiles["fighter:thief"]["armor"], "leather_armor",
		"Forked profile should have same armor")


func test_fork_profile_is_deep_copy() -> void:
	"""Regression: fork must deep-copy, not share references"""
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	_combatant.save_current_profile()

	_combatant.fork_profile("fighter:", "fighter:thief")

	# Modify the original profile
	_combatant.job_profiles["fighter:"]["weapon"] = "mythril_sword"

	# Forked profile should not be affected
	assert_eq(_combatant.job_profiles["fighter:thief"]["weapon"], "iron_sword",
		"Forked profile should be independent from source")


func test_fork_from_nonexistent_source() -> void:
	_combatant.fork_profile("nonexistent:", "new_key:")

	# Should not create anything (graceful no-op)
	assert_false(_combatant.job_profiles.has("new_key:"),
		"Fork from nonexistent source should not create dest profile")


func test_fork_preserves_passives_array() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	_set_passives(_combatant, ["weapon_mastery", "critical_strike"])
	_combatant.save_current_profile()

	_combatant.fork_profile("fighter:", "fighter:black_mage")

	var forked_passives = _combatant.job_profiles["fighter:black_mage"]["passives"]
	assert_eq(forked_passives.size(), 2, "Forked passives should have 2 entries")
	assert_true("weapon_mastery" in forked_passives, "Should contain weapon_mastery")
	assert_true("critical_strike" in forked_passives, "Should contain critical_strike")


## ---- Full Job Switch Workflow ----

func test_job_switch_saves_and_loads_profiles() -> void:
	"""Simulate the full job switch flow from JobMenu"""
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		pending("JobSystem not available")
		return

	# Start as fighter
	job_system.assign_job(_combatant, "fighter")
	_combatant.secondary_job_id = ""
	_combatant.equipped_weapon = "iron_sword"
	_set_passives(_combatant, ["weapon_mastery"])

	# Save current profile
	var old_key = _combatant.get_profile_key()
	_combatant.save_current_profile()
	assert_eq(old_key, "fighter:")

	# Switch to thief
	job_system.assign_job(_combatant, "thief")
	var new_key = _combatant.get_profile_key()
	assert_eq(new_key, "thief:")

	# No thief profile yet, so fork
	if not _combatant.job_profiles.has(new_key):
		_combatant.fork_profile(old_key, new_key)

	# Modify equipment for thief
	_combatant.equipped_weapon = "iron_dagger"
	_set_passives(_combatant, ["steal_boost"])
	_combatant.save_current_profile()

	# Switch back to fighter
	_combatant.save_current_profile()
	job_system.assign_job(_combatant, "fighter")
	_combatant.load_profile("fighter:")

	# Should have fighter equipment restored
	assert_eq(_combatant.equipped_weapon, "iron_sword",
		"Switching back to fighter should restore iron_sword")
	assert_true("weapon_mastery" in _combatant.equipped_passives,
		"Switching back to fighter should restore weapon_mastery passive")


func test_secondary_job_add_forks_profile() -> void:
	"""When adding secondary for first time, fork instead of reset"""
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		pending("JobSystem not available")
		return

	# Start as fighter with no secondary
	job_system.assign_job(_combatant, "fighter")
	_combatant.secondary_job_id = ""
	_combatant.equipped_weapon = "iron_sword"
	_set_passives(_combatant, ["weapon_mastery"])

	# Save current profile
	var old_key = _combatant.get_profile_key()
	_combatant.save_current_profile()

	# Add secondary job
	job_system.assign_secondary_job(_combatant, "thief")
	var new_key = _combatant.get_profile_key()
	assert_eq(new_key, "fighter:thief")

	# Fork (not reset!) - this is the key behavior
	_combatant.fork_profile(old_key, new_key)
	_combatant.load_profile(new_key)

	# Equipment should be preserved from the fork
	assert_eq(_combatant.equipped_weapon, "iron_sword",
		"Forking on secondary add should preserve equipment")
	assert_true("weapon_mastery" in _combatant.equipped_passives,
		"Forking on secondary add should preserve passives")


func test_secondary_job_remove_restores_primary_only_profile() -> void:
	"""When removing secondary, restore the primary-only profile"""
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		pending("JobSystem not available")
		return

	# Start as fighter, save profile
	job_system.assign_job(_combatant, "fighter")
	_combatant.secondary_job_id = ""
	_combatant.equipped_weapon = "iron_sword"
	_combatant.save_current_profile()

	# Add secondary, change equipment
	job_system.assign_secondary_job(_combatant, "thief")
	_combatant.equipped_weapon = "poison_dagger"
	_combatant.save_current_profile()

	# Remove secondary (back to "fighter:")
	_combatant.save_current_profile()
	_combatant.secondary_job = null
	_combatant.secondary_job_id = ""
	_combatant.load_profile("fighter:")

	assert_eq(_combatant.equipped_weapon, "iron_sword",
		"Removing secondary should restore primary-only profile")


## ---- Serialization ----

func test_job_profiles_included_in_to_dict() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	_combatant.save_current_profile()

	var data = _combatant.to_dict()

	assert_true(data.has("job_profiles"), "to_dict should include job_profiles")
	assert_true(data["job_profiles"].has("fighter:"), "Serialized profiles should include fighter:")


func test_job_profiles_restored_from_dict() -> void:
	# Create a combatant with profiles
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	_combatant.save_current_profile()

	# Serialize
	var data = _combatant.to_dict()

	# Create new combatant and restore
	var new_combatant = CombatantScript.new()
	add_child_autofree(new_combatant)
	new_combatant.from_dict(data)

	assert_true(new_combatant.job_profiles.has("fighter:"),
		"Deserialized combatant should have fighter: profile")
	assert_eq(new_combatant.job_profiles["fighter:"]["weapon"], "iron_sword",
		"Deserialized profile should have correct weapon")


func test_serialization_round_trip_preserves_multiple_profiles() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	_combatant.save_current_profile()

	_combatant.secondary_job_id = "thief"
	_combatant.equipped_weapon = "poison_dagger"
	_set_passives(_combatant, ["steal_boost", "evasion_up"])
	_combatant.save_current_profile()

	# Round-trip
	var data = _combatant.to_dict()
	var restored = CombatantScript.new()
	add_child_autofree(restored)
	restored.from_dict(data)

	assert_eq(restored.job_profiles.size(), 2, "Should have 2 profiles after round-trip")
	assert_true(restored.job_profiles.has("fighter:"), "Should have fighter: profile")
	assert_true(restored.job_profiles.has("fighter:thief"), "Should have fighter:thief profile")
	assert_eq(restored.job_profiles["fighter:"]["weapon"], "iron_sword")
	assert_eq(restored.job_profiles["fighter:thief"]["weapon"], "poison_dagger")


func test_serialization_deep_independence() -> void:
	"""Regression: serialized data must not share references with original"""
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	_combatant.save_current_profile()

	var data = _combatant.to_dict()

	# Modify original after serialization
	_combatant.job_profiles["fighter:"]["weapon"] = "mythril_sword"

	# Serialized data should be unaffected
	assert_eq(data["job_profiles"]["fighter:"]["weapon"], "iron_sword",
		"Serialized data should be independent from original object")


## ---- Edge Cases ----

func test_empty_job_profiles_dict() -> void:
	assert_eq(_combatant.job_profiles.size(), 0, "Fresh combatant should have empty profiles dict")


func test_profile_key_with_special_characters_in_job_id() -> void:
	_combatant.job = {"id": "time_mage", "name": "Time Mage"}
	_combatant.secondary_job_id = "black_mage"
	var key = _combatant.get_profile_key()
	assert_eq(key, "time_mage:black_mage", "Underscores in job IDs should work")


func test_all_job_combos_produce_unique_keys() -> void:
	"""Verify that primary:secondary keys are unique for different combos"""
	var combos = [
		["fighter", ""],
		["fighter", "thief"],
		["thief", "fighter"],  # Reversed should be different
		["white_mage", "black_mage"],
		["black_mage", "white_mage"],
	]

	var keys = {}
	for combo in combos:
		_combatant.job = {"id": combo[0], "name": combo[0]}
		_combatant.secondary_job_id = combo[1]
		var key = _combatant.get_profile_key()
		assert_false(keys.has(key), "Key '%s' should be unique (combo: %s:%s)" % [key, combo[0], combo[1]])
		keys[key] = true


func test_save_and_load_profile_with_no_equipment() -> void:
	_combatant.job = {"id": "fighter", "name": "Fighter"}
	_combatant.secondary_job_id = ""
	_combatant.equipped_weapon = ""
	_combatant.equipped_armor = ""
	_combatant.equipped_accessory = ""
	_set_passives(_combatant, [])
	_combatant.save_current_profile()

	_combatant.equipped_weapon = "iron_sword"
	_combatant.load_profile("fighter:")

	assert_eq(_combatant.equipped_weapon, "", "Should restore empty weapon slot")
