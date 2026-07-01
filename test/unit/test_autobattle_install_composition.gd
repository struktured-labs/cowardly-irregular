extends GutTest

## AutobattleSystem.install_composition_as_new_profile: append a fresh
## per-character profile from a RuleComposer composition dict, never
## overwriting existing profiles.

var autobattle


func before_each() -> void:
	autobattle = get_node_or_null("/root/AutobattleSystem")


func test_install_returns_new_profile_index() -> void:
	var comp := {
		"name": "test_profile",
		"description": "Test.",
		"rules": [
			{"conditions": [{"type": "always"}],
			 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
			 "enabled": true},
		],
	}
	var idx: int = autobattle.install_composition_as_new_profile("test_pc", comp)
	assert_gt(idx, -1, "install must return a valid new profile index")


func test_install_does_not_overwrite_existing_profile() -> void:
	var comp_a := {"name": "profile_a", "description": "", "rules": []}
	var comp_b := {"name": "profile_b", "description": "", "rules": []}
	var idx_a: int = autobattle.install_composition_as_new_profile("test_pc_2", comp_a)
	var idx_b: int = autobattle.install_composition_as_new_profile("test_pc_2", comp_b)
	assert_ne(idx_a, idx_b, "consecutive installs must NOT reuse the same slot")


func test_install_emits_character_script_changed() -> void:
	watch_signals(autobattle)
	var comp := {"name": "signal_check", "description": "", "rules": []}
	autobattle.install_composition_as_new_profile("test_pc_3", comp)
	assert_signal_emitted(autobattle, "character_script_changed")
