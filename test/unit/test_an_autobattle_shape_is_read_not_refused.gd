extends GutTest

## One grammar error makes compose_async return the canned draft, so a condition the model
## spelled its own way costs the player their entire ruleset.
##
## MEASURED by replaying 48 captured live-llama3 replies — 4 jobs x 12, each job's own
## authored bench intent — through the REAL compose_async, with a per-job control reply that
## MUST be refused (a level-1 character casting `firaga`):
##
##     before   mage 12/12 · fighter 12/12 · rogue 11/12 · bard 11/12   = 46 of 48
##     after    12/12 · 12/12 · 12/12 · 12/12                           = 48 of 48
##     controls refused in every run, before and after
##
## Three shapes, verbatim from the losses:
##
##     {"type":"ally_dead","op":"","value":null}      an empty payload on a NULLARY condition
##     {"type":"ally_hp_percent","op":">=0"}          the operator and value fused
##     {"type":"lullaby","target":"self"}             an ability id used as the action TYPE
##
## ⚠️ The first is a repair the AUTOGRIND side has carried all along. It was absent here for
## a reason worth naming: nothing on the autobattle side NAMED the nullary set — it lived in
## the grammar prose and in two evaluator comments — so there was no list to repair against.
## AutobattleSystem.NULLARY_CONDITIONS now names it, derived from the ARMS rather than the
## grammar, because the arms are what decides at runtime (setup_complete is nullary by
## behaviour and the grammar does not say so).

const RC := preload("res://src/llm/RuleComposer.gd")


func _rc():
	var c = RC.new()
	if c is Node:
		add_child_autofree(c)
	return c


func _sys():
	var s = get_tree().root.get_node_or_null("AutobattleSystem")
	assert_not_null(s, "CONTROL: AutobattleSystem autoload must exist")
	return s


func _ctx(kit: Array = ["battle_hymn", "lullaby", "riff"]) -> Dictionary:
	return {"resolved": true, "job_id": "bard", "kit": kit, "full_kit": kit,
		"max_mp": 70, "costs": {}, "items": ["potion"]}


func _rule(conds: Array, acts: Array) -> Dictionary:
	return {"conditions": conds, "actions": acts, "enabled": true}


func _errors(rules: Array) -> Array:
	var errs: Array = []
	for r in rules:
		for e in _sys().validate_rule(r):
			errs.append(str(e))
	return errs


# ── an empty payload on a nullary condition ───────────────────────────────────

func test_a_nullary_condition_sheds_an_empty_payload() -> void:
	## Verbatim from rogue/07. ally_dead reads neither op nor value; validate_rule refuses
	## the empty op, and that discards the whole composition.
	var rules: Array = [_rule([{"type": "ally_dead", "op": "", "value": null}],
		[{"type": "attack"}])]
	var notes: Array = _rc()._normalise_autobattle_shapes(rules, _ctx())
	assert_false(rules[0]["conditions"][0].has("op"), "the empty op is gone")
	assert_false(rules[0]["conditions"][0].has("value"), "and the null value")
	assert_eq(_errors(rules), [], "so the rule validates")
	assert_eq(notes.size(), 2, "each is reported: %s" % str(notes))


func test_a_non_nullary_condition_keeps_its_empty_op() -> void:
	## THE CONTROL THAT MATTERS. Dropping an empty op from a NUMERIC condition does not
	## repair it — it silently substitutes whatever the evaluator defaults to, turning a
	## refusal the player would see into a comparison they never wrote.
	var rules: Array = [_rule([{"type": "hp_percent", "op": "", "value": 30}], [{"type": "attack"}])]
	var notes: Array = _rc()._normalise_autobattle_shapes(rules, _ctx())
	assert_eq(str(rules[0]["conditions"][0].get("op", "<missing>")), "",
		"the op stays, so the validator keeps its refusal")
	assert_eq(notes, [], "and nothing is claimed")


func test_every_named_nullary_is_a_real_condition_type() -> void:
	## A ratchet on the const this fix added: a typo there would silently stop repairing a
	## live condition, and nothing else would notice.
	var sys = _sys()
	for id in sys.NULLARY_CONDITIONS:
		assert_true(sys.CONDITION_TYPES.has(str(id)),
			"'%s' is named nullary but is not a condition type" % id)


