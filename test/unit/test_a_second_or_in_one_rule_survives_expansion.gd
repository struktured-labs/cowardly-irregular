extends GutTest

## `_expand_or_conditions` expands only the FIRST `or` in a rule. A second one
## survives, and the pass exists precisely to stop an `or` reaching validate_rule.
##
## The loop reads `rules[i]`, advances `i`, and then inserts each clone at the
## NEW `i`, advancing past it — so neither the rewritten original nor any clone
## is ever re-examined. One `or` per rule is the only case it handles.
##
## `or` is in NEITHER domain's grammar — it is a model artifact, which is why the
## repair is domain-neutral and why a survivor is always a loss rather than
## vocabulary the player chose.
##
## ⚠️ SEVERITY, STATED HONESTLY: this is not the whole-composition loss the
## file's namesake was. `_drop_unusable_rules` runs later and drops the offending
## rules rather than the set. But expansion has by then CLONED the rule, so a
## single authored rule becomes two dropped ones — the player asked for one
## behaviour and loses it, with the repair note claiming the split succeeded.

var _rc = null


func before_each() -> void:
	_rc = get_tree().root.get_node_or_null("RuleComposer")


func _two_or_rule() -> Array:
	return [{
		"conditions": [
			{"type": "or", "conditions": [
				{"type": "hp_percent", "operator": "<", "value": 30},
				{"type": "hp_percent", "operator": "<", "value": 50}]},
			{"type": "or", "conditions": [
				{"type": "mp_percent", "operator": ">", "value": 10},
				{"type": "mp_percent", "operator": ">", "value": 20}]},
		],
		"actions": [{"type": "attack"}],
		"enabled": true,
	}]


func _surviving_ors(rules: Array) -> int:
	var n: int = 0
	for r in rules:
		for c in (r as Dictionary).get("conditions", []):
			if typeof(c) == TYPE_DICTIONARY and str((c as Dictionary).get("type", "")) == "or":
				n += 1
	return n


# ── floor ─────────────────────────────────────────────────────────────────────

func test_the_pieces_this_file_drives_are_reachable() -> void:
	assert_not_null(_rc, "RuleComposer autoload missing — nothing below runs")
	assert_true(_rc.has_method("_expand_or_conditions"),
		"RuleComposer._expand_or_conditions is gone — the pass this file is about")


# ── control: one OR still works ───────────────────────────────────────────────

func test_a_single_or_still_expands() -> void:
	## CONTROL, and the reason the arms below accuse the LOOP and not the matcher.
	var rules: Array = [{
		"conditions": [{"type": "or", "conditions": [
			{"type": "hp_percent", "operator": "<", "value": 30},
			{"type": "hp_percent", "operator": "<", "value": 50}]}],
		"actions": [{"type": "attack"}], "enabled": true}]
	var notes: Array = _rc._expand_or_conditions(rules, {})
	assert_eq(rules.size(), 2, "a single two-branch OR must yield two rules")
	assert_eq(_surviving_ors(rules), 0, "a single OR must leave no 'or' behind")
	assert_gt(notes.size(), 0, "the split must be reported to the player")


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_second_or_in_the_same_rule_is_also_expanded() -> void:
	## THE DEFECT. Both the rewritten original and every clone keep the second
	## `or`, and neither is revisited.
	var rules: Array = _two_or_rule()
	_rc._expand_or_conditions(rules, {})
	assert_eq(_surviving_ors(rules), 0,
		("%d 'or' condition(s) survived expansion across %d rule(s). The loop "
		+ "advances past every clone it inserts, so only the FIRST or in a rule "
		+ "is ever expanded. A surviving 'or' is in neither grammar, so "
		+ "validate_rule rejects it and _drop_unusable_rules drops the rule — "
		+ "and expansion has already cloned it, so one authored rule becomes "
		+ "two dropped ones.") % [_surviving_ors(rules), rules.size()])


func test_two_ors_produce_every_combination() -> void:
	## Two two-branch ORs describe four condition sets. Fewer means a branch the
	## player asked for was silently dropped rather than expanded.
	var rules: Array = _two_or_rule()
	_rc._expand_or_conditions(rules, {})
	assert_eq(rules.size(), 4,
		"two two-branch ORs should yield 4 rules, got %d" % rules.size())


func test_expansion_is_bounded_so_a_pathological_reply_cannot_hang_the_composer() -> void:
	## The repair runs on model output, so its input is adversarial by default.
	## Eight two-branch ORs is 256 rules uncapped; the composer must refuse to
	## grow without limit rather than build them.
	var conds: Array = []
	for i in range(8):
		conds.append({"type": "or", "conditions": [
			{"type": "hp_percent", "operator": "<", "value": 10 + i},
			{"type": "hp_percent", "operator": "<", "value": 50 + i}]})
	var rules: Array = [{"conditions": conds, "actions": [{"type": "attack"}], "enabled": true}]
	_rc._expand_or_conditions(rules, {})
	assert_lt(rules.size(), 100,
		"expansion grew to %d rules from one authored rule — it is unbounded" % rules.size())
