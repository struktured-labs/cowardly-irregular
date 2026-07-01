extends GutTest

## AutobattleSystem.install_composition_as_new_profile: append a fresh
## per-character profile from a RuleComposer composition dict, never
## overwriting existing profiles.

var autobattle
const _TEST_IDS := ["test_pc", "test_pc_2", "test_pc_3"]


func before_each() -> void:
	autobattle = get_node_or_null("/root/AutobattleSystem")
	for cid in _TEST_IDS:
		if autobattle.character_profiles.has(cid):
			autobattle.character_profiles.erase(cid)
	autobattle._save_character_profiles()


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


func test_install_normalizes_empty_name() -> void:
	var comp := {"name": "", "description": "", "rules": []}
	var idx: int = autobattle.install_composition_as_new_profile("test_pc", comp)
	assert_gt(idx, -1)
	var profile: Dictionary = autobattle.character_profiles["test_pc"]["profiles"][idx]
	var stored_name = profile.get("script", {}).get("name", "")
	assert_true(str(stored_name).begins_with("Composed "),
				"empty composition.name must normalize to 'Composed N'; got '%s'" % stored_name)


func test_install_survives_non_string_name() -> void:
	var comp := {"name": null, "description": "", "rules": []}
	var idx: int = autobattle.install_composition_as_new_profile("test_pc", comp)
	assert_gt(idx, -1, "non-string name (null) must not crash the helper")
	var profile: Dictionary = autobattle.character_profiles["test_pc"]["profiles"][idx]
	var stored_name = profile.get("script", {}).get("name", "")
	assert_true(str(stored_name).begins_with("Composed "),
				"null composition.name must fall back to Composed N")


func test_install_survives_non_array_rules() -> void:
	var comp := {"name": "bad_rules", "description": "", "rules": null}
	var idx: int = autobattle.install_composition_as_new_profile("test_pc", comp)
	assert_gt(idx, -1, "non-array rules (null) must not crash the helper")
	var profile: Dictionary = autobattle.character_profiles["test_pc"]["profiles"][idx]
	var stored: Variant = profile.get("script", {}).get("rules", [])
	assert_true(typeof(stored) == TYPE_ARRAY, "stored rules must be an Array; got typeof=%s" % typeof(stored))


func after_each() -> void:
	for cid in _TEST_IDS:
		if autobattle.character_profiles.has(cid):
			autobattle.character_profiles.erase(cid)
	autobattle._save_character_profiles()
