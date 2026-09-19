extends GutTest

## An OR condition in a composed AUTOBATTLE rule discards the player's ENTIRE rule set.
## The same OR in AUTOGRIND is expanded and works.
##
## RuleComposer runs ~15 normalisation passes over the model's reply before it becomes
## a player rule. One of them, `_expand_or_conditions`, splits a rule carrying an OR
## into one rule per branch — its own note says why that is sound:
##
##     "Split an OR into one rule per branch — in this grammar, rules ARE the or."
##
## That is true of BOTH grammars. AutobattleSystem evaluates rules top-to-bottom,
## first match wins, stated in three places in that file.
##
## ⛔ BUT THE PASS IS REACHED ONLY FROM `_normalise_autogrind_conditions`, WHICH
## compose_async GATES BEHIND `domain == DOMAIN_AUTOGRIND`. So for autobattle the OR
## survives to `validate_rule`, which answers "unknown condition type: 'or'" — and
## compose_async treats ANY grammar error as fatal to the WHOLE composition:
##
##     if grammar_errors.size() > 0:  -> _fallback_result(...)
##
## So one OR anywhere in the model's reply costs the player every rule it composed,
## not just the offending one. Same shape as the two preamble bugs in
## _extract_json_from_raw: a whole composed rule set lost to one malformed part.
##
## 🔑 The pass is domain-AGNOSTIC and provably so: its `types: Dictionary` parameter
## is declared and NEVER REFERENCED in the body. Nothing in it knows about autogrind.

const ReplayBackend := preload("res://tools/replay_backend.gd")

var _svc = null
var _rc = null
var _backend = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


func before_each() -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	_rc = get_tree().root.get_node_or_null("RuleComposer")
	if _svc == null or _rc == null:
		return
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_backend = ReplayBackend.new()
	_backend.name = "ReplayOr"
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend


func after_each() -> void:
	## NET. LLMService is an autoload and every arm swaps its backend list; restoring
	## here rather than at the end of an arm, because an arm that aborts would leave
	## the replay backend installed for every later FILE in the suite.
	if _backend and is_instance_valid(_backend):
		_backend.request_finished.disconnect(_svc._on_backend_finished)
		_svc.remove_child(_backend)
		_backend.free()
		_backend = null
	if _svc:
		_svc._backends.clear()
		for b in _orig_backends:
			_svc._backends.append(b)
		_svc._active_backend = _orig_active
		_svc.llm_enabled = _orig_enabled


func _payload(rules_json: String) -> String:
	return JSON.stringify({"name": "n", "description": "d", "rules_json": rules_json})


## One rule whose single condition is an OR of two branches the autobattle grammar
## accepts on their own. Both branches are real CONDITION_TYPES, so the ONLY thing
## the validator can object to is the unexpanded `or` wrapper.
const OR_RULE := '[{"conditions":[{"type":"or","conditions":[' \
	+ '{"type":"hp_percent","operator":"<","value":30},' \
	+ '{"type":"mp_percent","operator":"<","value":20}' \
	+ ']}],"actions":[{"type":"attack","target":"lowest_hp_enemy"}],"enabled":true}]'


# ── floor ─────────────────────────────────────────────────────────────────────

func test_the_pieces_this_file_drives_are_all_reachable() -> void:
	## FILE-LEVEL FLOOR, derived from what the arms below actually touch. Without it
	## a rename makes an arm abort mid-frame and score green on an earlier assert.
	assert_not_null(_svc, "LLMService autoload missing — nothing below runs")
	assert_not_null(_rc, "RuleComposer autoload missing — nothing below runs")
	assert_true(_rc.has_method("compose_async"), "RuleComposer.compose_async is gone")
	assert_true(_rc.has_method("_expand_or_conditions"),
		"RuleComposer._expand_or_conditions is gone — the pass this file is about")
	assert_true("DOMAIN_AUTOBATTLE" in _rc and "DOMAIN_AUTOGRIND" in _rc,
		"the domain constants this file switches on are gone")


# ── control: the transformation is sound and domain-agnostic ──────────────────

