extends GutTest

## Two of 33 compositions died because the model wrote "target": null.
##
## The grammar expresses "no target" by OMITTING the key, and the validator
## accepts that. A model writing the key with a JSON null means the same thing
## and gets `unknown target type: '<null>'` — which, because one bad rule
## discards the WHOLE ruleset, costs the player the entire composition.
##
## Measured across every parseable local-llama3 composition captured for the
## Rule Composer work: 33 scanned, 2 carried an explicit null.
##
## THE VALIDATOR IS RIGHT TO REFUSE IT and is left alone. `str(null)` is the
## literal "<null>", and worse, `action.get("target", "lowest_hp_enemy")` returns
## null rather than the default when the key is PRESENT — so a null that reached
## an installed profile would assign Nil to a typed String in
## AutobattleGridEditor and abort the enclosing function. The refusal protects
## that; this normalises the rule so it never needs refusing.

const OVERLAY := preload("res://src/ui/autobattle/RuleComposerOverlay.gd")

var _rc = null


func before_each() -> void:
	_rc = get_tree().root.get_node_or_null("RuleComposer")
	assert_not_null(_rc, "CONTROL: RuleComposer autoload must exist")


func _rule_with_null_target() -> Dictionary:
	return {"conditions": [{"type": "always"}],
			"actions": [{"type": "attack", "target": null}],
			"enabled": true}


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_null_target_is_rejected_before_the_fix() -> void:
	## CONTROL establishing the defect is real, against the live validator.
	var errs: Array = AutobattleSystem.validate_rule(_rule_with_null_target(), "")
	assert_gt(errs.size(), 0, "an explicit null target must be rejected by the validator")
	assert_true(", ".join(errs).find("<null>") != -1,
		"and it reports the stringified null, which is how this was spotted")


func test_dropping_the_key_makes_the_rule_valid() -> void:
	var rules: Array = [_rule_with_null_target()]
	assert_eq(_rc._drop_null_targets(rules), 1, "one null target must be dropped")
	assert_false((rules[0]["actions"] as Array)[0].has("target"),
		"the key must be ERASED, not set to a guessed value")
	assert_eq(AutobattleSystem.validate_rule(rules[0], "").size(), 0,
		"and the rule must now pass the validator it was failing")


func test_the_action_keeps_everything_else() -> void:
	var rules: Array = [_rule_with_null_target()]
	_rc._drop_null_targets(rules)
	assert_eq(str((rules[0]["actions"] as Array)[0]["type"]), "attack",
		"dropping one key must not disturb the rest of the action")
	assert_eq((rules[0]["conditions"] as Array).size(), 1, "or the conditions")


# ── it must not reach past target ─────────────────────────────────────────────

func test_a_real_target_is_never_touched() -> void:
	## CONTROL: this must not become "strip targets".
	var rules: Array = [{"conditions": [{"type": "always"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]
	assert_eq(_rc._drop_null_targets(rules), 0, "a valid target must be left alone")
	assert_eq(str((rules[0]["actions"] as Array)[0]["target"]), "lowest_hp_enemy",
		"and must still be exactly what the model chose")


func test_a_null_CONDITION_value_is_deliberately_left_to_be_rejected() -> void:
	## THE DISCRIMINATOR, and the reason this is narrow. A condition with a null
	## value is genuinely broken — the model failed to state a threshold. Stripping
	## that key would produce a rule that validates and then compares against a
	## default nobody chose: a plausible-looking artifact, which is worse than a
	## refusal. Only `target` has a documented, defined absent state.
	var rules: Array = [{"conditions": [{"type": "hp_percent", "op": "<", "value": null}],
		"actions": [{"type": "attack"}], "enabled": true}]
	_rc._drop_null_targets(rules)
	assert_true((rules[0]["conditions"] as Array)[0].has("value"),
		"a null condition value must NOT be stripped — it has no safe absent meaning")


func test_an_absent_target_is_not_invented() -> void:
	## CONTROL the other way: the repair must not ADD a target to an action that
	## legitimately has none.
	var rules: Array = [{"conditions": [{"type": "always"}],
		"actions": [{"type": "defer"}], "enabled": true}]
	assert_eq(_rc._drop_null_targets(rules), 0, "nothing to drop")
	assert_false((rules[0]["actions"] as Array)[0].has("target"),
		"and no target may be invented")


func test_malformed_rules_do_not_crash_the_pass() -> void:
	var rules: Array = ["not a rule", {}, {"actions": "not an array"},
		{"actions": ["not an action"]}]
	assert_eq(_rc._drop_null_targets(rules), 0, "malformed shapes must be skipped, not crash")
	assert_eq(rules.size(), 4, "and nothing may be dropped from the list itself")


# ── it is silent, on purpose ──────────────────────────────────────────────────

func test_dropping_a_null_target_produces_no_player_note() -> void:
	## Deliberate, and pinned so it stays deliberate: notes exist to disclose
	## changes to what a rule DOES. A null target and an absent target mean the
	## same thing, so reporting this would be noise in a list whose whole value is
	## that every line matters.
	var overlay = OVERLAY.new()
	add_child_autofree(overlay)
	overlay._preview_panel = Panel.new()
	overlay.add_child(overlay._preview_panel)
	var rules: Array = [_rule_with_null_target()]
	_rc._drop_null_targets(rules)
	overlay._populate_preview({"description": "d", "rules": rules, "notes": []})
	var label: Label = overlay._preview_panel.get_node_or_null("PreviewLabel") as Label
	assert_eq(label.text.find("Adjusted"), -1,
		"a semantics-preserving normalisation must not be reported as an adjustment")
