extends GutTest

## _create_default_autogrind_profiles() is reachable ONLY on first run, so a clobbered
## profiles.json is permanent. 2026-08-06: slot 0 became `always -> stop_grinding`.
## get_autogrind_rules reads the ACTIVE profile only, so the damage is scoped to `active`, not
## to all three — switching active is a recovery. Reset restores the shipped ruleset instead.

var _system


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true


func _clobber() -> void:
	## The exact shape found in struktured's live user://autogrind/profiles.json.
	_system.autogrind_profiles = {
		"active": 0,
		"profiles": [
			{"name": "Standard Grind", "rules": [{
				"conditions": [{"type": "always"}],
				"actions": [{"type": "stop_grinding"}],
				"enabled": true
			}]},
			{"name": "Safe Grind", "rules": []},
			{"name": "Aggressive Grind", "rules": []}
		]
	}


func _first_rules() -> Array:
	var p: Array = _system.autogrind_profiles.get("profiles", [])
	return [] if p.is_empty() else (p[0] as Dictionary).get("rules", [])


func _halts_immediately(rules: Array) -> bool:
	for r in rules:
		var rd: Dictionary = r
		var conds: Array = rd.get("conditions", [])
		var acts: Array = rd.get("actions", [])
		var uncond := conds.size() == 1 and str((conds[0] as Dictionary).get("type", "")) == "always"
		var stops := acts.any(func(a): return str((a as Dictionary).get("type", "")) == "stop_grinding")
		if uncond and stops:
			return true
	return false


func test_the_clobbered_shape_really_is_broken() -> void:
	# ARM+. Without this the reset assertions pass on any starting state.
	_clobber()
	assert_eq(_first_rules().size(), 1, "control: the clobbered profile has exactly one rule")
	assert_true(_halts_immediately(_first_rules()),
		"control: the clobbered profile must halt on its first evaluation, else this file tests nothing")


func test_reset_restores_the_shipped_first_profile() -> void:
	_clobber()
	var info: Dictionary = _system.reset_autogrind_profiles_to_defaults()
	assert_gt(int(info.get("rules_in_first", 0)), 1,
		"reset must restore the multi-rule shipped ruleset, not another single-rule stub")
	assert_false(_halts_immediately(_first_rules()),
		"after reset the active profile must not halt unconditionally on its first evaluation")


func test_reset_restores_the_full_profile_set_and_active_index() -> void:
	_clobber()
	_system.autogrind_profiles["active"] = 2
	var info: Dictionary = _system.reset_autogrind_profiles_to_defaults()
	assert_eq(int(info.get("profiles_after", 0)), 3, "the shipped set is three profiles")
	assert_eq(int(info.get("active_after", -1)), 0, "reset returns the player to the first profile")


func test_reset_reports_what_it_replaced() -> void:
	# The caller needs to tell the player what happened; a silent repair is the defect's shape.
	_clobber()
	var info: Dictionary = _system.reset_autogrind_profiles_to_defaults()
	assert_eq(int(info.get("profiles_before", -1)), 3, "must report the pre-reset profile count")
	assert_eq(int(info.get("active_before", -1)), 0, "must report the pre-reset active index")
