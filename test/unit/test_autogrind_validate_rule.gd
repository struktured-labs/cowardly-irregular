extends GutTest

var autogrind_system

func before_each() -> void:
	autogrind_system = get_node_or_null("/root/AutogrindSystem")
	assert_not_null(autogrind_system, "AutogrindSystem autoload not available")

func test_valid_autogrind_rule() -> void:
	var rule := {
		"conditions": [{"type": "party_hp_min", "op": "<", "value": 30}],
		"actions": [{"type": "heal_party"}],
		"enabled": true,
	}
	var errors: Array = autogrind_system.validate_rule(rule)
	assert_eq(errors.size(), 0, "valid rule must produce zero errors; got: %s" % [errors])

func test_missing_conditions() -> void:
	var rule := {"actions": [{"type": "stop_grinding"}]}
	var errors: Array = autogrind_system.validate_rule(rule)
	assert_gt(errors.size(), 0)
	assert_true("conditions" in "|".join(errors))

func test_unknown_autogrind_condition() -> void:
	var rule := {
		"conditions": [{"type": "phase_of_moon"}],
		"actions": [{"type": "stop_grinding"}],
	}
	var errors: Array = autogrind_system.validate_rule(rule)
	assert_gt(errors.size(), 0)
	assert_true("phase_of_moon" in "|".join(errors))

func test_switch_profile_missing_character_id() -> void:
	var rule := {
		"conditions": [{"type": "always"}],
		"actions": [{"type": "switch_profile", "profile_index": 1}],
	}
	var errors: Array = autogrind_system.validate_rule(rule)
	assert_gt(errors.size(), 0)
	assert_true("character_id" in "|".join(errors))

func test_switch_profile_missing_profile_index() -> void:
	var rule := {
		"conditions": [{"type": "always"}],
		"actions": [{"type": "switch_profile", "character_id": "cleric"}],
	}
	var errors: Array = autogrind_system.validate_rule(rule)
	assert_gt(errors.size(), 0)
	assert_true("profile_index" in "|".join(errors))

func test_unknown_action_type() -> void:
	var rule := {
		"conditions": [{"type": "always"}],
		"actions": [{"type": "explode_kingdom"}],
	}
	var errors: Array = autogrind_system.validate_rule(rule)
	assert_gt(errors.size(), 0)
	assert_true("explode_kingdom" in "|".join(errors))

func test_previously_missing_condition_types_now_accepted() -> void:
	var previously_missing := ["party_mp_avg", "battles_done", "efficiency", "member_injured",
		"win_streak", "time_elapsed", "ability_learned", "reached_level", "rare_item_found"]
	for ctype in previously_missing:
		var rule := {"conditions": [{"type": ctype}], "actions": [{"type": "stop_grinding"}]}
		var errors: Array = autogrind_system.validate_rule(rule)
		assert_eq(errors.size(), 0, "condition type '%s' should be accepted; got: %s" % [ctype, errors])

func test_previously_missing_action_types_now_accepted() -> void:
	var previously_missing := ["restore_mp", "flee_battle"]
	for atype in previously_missing:
		var rule := {"conditions": [{"type": "always"}], "actions": [{"type": atype}]}
		var errors: Array = autogrind_system.validate_rule(rule)
		assert_eq(errors.size(), 0, "action type '%s' should be accepted; got: %s" % [atype, errors])

func test_unknown_type_still_rejected_after_grammar_expansion() -> void:
	var rule := {
		"conditions": [{"type": "party_hp_max"}],
		"actions": [{"type": "resurrect_all"}],
	}
	var errors: Array = autogrind_system.validate_rule(rule)
	assert_gt(errors.size(), 0)
	assert_true("party_hp_max" in "|".join(errors))
	assert_true("resurrect_all" in "|".join(errors))
