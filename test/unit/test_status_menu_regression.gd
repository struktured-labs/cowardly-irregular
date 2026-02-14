extends GutTest

## Regression tests for StatusMenu
## Prevents crashes from invalid property access on Combatant
## Critical: character.level, character.exp, etc don't exist on Combatant

const CombatantScript = preload("res://src/battle/Combatant.gd")


## ---- Property Access Safety ----
## These tests verify that every property StatusMenu accesses actually exists on Combatant

func test_combatant_has_job_level_not_level() -> void:
	"""Regression: StatusMenu crashed using character.level (doesn't exist)"""
	var c = CombatantScript.new()
	add_child_autofree(c)

	# job_level must exist
	assert_true("job_level" in c, "Combatant must have job_level property")
	assert_eq(c.job_level, 1, "Default job_level should be 1")

	# 'level' must NOT exist (caused crash)
	assert_false("level" in c, "Combatant must NOT have 'level' property (use job_level)")


func test_combatant_has_job_exp_not_exp() -> void:
	"""Regression: StatusMenu crashed using character.exp (doesn't exist)"""
	var c = CombatantScript.new()
	add_child_autofree(c)

	assert_true("job_exp" in c, "Combatant must have job_exp property")
	assert_eq(c.job_exp, 0, "Default job_exp should be 0")

	# 'exp' must NOT exist
	assert_false("exp" in c, "Combatant must NOT have 'exp' property (use job_exp)")


func test_combatant_has_all_status_menu_properties() -> void:
	"""Verify every property accessed by StatusMenu._build_ui exists on Combatant"""
	var c = CombatantScript.new()
	add_child_autofree(c)

	# Header panel properties
	assert_true("combatant_name" in c, "Must have combatant_name")
	assert_true("job" in c, "Must have job")
	assert_true("job_level" in c, "Must have job_level")
	assert_true("current_hp" in c, "Must have current_hp")
	assert_true("max_hp" in c, "Must have max_hp")
	assert_true("current_mp" in c, "Must have current_mp")
	assert_true("max_mp" in c, "Must have max_mp")
	assert_true("job_exp" in c, "Must have job_exp")

	# Stats panel properties
	assert_true("attack" in c, "Must have attack")
	assert_true("defense" in c, "Must have defense")
	assert_true("magic" in c, "Must have magic")
	assert_true("speed" in c, "Must have speed")
	assert_true("base_attack" in c, "Must have base_attack")
	assert_true("base_defense" in c, "Must have base_defense")
	assert_true("base_magic" in c, "Must have base_magic")
	assert_true("base_speed" in c, "Must have base_speed")
	assert_true("base_max_hp" in c, "Must have base_max_hp")
	assert_true("base_max_mp" in c, "Must have base_max_mp")

	# Equipment panel properties
	assert_true("equipped_weapon" in c, "Must have equipped_weapon")
	assert_true("equipped_armor" in c, "Must have equipped_armor")
	assert_true("equipped_accessory" in c, "Must have equipped_accessory")

	# Passives panel properties
	assert_true("equipped_passives" in c, "Must have equipped_passives")
	assert_true("max_passive_slots" in c, "Must have max_passive_slots")

	# Status effects panel
	assert_true("status_effects" in c, "Must have status_effects")

	# Injuries panel
	assert_true("permanent_injuries" in c, "Must have permanent_injuries")


func test_combatant_job_safe_access_pattern() -> void:
	"""StatusMenu uses 'character.job.get(...)' - verify null job doesn't crash"""
	var c = CombatantScript.new()
	add_child_autofree(c)

	# Job is null by default
	assert_null(c.job, "Default job should be null")

	# StatusMenu pattern: character.job.get("name", "Fighter") if character.job else "Fighter"
	var job_name = c.job.get("name", "Fighter") if c.job else "Fighter"
	assert_eq(job_name, "Fighter", "Null job should default to Fighter")


func test_combatant_hp_percentage_no_division_by_zero() -> void:
	"""StatusMenu calculates hp_pct = current_hp / max(1, max_hp)"""
	var c = CombatantScript.new()
	add_child_autofree(c)

	# Edge case: max_hp = 0
	c.max_hp = 0
	c.current_hp = 0
	var hp_pct = float(c.current_hp) / max(1, c.max_hp)
	assert_eq(hp_pct, 0.0, "HP pct should be 0 when max_hp is 0 (no division by zero)")


func test_combatant_mp_percentage_no_division_by_zero() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)

	c.max_mp = 0
	c.current_mp = 0
	var mp_pct = float(c.current_mp) / max(1, c.max_mp)
	assert_eq(mp_pct, 0.0, "MP pct should be 0 when max_mp is 0")


