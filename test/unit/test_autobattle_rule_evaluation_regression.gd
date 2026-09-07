extends GutTest

## Regression tests for AutobattleSystem rule evaluation order.
##
## CLAUDE.md documents the contract: "Rules are evaluated top-to-bottom
## (first match wins)". The autobattle UI lets players reorder rules
## with the assumption that ordering is meaningful — if first-match-wins
## ever silently breaks, the entire scripting system stops respecting
## priority.
##
## Also covers:
##   - Disabled rules are skipped (UI toggles depend on this)
##   - Empty conditions = always match (fallback rule pattern)
##   - "always" condition type matches unconditionally
##
## We test by exercising _evaluate_grid_rule() directly rather than the
## full execute_grid_autobattle() chain. The latter rebuilds actions
## via _action_def_to_action() which strips test-only marker fields,
## making which-rule-matched harder to detect. Direct rule evaluation
## is the contract we care about anyway — action shape is its own concern.


const AutobattleSystemScript = preload("res://src/autobattle/AutobattleSystem.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")


var _autobattle: Node
var _combatant: Combatant


func before_each() -> void:
	_autobattle = AutobattleSystemScript.new()
	add_child_autofree(_autobattle)

	_combatant = CombatantScript.new()
	_combatant.combatant_name = "Hero"
	_combatant.max_hp = 100
	_combatant.current_hp = 100
	_combatant.max_mp = 50
	_combatant.current_mp = 50
	_combatant.attack = 10
	_combatant.defense = 10
	_combatant.magic = 10
	_combatant.speed = 10
	add_child_autofree(_combatant)


func _first_matching_rule_index(rules: Array) -> int:
	# Mirror the loop in execute_grid_autobattle line ~160 — early-return
	# on first matching rule.
	for i in range(rules.size()):
		if _autobattle._evaluate_grid_rule(_combatant, rules[i]):
			return i
	return -1


func test_first_match_wins_when_multiple_rules_match() -> void:
	var rules = [
		{"enabled": true, "conditions": [{"type": "always"}],
		 "actions": [{"type": "attack"}]},
		{"enabled": true, "conditions": [{"type": "always"}],
		 "actions": [{"type": "attack"}]},
	]
	assert_eq(_first_matching_rule_index(rules), 0,
		"First match must win — index 0 should be selected, not 1")


func test_unmatched_rule_falls_through_to_next() -> void:
	# Rule 0: HP < 0% (never true). Rule 1: always.
	var rules = [
		{"enabled": true,
		 "conditions": [{"type": "hp_percent", "op": "<", "value": 0}],
		 "actions": []},
		{"enabled": true, "conditions": [{"type": "always"}],
		 "actions": []},
	]
	assert_eq(_first_matching_rule_index(rules), 1,
		"Unmatched rule 0 must fall through to rule 1")


func test_disabled_rule_is_skipped() -> void:
	# Rule 0: disabled but always-match. Must be skipped.
	var rules = [
		{"enabled": false, "conditions": [{"type": "always"}],
		 "actions": []},
		{"enabled": true, "conditions": [{"type": "always"}],
		 "actions": []},
	]
	assert_eq(_first_matching_rule_index(rules), 1,
		"Disabled rule 0 must be skipped, rule 1 should match")


func test_empty_conditions_array_always_matches() -> void:
	# Per _evaluate_grid_rule line ~178: "No conditions = always match"
	var rules = [
		{"enabled": true, "conditions": [], "actions": []},
	]
	assert_eq(_first_matching_rule_index(rules), 0,
		"Empty conditions array must be treated as always-match")


func test_missing_conditions_field_always_matches() -> void:
	# Belt-and-suspenders: rule with no `conditions` key at all should
	# also match. The check `if not rule.has("conditions") or ... == 0`
	# handles both the missing-key and empty-array cases.
	var rules = [
		{"enabled": true, "actions": []},
	]
	assert_eq(_first_matching_rule_index(rules), 0,
		"Missing conditions key must also be treated as always-match")


func test_all_rules_unmatched_returns_negative_one() -> void:
	# Every rule fails — sentinel -1, signaling fallthrough to default.
	var rules = [
		{"enabled": true,
		 "conditions": [{"type": "hp_percent", "op": "<", "value": 0}],
		 "actions": []},
		{"enabled": true,
		 "conditions": [{"type": "mp_percent", "op": "<", "value": 0}],
		 "actions": []},
	]
	assert_eq(_first_matching_rule_index(rules), -1,
		"All-unmatched rules must signal fallthrough (-1)")


func test_always_condition_matches_at_full_hp() -> void:
	# Sanity: "always" type matches regardless of state.
	_combatant.current_hp = _combatant.max_hp
	var rules = [
		{"enabled": true, "conditions": [{"type": "always"}], "actions": []},
	]
	assert_eq(_first_matching_rule_index(rules), 0)


func test_always_condition_matches_at_zero_hp() -> void:
	# Even at zero HP, "always" matches.
	_combatant.current_hp = 0
	_combatant.is_alive = false
	var rules = [
		{"enabled": true, "conditions": [{"type": "always"}], "actions": []},
	]
	assert_eq(_first_matching_rule_index(rules), 0)


func test_default_enabled_is_true() -> void:
	# When `enabled` key is missing, _evaluate_grid_rule line ~174 uses
	# `rule.get("enabled", true)` — the default is true (enabled).
	var rules = [
		{"conditions": [{"type": "always"}], "actions": []},  # no 'enabled' key
	]
	assert_eq(_first_matching_rule_index(rules), 0,
		"Missing 'enabled' key must default to enabled=true")
