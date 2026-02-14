extends GutTest

## Tests for Combatant serialization (to_dict / from_dict)
## Ensures save/load round-trips preserve all state correctly

const CombatantScript = preload("res://src/battle/Combatant.gd")


## ---- Basic Round-Trip ----

func test_basic_round_trip() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)

	c.combatant_name = "Hero"
	c.max_hp = 150
	c.current_hp = 80
	c.max_mp = 60
	c.current_mp = 30
	c.attack = 20
	c.defense = 15
	c.magic = 12
	c.speed = 14

	var data = c.to_dict()
	var restored = CombatantScript.new()
	add_child_autofree(restored)
	restored.from_dict(data)

	assert_eq(restored.combatant_name, "Hero", "Name round-trip")
	assert_eq(restored.max_hp, 150, "max_hp round-trip")
	assert_eq(restored.current_hp, 80, "current_hp round-trip")
	assert_eq(restored.max_mp, 60, "max_mp round-trip")
	assert_eq(restored.current_mp, 30, "current_mp round-trip")
	assert_eq(restored.attack, 20, "attack round-trip")
	assert_eq(restored.defense, 15, "defense round-trip")
	assert_eq(restored.magic, 12, "magic round-trip")
	assert_eq(restored.speed, 14, "speed round-trip")


func test_round_trip_with_status_effects() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.add_status("poison")
	c.add_status("slow")

	var data = c.to_dict()
	var restored = CombatantScript.new()
	add_child_autofree(restored)
	restored.from_dict(data)

	assert_eq(restored.status_effects.size(), 2, "Should restore 2 status effects")
	assert_true("poison" in restored.status_effects, "Should have poison")
	assert_true("slow" in restored.status_effects, "Should have slow")


func test_round_trip_with_permanent_injuries() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.apply_permanent_injury({"stat": "attack", "penalty": 3})

	var data = c.to_dict()
	var restored = CombatantScript.new()
	add_child_autofree(restored)
	restored.from_dict(data)

	assert_eq(restored.permanent_injuries.size(), 1, "Should restore 1 injury")
	assert_eq(restored.permanent_injuries[0]["stat"], "attack")
	assert_eq(restored.permanent_injuries[0]["penalty"], 3)


func test_round_trip_with_learned_abilities() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.learn_ability("fire")
	c.learn_ability("cure")
	c.learn_ability("thunder")

	var data = c.to_dict()
	var restored = CombatantScript.new()
	add_child_autofree(restored)
	restored.from_dict(data)

	assert_eq(restored.learned_abilities.size(), 3, "Should restore 3 learned abilities")
	assert_true("fire" in restored.learned_abilities, "Should have fire")
	assert_true("cure" in restored.learned_abilities, "Should have cure")
	assert_true("thunder" in restored.learned_abilities, "Should have thunder")


func test_round_trip_with_is_alive_false() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.is_alive = false

	var data = c.to_dict()
	var restored = CombatantScript.new()
	add_child_autofree(restored)
	restored.from_dict(data)

	assert_false(restored.is_alive, "Should restore is_alive=false")


func test_round_trip_with_ap() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.current_ap = 3

	var data = c.to_dict()
	var restored = CombatantScript.new()
	add_child_autofree(restored)
	restored.from_dict(data)

	assert_eq(restored.current_ap, 3, "Should restore current_ap")


func test_round_trip_preserves_job_profiles() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.job = {"id": "fighter", "name": "Fighter"}
	c.secondary_job_id = ""
	c.equipped_weapon = "iron_sword"
	c.equipped_armor = "leather_armor"
	c.equipped_accessory = ""
	c.equipped_passives.clear()
	c.equipped_passives.append("weapon_mastery")
	c.save_current_profile()

	c.secondary_job_id = "thief"
	c.equipped_weapon = "iron_dagger"
	c.equipped_passives.clear()
	c.equipped_passives.append("steal_boost")
	c.save_current_profile()

	var data = c.to_dict()
	var restored = CombatantScript.new()
	add_child_autofree(restored)
	restored.from_dict(data)

	assert_eq(restored.job_profiles.size(), 2, "Should restore 2 profiles")
	assert_true(restored.job_profiles.has("fighter:"), "Should have fighter: profile")
	assert_true(restored.job_profiles.has("fighter:thief"), "Should have fighter:thief profile")
	assert_eq(restored.job_profiles["fighter:"]["weapon"], "iron_sword")
	assert_eq(restored.job_profiles["fighter:thief"]["weapon"], "iron_dagger")


## ---- Edge Cases ----

func test_from_dict_with_empty_dict() -> void:
	"""Should not crash when given empty dict"""
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.combatant_name = "Original"

	c.from_dict({})

	# Name should be unchanged (from_dict checks has() before overwriting)
	assert_eq(c.combatant_name, "Original", "Empty dict should not modify existing state")


func test_from_dict_with_partial_data() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.combatant_name = "Original"
	c.max_hp = 100

	c.from_dict({"name": "New Name"})

	assert_eq(c.combatant_name, "New Name", "Partial data should update provided fields")
	assert_eq(c.max_hp, 100, "Missing fields should remain unchanged")


func test_to_dict_returns_independent_copy() -> void:
	"""Modifying returned dict should not affect combatant"""
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.combatant_name = "Hero"
	c.add_status("poison")

	var data = c.to_dict()
	data["name"] = "Modified"
	data["status_effects"].append("sleep")

	assert_eq(c.combatant_name, "Hero", "Original name should be unchanged")
	assert_eq(c.status_effects.size(), 1, "Original status_effects should be unchanged")


func test_round_trip_with_zero_stats() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.max_hp = 0
	c.current_hp = 0
	c.max_mp = 0
	c.current_mp = 0
	c.attack = 0
	c.defense = 0

	var data = c.to_dict()
	var restored = CombatantScript.new()
	add_child_autofree(restored)
	restored.from_dict(data)

	assert_eq(restored.max_hp, 0, "Zero max_hp round-trip")
	assert_eq(restored.attack, 0, "Zero attack round-trip")


func test_round_trip_with_negative_ap() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.current_ap = -3  # In AP debt

	var data = c.to_dict()
	var restored = CombatantScript.new()
	add_child_autofree(restored)
	restored.from_dict(data)

	assert_eq(restored.current_ap, -3, "Negative AP should survive round-trip")


## ---- to_dict Contains All Required Keys ----

func test_to_dict_has_all_expected_keys() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)

	var data = c.to_dict()

	var required_keys = [
		"name", "max_hp", "max_mp", "current_hp", "current_mp",
		"current_ap", "attack", "defense", "magic", "speed",
		"status_effects", "permanent_injuries", "is_alive",
		"learned_abilities", "job_profiles"
	]

	for key in required_keys:
		assert_true(data.has(key),
			"to_dict() must include key: %s" % key)


func test_to_dict_types() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)
	var data = c.to_dict()

	assert_typeof(data["name"], TYPE_STRING, "name should be String")
	assert_typeof(data["max_hp"], TYPE_INT, "max_hp should be int")
	assert_typeof(data["is_alive"], TYPE_BOOL, "is_alive should be bool")
	assert_typeof(data["status_effects"], TYPE_ARRAY, "status_effects should be Array")
	assert_typeof(data["permanent_injuries"], TYPE_ARRAY, "permanent_injuries should be Array")
	assert_typeof(data["learned_abilities"], TYPE_ARRAY, "learned_abilities should be Array")
	assert_typeof(data["job_profiles"], TYPE_DICTIONARY, "job_profiles should be Dictionary")