func test_the_pass_expands_an_autobattle_shaped_rule_correctly() -> void:
	## CONTROL, and the reason the defect arm accuses the CALL SITE rather than the
	## pass. Handed an autobattle-shaped rule directly, `_expand_or_conditions` splits
	## it into one rule per branch — so the transformation already works for this
	## grammar and the only thing missing is being called for it.
	##
	## If this ever fails, the pass itself is the defect and the arms below are
	## accusing the wrong place.
	var rules: Array = [{
		"conditions": [{"type": "or", "conditions": [
			{"type": "hp_percent", "operator": "<", "value": 30},
			{"type": "mp_percent", "operator": "<", "value": 20},
		]}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
		"enabled": true,
	}]
	var notes: Array = _rc._expand_or_conditions(rules, {})
	assert_eq(rules.size(), 2,
		"the pass must split one OR of two branches into two rules, got %d" % rules.size())
	assert_gt(notes.size(), 0, "and must say so, or the player is not told what changed")
	var types: Array = []
	for r in rules:
		types.append(str(((r as Dictionary)["conditions"] as Array)[0].get("type", "")))
	assert_eq(types, ["hp_percent", "mp_percent"],
		"each split rule must carry ONE branch as its condition, got %s" % [types])


func test_the_pass_ignores_the_types_argument_entirely() -> void:
	## The claim that it is domain-agnostic, made executable. The parameter is
	## declared and never read, so the same input must expand identically whether
	## it is handed the autogrind table or nothing at all. If a future change starts
	## consuming it, this reds and the "just call it for autobattle" fix needs review.
	var a: Array = [{"conditions": [{"type": "or", "conditions": [
		{"type": "hp_percent", "operator": "<", "value": 30},
		{"type": "mp_percent", "operator": "<", "value": 20}]}],
		"actions": [{"type": "attack"}], "enabled": true}]
	var b: Array = a.duplicate(true)
	_rc._expand_or_conditions(a, {})
	_rc._expand_or_conditions(b, {"hp_percent": "x", "mp_percent": "y", "anything": "z"})
	assert_eq(a.size(), b.size(),
		"the pass behaved differently for two different `types` tables — it is not "
		+ "domain-agnostic after all, and calling it for autobattle needs more than a call")


# ── the defect ────────────────────────────────────────────────────────────────

func test_an_or_does_not_discard_the_whole_autobattle_composition() -> void:
	## THE DEFECT, at the surface the player meets. compose_async treats any grammar
	## error as fatal to the ENTIRE composition, so an unexpanded OR does not cost
	## one rule — it costs every rule the model just wrote.
	if _backend == null:
		pending("replay backend unavailable")
		return
	_backend.next_text = _payload(OR_RULE)
	var res: Dictionary = await _rc.compose_async(_rc.DOMAIN_AUTOBATTLE, "attack when hp or mp is low", "hero", [])
	assert_eq(str(res.get("source", "")), "llm",
		("an OR condition discarded the player's whole autobattle composition — source=%s, "
		+ "errors=%s. The grind domain expands the same OR into one rule per branch; "
		+ "autobattle never reaches that pass, so validate_rule rejects 'or' and "
		+ "compose_async falls back for the ENTIRE set.")
			% [str(res.get("source", "")), res.get("errors", [])])


func test_the_surviving_autobattle_rules_are_one_per_branch() -> void:
	## Direction matters: surviving is not enough. A composer that dropped the OR
	## condition and kept an unconditional rule would satisfy the arm above while
	## silently changing what the player asked for.
	if _backend == null:
		pending("replay backend unavailable")
		return
	_backend.next_text = _payload(OR_RULE)
	var res: Dictionary = await _rc.compose_async(_rc.DOMAIN_AUTOBATTLE, "attack when hp or mp is low", "hero", [])
	var rules: Array = res.get("rules", []) as Array
	assert_eq(rules.size(), 2,
		"an OR of two branches must reach the player as two rules, got %d" % rules.size())
	var seen: Array = []
	for r in rules:
		var conds: Array = (r as Dictionary).get("conditions", []) as Array
		if conds.size() > 0:
			seen.append(str((conds[0] as Dictionary).get("type", "")))
	assert_true(seen.has("hp_percent") and seen.has("mp_percent"),
		"both branches of the OR must survive as their own rule, got %s" % [seen])


func test_a_plain_autobattle_rule_still_composes() -> void:
	## FLOOR on the fixture. If composition broke for every reply, the arms above
	## would red for a reason that has nothing to do with OR handling, and the
	## message would send the next reader to the wrong pass.
	if _backend == null:
		pending("replay backend unavailable")
		return
	_backend.next_text = _payload(
		'[{"conditions":[{"type":"hp_percent","operator":"<","value":30}],'
		+ '"actions":[{"type":"attack","target":"lowest_hp_enemy"}],"enabled":true}]')
	var res: Dictionary = await _rc.compose_async(_rc.DOMAIN_AUTOBATTLE, "attack low", "hero", [])
	assert_eq(str(res.get("source", "")), "llm",
		"a plain autobattle rule no longer composes — the arms above are not about OR: %s"
			% [res.get("errors", [])])
