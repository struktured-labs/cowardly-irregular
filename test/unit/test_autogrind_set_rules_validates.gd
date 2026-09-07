extends GutTest

## Regression coverage: set_autogrind_rules validates at the CHOKE POINT.
## 9935f728 closed the ScriptShareManager clipboard-import gap per-caller by
## pre-validating. Audit (2026-07-16) found 2 remaining bypass paths:
## RuleComposerOverlay (LLM Rule Composer output → set_autogrind_rules @ L172,L197)
## and AutogrindRuleTemplates.install_as_new_profile → set_autogrind_rules @ L74.
## LLM output is untrusted-source-class; templates come from shipped JSON but a
## rebase/typo could ship invalid content. Defense-in-depth: validate in
## set_autogrind_rules itself so every writer benefits without remembering.

var _system: Node


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true


func _valid_rule() -> Dictionary:
	return {
		"conditions": [{"type": "party_hp_avg", "op": "<", "value": 30}],
		"actions": [{"type": "stop_grinding"}],
		"enabled": true,
	}


func _snapshot_rules() -> Array:
	return _system.get_autogrind_rules().duplicate(true)


func test_valid_rules_apply_unchanged() -> void:
	# Contract preserved: the fix must not break the well-formed common path.
	var good := [_valid_rule()]
	_system.set_autogrind_rules(good)
	var current: Array = _system.get_autogrind_rules()
	assert_eq(current.size(), 1, "valid rule set must apply")
	assert_eq(current[0]["actions"][0]["type"], "stop_grinding", "structure preserved")


func test_bad_condition_type_rejected_no_mutation() -> void:
	# LLM-composer-style output that happens to invent a condition type.
	var pre := _snapshot_rules()
	var bad := [{
		"conditions": [{"type": "party_snake_case_typo", "op": "<", "value": 30}],
		"actions": [{"type": "stop_grinding"}],
	}]
	_system.set_autogrind_rules(bad)
	var post := _snapshot_rules()
	assert_eq(post, pre, "bad condition type must be rejected with ZERO mutation to existing rules")


func test_bad_action_type_rejected_no_mutation() -> void:
	var pre := _snapshot_rules()
	var bad := [{
		"conditions": [{"type": "always"}],
		"actions": [{"type": "eject_from_universe"}],
	}]
	_system.set_autogrind_rules(bad)
	var post := _snapshot_rules()
	assert_eq(post, pre, "bad action type must be rejected with ZERO mutation")


func test_missing_conditions_key_rejected() -> void:
	var pre := _snapshot_rules()
	var bad := [{"actions": [{"type": "stop_grinding"}]}]
	_system.set_autogrind_rules(bad)
	var post := _snapshot_rules()
	assert_eq(post, pre, "rule missing 'conditions' key must be rejected")


func test_missing_actions_key_rejected() -> void:
	var pre := _snapshot_rules()
	var bad := [{"conditions": [{"type": "always"}]}]
	_system.set_autogrind_rules(bad)
	var post := _snapshot_rules()
	assert_eq(post, pre, "rule missing 'actions' key must be rejected")


func test_non_dict_rule_rejected() -> void:
	var pre := _snapshot_rules()
	var bad: Array = ["this is not a dict"]
	_system.set_autogrind_rules(bad)
	var post := _snapshot_rules()
	assert_eq(post, pre, "non-dict rule entry must be rejected without crashing")


func test_partial_reject_all_or_nothing() -> void:
	# Contract: even ONE bad rule rejects the ENTIRE set. Otherwise partial mutation
	# would leave rules in a state neither the caller nor the user requested.
	var mixed := [_valid_rule(), {
		"conditions": [{"type": "banana_republic", "op": "<", "value": 30}],
		"actions": [{"type": "stop_grinding"}],
	}]
	var pre := _snapshot_rules()
	_system.set_autogrind_rules(mixed)
	var post := _snapshot_rules()
	assert_eq(post, pre, "partial invalid input must reject the whole set — no partial mutation")


func test_empty_array_applies_cleanly() -> void:
	# Empty rules is legal (means "no autogrind rules active") and must not error.
	_system.set_autogrind_rules([])
	assert_eq(_system.get_autogrind_rules().size(), 0, "empty rules set must apply — legal state")


func test_signal_fires_only_on_successful_apply() -> void:
	# autogrind_rules_changed subscribers (editors, UI) should not react to REJECTED
	# writes — otherwise a rejected LLM composition still triggers a spurious refresh.
	var fired := [false]
	_system.autogrind_rules_changed.connect(func(): fired[0] = true)
	_system.set_autogrind_rules([{"conditions": [{"type": "invented"}], "actions": []}])
	assert_false(fired[0], "signal must NOT fire on rejected input — subscribers would refresh on a no-op")
	_system.set_autogrind_rules([_valid_rule()])
	assert_true(fired[0], "signal MUST fire on successful apply")