func test_equipped_passives_is_iterable_when_empty() -> void:
	"""StatusMenu iterates equipped_passives - must work when empty"""
	var c = CombatantScript.new()
	add_child_autofree(c)

	assert_eq(c.equipped_passives.size(), 0, "Default passives should be empty")

	# Simulate what StatusMenu does
	var count = 0
	for passive_id in c.equipped_passives:
		count += 1
	assert_eq(count, 0, "Iterating empty passives should work")


func test_status_effects_is_iterable_when_empty() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)

	assert_eq(c.status_effects.size(), 0, "Default status_effects should be empty")

	var count = 0
	for status in c.status_effects:
		count += 1
	assert_eq(count, 0, "Iterating empty status_effects should work")


func test_permanent_injuries_is_iterable_when_empty() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)

	assert_eq(c.permanent_injuries.size(), 0, "Default injuries should be empty")


func test_permanent_injuries_has_expected_keys() -> void:
	"""StatusMenu accesses injury.get('stat') and injury.get('penalty')"""
	var c = CombatantScript.new()
	add_child_autofree(c)

	# Add an injury
	c.apply_permanent_injury({"stat": "attack", "penalty": 2})

	assert_eq(c.permanent_injuries.size(), 1, "Should have 1 injury")
	var injury = c.permanent_injuries[0]
	assert_true(injury.has("stat"), "Injury should have 'stat' key")
	assert_true(injury.has("penalty"), "Injury should have 'penalty' key")


func test_equipped_weapon_is_string() -> void:
	"""StatusMenu calls character.equipped_weapon.is_empty()"""
	var c = CombatantScript.new()
	add_child_autofree(c)

	assert_typeof(c.equipped_weapon, TYPE_STRING, "equipped_weapon must be String")
	assert_true(c.equipped_weapon.is_empty(), "Default equipped_weapon should be empty string")


func test_equipped_armor_is_string() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)

	assert_typeof(c.equipped_armor, TYPE_STRING, "equipped_armor must be String")


func test_equipped_accessory_is_string() -> void:
	var c = CombatantScript.new()
	add_child_autofree(c)

	assert_typeof(c.equipped_accessory, TYPE_STRING, "equipped_accessory must be String")


## ---- StatusMenu Source Code Checks ----

func test_status_menu_uses_job_level_not_level() -> void:
	"""Regression: verify source code does not reference character.level"""
	var content = FileAccess.get_file_as_string("res://src/ui/StatusMenu.gd")

	# Should use job_level
	assert_true(content.contains("character.job_level"),
		"StatusMenu should use character.job_level")

	# Should NOT use plain .level (except in property names like "job_level")
	var lines = content.split("\n")
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		if "character.level" in line and "job_level" not in line:
			assert_true(false,
				"StatusMenu line %d uses character.level instead of character.job_level: %s" % [i + 1, line])


func test_status_menu_uses_job_exp_not_exp() -> void:
	"""Regression: verify source code does not reference character.exp directly"""
	var content = FileAccess.get_file_as_string("res://src/ui/StatusMenu.gd")

	assert_true(content.contains("character.job_exp"),
		"StatusMenu should use character.job_exp")

	var lines = content.split("\n")
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		# Check for character.exp but not character.job_exp
		if "character.exp" in line and "character.job_exp" not in line:
			assert_true(false,
				"StatusMenu line %d uses character.exp instead of character.job_exp: %s" % [i + 1, line])


func test_save_system_uses_job_level_not_level() -> void:
	"""Regression: SaveSystem _get_party_summary used member.level"""
	var content = FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")

	var lines = content.split("\n")
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		# Check for member.level that's NOT member.job_level
		if "member.level" in line and "job_level" not in line:
			assert_true(false,
				"SaveSystem line %d uses member.level instead of member.job_level: %s" % [i + 1, line])


## ---- StatusMenu Script Check ----

func test_status_menu_script_loads() -> void:
	var script = load("res://src/ui/StatusMenu.gd")
	assert_not_null(script, "StatusMenu.gd should load without errors")


func test_status_menu_has_closed_signal() -> void:
	var StatusMenuScript = load("res://src/ui/StatusMenu.gd")
	var menu = StatusMenuScript.new()
	assert_has_signal(menu, "closed", "StatusMenu should have closed signal")
	menu.queue_free()


func test_status_menu_has_setup_method() -> void:
	var StatusMenuScript = load("res://src/ui/StatusMenu.gd")
	var menu = StatusMenuScript.new()
	assert_true(menu.has_method("setup"), "StatusMenu should have setup method")
	menu.queue_free()
