extends GutTest

## `AutobattleSystem.create_rule` emitted a rule shape `AutobattleSystem.validate_rule`
## refuses. Measured through the real autoload before removal:
##
##     create_rule(...)      -> ["description", "conditions", "logic", "action_type"]
##     validate_rule(that)   -> ["missing 'actions' array"]
##
## It was a pre-grid fossil: the grid format every evaluator reads carries an `actions`
## ARRAY whose entries have a string `type`, and `create_rule` wrote the old `ActionType`
## ENUM under `action_type` with no `actions` key at all. Zero callers in src/, test/ or
## tools/, which is why it survived — a public-looking builder nothing had tried.
##
## It was also the last writer of the rule-level `logic` key, which `validate_rule` now
## refuses on any value but "AND". A builder that stamps a key the validator rejects is a
## contradiction, not a convenience.
##
## ⚠️ WHAT THIS GUARD IS AND IS NOT. It cannot anticipate a builder nobody has written, so
## it does not claim to. It pins two things that are checkable now:
##   1. the fossil is gone, and gone rather than renamed — nothing on the autoload offers
##      a rule builder whose output the validator would refuse;
##   2. the shape a builder WOULD have to emit, asserted against the live validator, so
##      the next person has a worked example that fails if the grammar moves under it.
## The second arm is the load-bearing one: if `validate_rule` ever stops accepting the
## canonical grid shape, this file reds and names it, which is the drift that made the
## fossil invisible in the first place.

var _sys = null


func before_each() -> void:
	_sys = get_tree().root.get_node_or_null("AutobattleSystem")


func test_control_the_autoload_and_validator_are_reachable() -> void:
	## Without this, every arm below passes by being unable to look.
	assert_not_null(_sys, "CONTROL: AutobattleSystem autoload must exist")
	if _sys == null:
		return
	assert_true(_sys.has_method("validate_rule"), "CONTROL: validate_rule must be callable")


func test_the_fossil_builder_is_gone() -> void:
	if _sys == null:
		return
	assert_false(_sys.has_method("create_rule"),
		"create_rule emitted a shape validate_rule refuses ('missing actions array') and had no callers — it must not come back without the arm below passing")


func test_no_rule_builder_on_the_autoload_emits_a_shape_the_validator_refuses() -> void:
	## Derived from the autoload's OWN method list rather than a hand-kept name list, so a
	## future `make_rule` / `build_rule` / `new_rule` is in scope the moment it lands.
	if _sys == null:
		return
	var builders: Array = []
	for m in _sys.get_method_list():
		var n: String = str(m.get("name", ""))
		if n.begins_with("_"):
			continue
		if n.find("rule") == -1:
			continue
		## A builder is a no-side-effect function that RETURNS a rule. Anything taking a
		## rule as input (validate_rule, add_rule_to_script) is not one.
		if n.begins_with("create") or n.begins_with("make") or n.begins_with("build") or n.begins_with("new"):
			builders.append(n)
	## ANTI-VACUITY FLOOR. With no builders present the loop below runs zero times and the
	## arm asserts nothing — scoring Risky, never Failed, while appearing to defend this.
	## The floor asserts the SCAN worked, so "no builders" is a measured zero rather than
	## a method list this arm could not read.
	var named: int = 0
	for m in _sys.get_method_list():
		if str(m.get("name", "")).find("rule") != -1:
			named += 1
	assert_gt(named, 3,
		"CONTROL: the scan must see the autoload's rule-named methods (validate_rule, deep_check_reachability and friends) — a near-zero here means the scan is broken, not that the class is clean, got %d" % [named])
	gut.p("rule builders found on AutobattleSystem: %s" % [builders])
	for n in builders:
		assert_true(false,
			"'%s' looks like a rule builder; it must be covered by a test asserting validate_rule accepts its output, and this guard is where that goes" % [n])


func test_the_canonical_grid_shape_a_builder_must_emit_still_validates() -> void:
	## The worked example the removal comment points at. If the grammar moves, this reds
	## and names it — which is exactly the drift that let the fossil sit unnoticed, since
	## nothing compared a builder's output to the validator.
	if _sys == null:
		return
	var rule: Dictionary = {
		"description": "heal the lowest ally when hurt",
		"enabled": true,
		"conditions": [{"type": "ally_hp_percent", "op": "<", "value": 50}],
		"actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}],
	}
	var errs: Array = _sys.validate_rule(rule)
	assert_eq(errs.size(), 0,
		"the canonical grid rule must validate — if this reds, the grammar moved and any builder written against it is now wrong: %s" % [errs])


func test_the_fossils_own_output_is_refused_which_is_why_it_was_removed() -> void:
	## The fossil's exact emitted shape, asserted against the live validator. Deliberately
	## does NOT assert on the rule-level `logic` key: that refusal lives on a different
	## branch of mine and an arm here would pass or fail depending on fold order rather
	## than on this change.
	if _sys == null:
		return
	var fossil: Dictionary = {
		"description": "the fossil's exact shape",
		"conditions": [{"type": "hp_percent", "op": "<", "value": 30}],
		"logic": "AND",
		"action_type": 1,
	}
	var errs: Array = _sys.validate_rule(fossil)
	assert_gt(errs.size(), 0, "the fossil's own output must be refused, which is why it was removed")
	var joined: String = "|".join(PackedStringArray(errs))
	assert_true(joined.find("actions") != -1,
		"and the refusal must name the missing 'actions' array, got: %s" % [errs])
