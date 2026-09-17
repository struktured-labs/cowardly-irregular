extends GutTest

## compose_async turns ANY grammar error into `_fallback_result` — the canned draft — so
## one condition the model spelled its own way costs the player every rule they asked for.
##
## MEASURED by replaying 20 captured live-llama3 replies through the REAL compose_async
## (tools/replay_backend.gd), one intent held fixed:
##
##     as shipped   13 of 20 survived
##     after        20 of 20
##
## The seven losses were five distinct shapes, and every one is the model expressing
## something this grammar spells differently rather than inventing a mechanic:
##
##     member_hp_min · member_hp_avg    an aggregate that is spelled party_*
##     op "in" with a list value        "is it one of these" on member_status
##     any_of {conditions: [...]}       boolean OR
##     or {options: [...]}              boolean OR, second spelling
##     {"always": ""}                   the type written as the KEY
##
## HOW TO RE-RUN IT, because the number above is the only thing that can find this class
## and no per-field probe can: capture whole replies from a live sampling run to disk, then
## drive each one back through compose_async with tools/replay_backend.gd and count how many
## return source == "llm" rather than the canned draft. Always plant a control reply that
## MUST be refused — a cleric casting `firaga` — or a clean sweep cannot be distinguished
## from a harness that has stopped detecting losses.
##
## Run against autobattle the same way, 2 intents x 20 replies: 20 of 20 survived both, with
## the planted control correctly LOST. That side carries more repairs already, so the shape
## class is a grind-side defect rather than a composer-wide one.
##
## Every repair is a lookup in AutogrindSystem's own vocabulary — PARTY_CONDITION_TYPES,
## NULLARY_CONDITIONS, NAMED_VALUE_CONDITIONS, OPERATORS — so none of them is a table of
## guesses kept in the composer. Each condition below is VERBATIM from a captured reply.

const RC := preload("res://src/llm/RuleComposer.gd")


func _rc():
	var c = RC.new()
	if c is Node:
		add_child_autofree(c)
	return c


func _sys():
	var s = get_tree().root.get_node_or_null("AutogrindSystem")
	assert_not_null(s, "CONTROL: AutogrindSystem autoload must exist")
	return s


func _rule(conds: Array, action: String = "stop_grinding") -> Dictionary:
	return {"conditions": conds, "actions": [{"type": action}], "enabled": true}


func _types(rules: Array) -> Array:
	var out: Array = []
	for r in rules:
		for c in r.get("conditions", []):
			out.append(str(c.get("type", "<none>")))
	return out


func _errors(rules: Array) -> Array:
	var errs: Array = []
	for r in rules:
		for e in _sys().validate_rule(r):
			errs.append(str(e))
	return errs


# ── an aggregate spelled member_* ─────────────────────────────────────────────

func test_a_member_aggregate_is_read_as_the_party_one() -> void:
	## Verbatim from replies 03 and 09. The mirror of the party_ strip already here:
	## swapped ONLY when the swapped name is itself a live type.
	var rules: Array = [_rule([{"type": "member_hp_min", "op": "<", "value": 30}]),
		_rule([{"type": "member_hp_avg", "op": "<", "value": 80}])]
	var notes: Array = _rc()._normalise_autogrind_conditions(rules, _sys())
	assert_eq(_types(rules), ["party_hp_min", "party_hp_avg"], "both are party-level aggregates")
	assert_eq(_errors(rules), [], "and the rules now validate")
	assert_eq(notes.size(), 2, "each is reported: %s" % str(notes))


func test_a_member_type_that_is_real_is_not_swapped() -> void:
	## CONTROL. member_hp and member_dead are live types — rewriting them to party_*
	## would change what the player asked about from one character to the whole party.
	var rules: Array = [_rule([{"type": "member_hp", "member": "cleric", "op": "<", "value": 30}]),
		_rule([{"type": "member_dead"}])]
	var notes: Array = _rc()._normalise_autogrind_conditions(rules, _sys())
	assert_eq(_types(rules), ["member_hp", "member_dead"], "a live type is never touched")
	assert_eq(notes, [], "and nothing is claimed")