# ── the operator and value fused ──────────────────────────────────────────────

func test_a_fused_operator_is_split_into_its_parts() -> void:
	## Verbatim from bard/00. The string carries both halves, so this is a parse of what
	## the model wrote rather than a guess about what it meant.
	var rules: Array = [_rule([{"type": "ally_hp_percent", "op": ">=0"}], [{"type": "attack"}])]
	var notes: Array = _rc()._normalise_autobattle_shapes(rules, _ctx())
	assert_eq(str(rules[0]["conditions"][0]["op"]), ">=", "the operator it names")
	assert_eq(int(rules[0]["conditions"][0]["value"]), 0, "and the value glued to it")
	assert_eq(_errors(rules), [], "so the rule validates")
	assert_gt(notes.size(), 0, "and it is reported")


func test_a_fused_operator_that_disagrees_with_a_present_value_is_refused() -> void:
	## Then it IS a guess: two numbers and no way to know which the player meant.
	var rules: Array = [_rule([{"type": "hp_percent", "op": "<40", "value": 25}], [{"type": "attack"}])]
	var notes: Array = _rc()._normalise_autobattle_shapes(rules, _ctx())
	assert_eq(str(rules[0]["conditions"][0]["op"]), "<40", "left for the validator")
	assert_eq(int(rules[0]["conditions"][0]["value"]), 25, "and the value untouched")
	assert_eq(notes, [], "nothing claimed")


func test_a_fused_operator_whose_tail_is_not_a_number_is_left_alone() -> void:
	var rules: Array = [_rule([{"type": "hp_percent", "op": ">=lots"}], [{"type": "attack"}])]
	var notes: Array = _rc()._normalise_autobattle_shapes(rules, _ctx())
	assert_eq(str(rules[0]["conditions"][0]["op"]), ">=lots", "there is no value to recover")
	assert_eq(notes, [], "nothing claimed")


# ── an ability id used as the action type ─────────────────────────────────────

func test_an_ability_named_as_the_action_type_is_read_as_an_ability() -> void:
	## Verbatim from bard/00, three times in one composition.
	var rules: Array = [_rule([{"type": "always"}], [{"type": "lullaby", "target": "self"}])]
	var notes: Array = _rc()._normalise_autobattle_shapes(rules, _ctx())
	var a: Dictionary = rules[0]["actions"][0]
	assert_eq(str(a["type"]), "ability", "the action is an ability")
	assert_eq(str(a["id"]), "lullaby", "and the ability is the one it named")
	assert_eq(str(a["target"]), "self", "and the target it asked for survives")
	assert_gt(notes.size(), 0, "and it is reported")


func test_only_an_ability_in_THIS_characters_kit_is_read_that_way() -> void:
	## Scoped to the kit, so the rewrite can only produce an action the deep check would
	## already have accepted. An id from another job must stay a refusal, not become one
	## the composer invented.
	var rules: Array = [_rule([{"type": "always"}], [{"type": "firaga"}])]
	var notes: Array = _rc()._normalise_autobattle_shapes(rules, _ctx())
	assert_eq(str(rules[0]["actions"][0]["type"]), "firaga", "not in the bard's kit, so not rewritten")
	assert_eq(notes, [], "and nothing claimed")


func test_a_real_action_type_is_never_rewritten() -> void:
	## CONTROL on the scan: it must key on "not a live action type", not on "appears in
	## the kit" — an ability id that collided with an action name would otherwise be eaten.
	var rules: Array = [_rule([{"type": "always"}], [{"type": "attack", "target": "random_enemy"}])]
	var notes: Array = _rc()._normalise_autobattle_shapes(rules, _ctx(["attack"]))
	assert_eq(str(rules[0]["actions"][0]["type"]), "attack", "a live action type wins")
	assert_eq(notes, [], "and nothing claimed")


