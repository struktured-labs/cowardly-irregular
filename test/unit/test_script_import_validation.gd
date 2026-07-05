extends GutTest

## Feature 2026-07-05: imported/shared autobattle scripts (ScriptShareManager)
## were applied WITHOUT validating their rules — a hand-edited, malformed, or
## newer-version share could set a script carrying bad condition/target types
## that silently misbehaves at runtime. apply now runs each rule through the
## engine's validate_rule and REFUSES a bad single-script import (skips bad
## entries in a bundle). Sharing scripts between players is a stated design
## vision, so importing untrusted data safely matters.

const SSM := preload("res://src/autobattle/ScriptShareManager.gd")


func _valid_script() -> Dictionary:
	return {"rules": [
		{"conditions": [{"type": "enemy_has_status", "status": "stun"}],
		 "actions": [{"type": "ability", "id": "fire", "target": "weakest_to_ability"}],
		 "enabled": true},
	]}


func _invalid_script() -> Dictionary:
	# bogus target type — validate_rule rejects it (not in TARGET_TYPES)
	return {"rules": [
		{"conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "not_a_real_target"}],
		 "enabled": true},
	]}


func test_valid_script_validates_clean() -> void:
	assert_eq(SSM.validate_imported_script(_valid_script()).size(), 0,
		"a well-formed shared script must validate cleanly")


func test_invalid_target_is_caught() -> void:
	assert_gt(SSM.validate_imported_script(_invalid_script()).size(), 0,
		"an invalid target type must produce a validation error")


func test_missing_rules_array_is_error() -> void:
	assert_gt(SSM.validate_imported_script({}).size(), 0,
		"a script with no rules array can't be a valid import")


func test_non_dict_rule_is_error() -> void:
	assert_gt(SSM.validate_imported_script({"rules": ["oops"]}).size(), 0,
		"a rule that isn't a dictionary is invalid")


func test_apply_rejects_invalid_script() -> void:
	# Reject path returns BEFORE set_character_script — no state mutation.
	var data := {"type": "autobattle_script", "script": _invalid_script()}
	assert_false(SSM.apply_character_script("test_reject_char", data),
		"apply must refuse an import whose rules don't validate")


func test_bundle_path_validates_in_source() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/autobattle/ScriptShareManager.gd")
	var idx: int = src.find("func apply_script_bundle")
	var body: String = src.substr(idx, src.find("\nstatic func", idx + 1) - idx if src.find("\nstatic func", idx + 1) > -1 else 400)
	assert_string_contains(body, "validate_imported_script",
		"the bundle apply path must also validate each script before applying")