func test_a_member_type_whose_swap_is_not_live_is_left_alone() -> void:
	var rules: Array = [_rule([{"type": "member_vibes", "op": "<", "value": 3}])]
	var notes: Array = _rc()._normalise_autogrind_conditions(rules, _sys())
	assert_eq(_types(rules), ["member_vibes"], "party_vibes is not a type either, so this is a guess")
	assert_eq(notes, [], "and the validator keeps its refusal")


# ── boolean OR, which this grammar spells as separate rules ───────────────────

func test_an_or_becomes_one_rule_per_branch() -> void:
	## Verbatim from reply 17. Conditions are AND-chained and first match wins, so the
	## rule list IS the or.
	var rules: Array = [_rule([{"type": "or", "options": [
		{"type": "member_status", "value": "poison"},
		{"type": "party_hp_min", "op": "<", "value": 30}]}])]
	var notes: Array = _rc()._normalise_autogrind_conditions(rules, _sys())
	assert_eq(rules.size(), 2, "two branches, two rules")
	assert_eq(_types(rules), ["member_status", "party_hp_min"], "each rule asks one of them")
	assert_eq(_errors(rules), [], "and both validate")
	assert_gt(notes.size(), 0, "and the split is reported")


func test_the_other_spelling_is_covered_too() -> void:
	## Verbatim from reply 11: `any_of`, and its branches under `conditions` rather than
	## `options`. Covering one spelling would look right and leave the other a total loss.
	var rules: Array = [_rule([{"type": "any_of", "conditions": [
		{"type": "party_hp_min", "op": "<", "value": 30},
		{"type": "member_dead"}]}])]
	_rc()._normalise_autogrind_conditions(rules, _sys())
	assert_eq(_types(rules), ["party_hp_min", "member_dead"], "any_of/conditions is the same shape")


func test_the_split_keeps_sibling_conditions_and_the_actions() -> void:
	## An OR beside an AND: (A and (b or c)) is (A and b) or (A and c). A clone that
	## dropped A would widen the rule into one the player never wrote.
	var guard := {"type": "battles_done", "op": ">=", "value": 5}
	var rules: Array = [_rule([guard, {"type": "or", "options": [
		{"type": "member_dead"}, {"type": "party_hp_min", "op": "<", "value": 30}]}], "heal_party")]
	_rc()._normalise_autogrind_conditions(rules, _sys())
	assert_eq(rules.size(), 2, "CONTROL: it split")
	for r in rules:
		assert_true(r["conditions"].has(guard), "the AND-chained guard survives: %s" % str(r))
		assert_eq(r["actions"], [{"type": "heal_party"}], "and the actions")


func test_the_branches_stay_adjacent_and_in_order() -> void:
	## First match wins, so a clone appended at the end would be shadowed by whatever
	## the player put between.
	var tail := _rule([{"type": "always"}], "heal_party")
	var rules: Array = [_rule([{"type": "or", "options": [
		{"type": "member_dead"}, {"type": "party_hp_min", "op": "<", "value": 30}]}]), tail]
	_rc()._normalise_autogrind_conditions(rules, _sys())
	assert_eq(_types(rules), ["member_dead", "party_hp_min", "always"], "the pair stays adjacent")


func test_an_or_with_no_branches_is_left_for_the_validator() -> void:
	var rules: Array = [_rule([{"type": "or"}])]
	var notes: Array = _rc()._normalise_autogrind_conditions(rules, _sys())
	assert_eq(rules.size(), 1, "there is nothing to expand into")
	assert_eq(notes, [], "and nothing may be claimed")


# ── the type written as the key ───────────────────────────────────────────────

func test_a_type_written_as_the_key_is_read_as_the_type() -> void:
	## Verbatim from reply 12: {"always": ""} for {"type": "always"}.
	var rules: Array = [_rule([{"always": ""}])]
	var notes: Array = _rc()._normalise_autogrind_conditions(rules, _sys())
	assert_eq(_types(rules), ["always"], "the key names the condition")
	assert_eq(_errors(rules), [], "and it validates")
	assert_gt(notes.size(), 0, "and it is reported")


