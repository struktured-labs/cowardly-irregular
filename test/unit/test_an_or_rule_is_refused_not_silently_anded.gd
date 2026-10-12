extends GutTest

## A shared autobattle script carrying a rule-level `logic: "OR"` used to import clean and
## then fire only when EVERY condition held — the opposite of what the rule said.
##
## The key is real, not a phantom: `AutobattleSystem.create_rule` writes `"logic": "AND"`
## into every rule it builds, so `logic` is part of the shared export format and a
## hand-edited or friend-sent script can carry "OR" legitimately.
##
## ⛔ NOTHING EVALUATES IT. The live path is `_evaluate_grid_rule`, whose loop is
##
##     # All conditions must be true (AND logic)
##     for condition in rule["conditions"]:
##         if not _evaluate_grid_condition(combatant, condition): return false
##
## and which never reads `logic`. The only function that honours the key,
## `_evaluate_rule`, is dead — its own comment says so and it has no caller in `src/`
## (measured: one occurrence of `_evaluate_rule(` in all of `src/`, its own definition).
##
## And `validate_rule` whitelisted no rule-level key, so the import choke point at
## `ScriptShareManager.validate_imported_script` — which runs every imported rule through
## `validate_rule` — waved it through. The player then has a rule that reads "fire if the
## tank is low OR the healer is low" and fires only when both are, with no error anywhere.
##
## This is NOT the OR already covered by `test_an_or_costs_the_autobattle_player_the_whole_set`.
## That one is an OR *condition type* (`{"type": "or", ...}`) in an LLM-composed reply, which
## `validate_rule` already rejects ("unknown condition type: 'or'") and which costs the whole
## composition. This is a rule-level *key* that was accepted and ignored. Different path
## (import/share, not composition), different symptom (silent wrong behaviour, not a
## discarded set).
##
## The repair refuses it at the validator, because that is the layer the import path already
## consults — so the player hears about it when the script arrives rather than wondering for
## a session why a rule never triggers. The message names the fix in the grammar's own idiom:
## rules are tried top-to-bottom, first match wins, so separate rules ARE the or.

const SSM := preload("res://src/autobattle/ScriptShareManager.gd")


func _sys():
	var s = get_tree().root.get_node_or_null("AutobattleSystem")
	assert_not_null(s, "CONTROL: AutobattleSystem autoload must exist, or nothing below is a test")
	return s


func _rule(extra: Dictionary = {}) -> Dictionary:
	## A rule that is otherwise valid, so an error can only come from what the arm adds.
	var r: Dictionary = {
		"conditions": [{"type": "hp_percent", "op": "<", "value": 30}],
		"actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}],
	}
	for k in extra:
		r[k] = extra[k]
	return r


func _logic_errors(errs: Array) -> Array:
	var out: Array = []
	for e in errs:
		if str(e).find("'logic'") != -1:
			out.append(str(e))
	return out


func test_control_the_base_rule_validates_clean() -> void:
	## Without this, every arm below could pass because the fixture is simply invalid.
	var sys = _sys()
	if sys == null:
		return
	var errs: Array = sys.validate_rule(_rule())
	assert_eq(errs.size(), 0, "CONTROL: the fixture rule must be valid with no 'logic' key, got: %s" % [errs])


func test_control_logic_and_is_accepted_because_create_rule_writes_it() -> void:
	## create_rule stamps "AND" on everything it builds. Refusing that would reject the
	## engine's own exports, which is a worse bug than the one being fixed.
	var sys = _sys()
	if sys == null:
		return
	for v in ["AND", "and", " And "]:
		var errs: Array = sys.validate_rule(_rule({"logic": v}))
		assert_eq(_logic_errors(errs).size(), 0,
			"logic '%s' must be accepted — it is what create_rule writes, modulo case/space" % [v])


func test_an_or_rule_is_refused_and_the_message_says_what_to_do() -> void:
	var sys = _sys()
	if sys == null:
		return
	var errs: Array = sys.validate_rule(_rule({"logic": "OR"}))
	var hits: Array = _logic_errors(errs)
	assert_eq(hits.size(), 1, "a rule-level logic:'OR' must produce exactly one 'logic' error, got: %s" % [errs])
	if hits.size() != 1:
		return
	var msg: String = hits[0]
	assert_true(msg.find("OR") != -1, "the message must quote the offending value back: %s" % [msg])
	## The player cannot act on "unsupported". They can act on "split it into two rules".
	assert_true(msg.to_lower().find("split") != -1,
		"the message must tell the player to split the rule, not just that it is wrong: %s" % [msg])


func test_a_lowercase_or_is_refused_too() -> void:
	## A hand-edited JSON is as likely to say "or" as "OR", and the evaluator would treat
	## both the same way — which is to say, not at all.
	var sys = _sys()
	if sys == null:
		return
	for v in ["or", "Or", "OR ", "xor", "ANY"]:
		var errs: Array = sys.validate_rule(_rule({"logic": v}))
		assert_eq(_logic_errors(errs).size(), 1,
			"logic '%s' is not evaluated and must be refused, got: %s" % [v, errs])


func test_an_imported_script_with_an_or_rule_is_refused_at_the_choke_point() -> void:
	## The arm that makes this player-facing: ScriptShareManager is what a friend's script
	## goes through, and it reports per-rule so the player knows WHICH rule to split.
	var clean: Dictionary = {"rules": [_rule()]}
	assert_eq(SSM.validate_imported_script(clean).size(), 0,
		"CONTROL: an import of the valid fixture must be accepted")

	var dirty: Dictionary = {"rules": [_rule(), _rule({"logic": "OR"})]}
	var errs: Array = SSM.validate_imported_script(dirty)
	assert_eq(_logic_errors(errs).size(), 1, "the import must refuse the OR rule, got: %s" % [errs])
	var joined: String = "|".join(PackedStringArray(errs))
	assert_true(joined.find("rule 1") != -1,
		"the refusal must name the offending rule's index so the player can find it: %s" % [errs])
