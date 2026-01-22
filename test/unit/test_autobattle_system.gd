extends GutTest

## Regression tests for AutobattleSystem
## Tests autobattle profile loading, script execution, and rule evaluation

var _autobattle: Node


func before_all() -> void:
	# Get reference to AutobattleSystem singleton
	_autobattle = get_tree().root.get_node_or_null("AutobattleSystem")


func test_autobattle_system_exists() -> void:
	assert_not_null(_autobattle, "AutobattleSystem singleton should exist")


func test_get_character_script_returns_dict() -> void:
	# Regression test: execute_grid_autobattle was using character_scripts
	# instead of get_character_script(), causing empty scripts to be returned
	var script = _autobattle.get_character_script("hero")
	assert_typeof(script, TYPE_DICTIONARY, "get_character_script should return Dictionary")


func test_character_script_has_rules() -> void:
	# Ensure character scripts have the expected structure
	var script = _autobattle.get_character_script("hero")
	assert_true(script.has("rules"), "Character script should have 'rules' key")
	assert_typeof(script["rules"], TYPE_ARRAY, "Rules should be an Array")


func test_default_script_has_valid_conditions() -> void:
	# Test that default scripts have valid condition types
	var script = _autobattle.create_default_character_script("hero")
	assert_true(script.has("rules"), "Default script should have rules")

	for rule in script["rules"]:
		if rule.has("conditions"):
			for condition in rule["conditions"]:
				assert_true(condition.has("type"), "Condition should have 'type'")
				var cond_type = condition["type"]
				var valid_types = ["hp_percent", "mp_percent", "ap", "has_status",
								   "enemy_hp_percent", "ally_hp_percent", "turn",
								   "enemy_count", "ally_count", "item_count", "always"]
				assert_true(cond_type in valid_types, "Condition type '%s' should be valid" % cond_type)


func test_autobattle_enabled_toggle() -> void:
	# Test enable/disable toggle
	_autobattle.set_autobattle_enabled("test_char", true)
	assert_true(_autobattle.is_autobattle_enabled("test_char"), "Autobattle should be enabled")

	_autobattle.set_autobattle_enabled("test_char", false)
	assert_false(_autobattle.is_autobattle_enabled("test_char"), "Autobattle should be disabled")


func test_toggle_autobattle_returns_new_state() -> void:
	# Test toggle function returns correct state
	_autobattle.set_autobattle_enabled("test_toggle", false)
	var new_state = _autobattle.toggle_autobattle("test_toggle")
	assert_true(new_state, "Toggle from false should return true")

	new_state = _autobattle.toggle_autobattle("test_toggle")
	assert_false(new_state, "Toggle from true should return false")


func test_profile_management() -> void:
	# Test profile creation and retrieval
	var profiles = _autobattle.get_character_profiles("hero")
	assert_typeof(profiles, TYPE_ARRAY, "get_character_profiles should return Array")
	assert_gt(profiles.size(), 0, "Should have at least one profile")


func test_vex_default_script_has_abilities() -> void:
	# Regression test: Vex should have ability actions in default script
	var script = _autobattle.create_default_character_script("vex")
	var has_ability_action = false

	for rule in script["rules"]:
		if rule.has("actions"):
			for action in rule["actions"]:
				if action.get("type") == "ability":
					has_ability_action = true
					break

	assert_true(has_ability_action, "Vex default script should have ability actions (fire/thunder)")


func test_mira_default_script_has_healing() -> void:
	# Regression test: Mira (white mage) should have healing in default script
	var script = _autobattle.create_default_character_script("mira")
	var has_cure = false

	for rule in script["rules"]:
		if rule.has("actions"):
			for action in rule["actions"]:
				if action.get("type") == "ability" and action.get("id") == "cure":
					has_cure = true
					break

	assert_true(has_cure, "Mira default script should have Cure ability")