func test_only_a_lone_key_that_is_a_live_type_is_read_that_way() -> void:
	## Anything looser rewrites a rule on the strength of a coincidence: a condition
	## with two keys is a malformed condition, not a type-as-key.
	var rules: Array = [_rule([{"op": "<", "value": 3}]), _rule([{"nonsense": ""}])]
	var notes: Array = _rc()._normalise_autogrind_conditions(rules, _sys())
	assert_eq(_types(rules), ["<none>", "<none>"], "neither may be rewritten")
	assert_eq(notes, [], "and nothing claimed")


# ── an operator a named-value condition cannot use ────────────────────────────

func test_an_unusable_op_on_a_status_condition_is_dropped() -> void:
	## Verbatim from replies 04 and 13. member_status asks whether the status is PRESENT
	## — the evaluator never reads op — but validate_rule refuses an unknown one, and
	## that discards the whole composition.
	var rules: Array = [_rule([{"type": "member_status", "op": "in", "value": "poison"}])]
	var notes: Array = _rc()._normalise_autogrind_conditions(rules, _sys())
	assert_false(rules[0]["conditions"][0].has("op"), "the op it cannot use is gone")
	assert_eq(rules[0]["conditions"][0]["value"], "poison", "and the status it asked for is kept")
	assert_eq(_errors(rules), [], "so the rule validates")
	assert_gt(notes.size(), 0, "and it is reported")


func test_a_valid_op_is_kept_and_a_numeric_conditions_bad_op_is_not_touched() -> void:
	## Two controls in one: the drop is scoped to NAMED_VALUE conditions and to ops the
	## system does not know. On a numeric condition the op is load-bearing, so silently
	## dropping it would change the comparison rather than repair it.
	var rules: Array = [_rule([{"type": "member_status", "op": "==", "value": "poison"}]),
		_rule([{"type": "party_hp_min", "op": "in", "value": 30}])]
	var notes: Array = _rc()._normalise_autogrind_conditions(rules, _sys())
	assert_eq(str(rules[0]["conditions"][0].get("op", "")), "==", "a valid op is left alone")
	assert_eq(str(rules[1]["conditions"][0].get("op", "")), "in",
		"and a numeric condition keeps its op, so the validator still refuses it")
	assert_eq(notes, [], "neither is a repair")


# ── nothing is claimed about a correct ruleset ────────────────────────────────

func test_a_correct_ruleset_is_untouched_and_silent() -> void:
	## The notes panel says what the composer CHANGED. A note on an untouched ruleset is
	## a lie about the player's own rules.
	var rules: Array = [_rule([{"type": "party_hp_min", "op": "<", "value": 30}], "heal_party"),
		_rule([{"type": "member_status", "value": "poison"}]), _rule([{"type": "always"}])]
	var before: Array = rules.duplicate(true)
	var notes: Array = _rc()._normalise_autogrind_conditions(rules, _sys())
	assert_eq(rules, before, "byte-for-byte unchanged")
	assert_eq(notes, [], "and silent")


# ── the repairs must be WIRED, which no arm above can tell you ────────────────

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


func test_a_real_composition_carrying_every_shape_survives() -> void:
	## THE CONSEQUENCE ARM. All thirteen above call the helper by hand and stay green if
	## compose_async stops calling it — which is the defect. One reply carrying all five
	## measured shapes at once, driven through the shipping path.
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
			_rule([{"type": "member_hp_min", "op": "<", "value": 30}]),
			_rule([{"type": "member_status", "op": "in", "value": "poison"}]),
			_rule([{"type": "or", "options": [
				{"type": "member_dead"}, {"type": "party_hp_min", "op": "<", "value": 20}]}]),
			_rule([{"always": ""}]),
		])})
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend
	var res: Dictionary = await rc.compose_async("autogrind", "stop when things go wrong", "", [])
	assert_eq(str(res.get("source", "")), "llm",
		"the composition must survive: %s" % str(res.get("errors", [])))
	assert_eq(res.get("errors", []), [], "with no grammar errors left")
	assert_eq(_types(res.get("rules", [])),
		["party_hp_min", "member_status", "member_dead", "party_hp_min", "always"],
		"every shape read as what the grammar spells")