func test_a_correct_ruleset_is_untouched_and_silent() -> void:
	var rules: Array = [_rule([{"type": "ally_dead"}],
		[{"type": "ability", "id": "lullaby", "target": "lowest_hp_ally"}])]
	var before: Array = rules.duplicate(true)
	var notes: Array = _rc()._normalise_autobattle_shapes(rules, _ctx())
	assert_eq(rules, before, "byte-for-byte unchanged")
	assert_eq(notes, [], "and silent")


# ── the repair must be WIRED, which no arm above can tell you ─────────────────

var _svc = null
var _backend = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


func after_each() -> void:
	if _backend == null or not is_instance_valid(_backend):
		return
	_backend.request_finished.disconnect(_svc._on_backend_finished)
	_svc.remove_child(_backend)
	_backend.free()
	_backend = null
	_svc._backends.clear()
	for b in _orig_backends:
		_svc._backends.append(b)
	_svc._active_backend = _orig_active
	_svc.llm_enabled = _orig_enabled


func test_a_real_composition_carrying_all_three_shapes_survives() -> void:
	## THE CONSEQUENCE ARM. Every arm above calls the helper by hand and stays green if
	## compose_async stops calling it — which is the defect. This is also the only arm that
	## would have caught the first version of this fix: it passed `domain_system` before
	## that variable was declared, which is a PARSE error, so the whole file failed to load.
	var rc = get_tree().root.get_node_or_null("RuleComposer")
	assert_not_null(rc, "CONTROL: RuleComposer autoload must exist")
	_svc = get_tree().root.get_node_or_null("LLMService")
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist")
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_backend = preload("res://tools/replay_backend.gd").new()
	_backend.name = "ReplayBE"
	_backend.next_text = JSON.stringify({"name": "n", "description": "d",
		"rules_json": JSON.stringify([
			_rule([{"type": "ally_dead", "op": "", "value": null}],
				[{"type": "battle_hymn", "target": "all_allies"}]),
			_rule([{"type": "ally_hp_percent", "op": ">=0"}], [{"type": "attack"}]),
		])})
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend
	var res: Dictionary = await rc.compose_async("autobattle", "support the party", "bard", [])
	assert_eq(str(res.get("source", "")), "llm",
		"the composition must survive: %s" % str(res.get("errors", [])))
	assert_eq(res.get("errors", []), [], "with no grammar errors left")
	var rules: Array = res.get("rules", [])
	assert_eq(rules.size(), 2, "both rules delivered")
	assert_eq(str((rules[0]["actions"][0] as Dictionary).get("id", "")), "battle_hymn",
		"the ability read as an ability on the real path")
	assert_eq(str((rules[1]["conditions"][0] as Dictionary).get("op", "")), ">=",
		"and the fused operator split")


func test_a_newly_recognised_ability_still_gets_its_mp_guard() -> void:
	## ORDER IS THE MECHANISM. This repair must run BEFORE _supply_missing_mp_guards: an
	## action only recognised as an ability AFTER that pass never gets the guard the deep
	## check then demands, and the rule is dropped on the way out.
	##
	## That is not hypothetical — it is what the first version of this fix did. The
	## end-to-end arm above returned 1 rule of 2 and that is how it was found; this arm
	## names the property so a later reorder reds with the reason rather than a count.
	var rc = get_tree().root.get_node_or_null("RuleComposer")
	assert_not_null(rc, "CONTROL: RuleComposer autoload must exist")
	_svc = get_tree().root.get_node_or_null("LLMService")
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_backend = preload("res://tools/replay_backend.gd").new()
	_backend.name = "ReplayBE"
	_backend.next_text = JSON.stringify({"name": "n", "description": "d",
		"rules_json": JSON.stringify([
			_rule([{"type": "always"}], [{"type": "battle_hymn", "target": "all_allies"}])])})
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend
	var res: Dictionary = await rc.compose_async("autobattle", "buff the party", "bard", [])
	var rules: Array = res.get("rules", [])
	assert_eq(rules.size(), 1, "the rule must survive: %s" % str(res.get("errors", [])))
	var guarded: bool = false
	for c in (rules[0]["conditions"] as Array):
		if str((c as Dictionary).get("type", "")) == "mp_percent":
			guarded = true
	assert_true(guarded,
		"the MP guard must have been supplied for the ability this repair revealed")
