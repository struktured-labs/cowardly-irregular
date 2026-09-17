extends GutTest

## `member_status` carries ONE status id. `validate_rule` refuses anything else, and
## RuleComposer turns ANY grammar error into `_fallback_result` — so one malformed value
## discards the WHOLE composition, not the rule that carried it.
##
## MEASURED on live llama3 2026-09-17, 20 samples, after the prompt was given the status
## vocabulary (which took unmatchable values from 41/41 to 4/43):
##
##     ['frozen', 'poison']   2      the player said "frozen or poisoned"; the model
##     ['stun', 'poison']     1      spelled OR as a list
##     'frozen'               1      a participle surviving the instruction
##
## So 3 in 20 players asking for "stop if anyone is frozen or poisoned" lost every rule
## they asked for, and the prompt already says "ONE id from this list — never a list" on
## the line above. Prompt pressure closed 41→4 and cannot close the last 4.
##
## Both repairs are lookups in DialoguePrompts.AUTOGRIND_STATUS_VOCABULARY — the same
## table the prompt renders. An array becomes one rule per id because OR is what this
## grammar's rule list already means: conditions are AND-chained, first match wins.

const RC := preload("res://src/llm/RuleComposer.gd")
const DP := preload("res://src/llm/DialoguePrompts.gd")


func _rc():
	var c = RC.new()
	if c is Node:
		add_child_autofree(c)
	return c


func _rule(value: Variant, extra: Array = []) -> Dictionary:
	var conds: Array = [{"type": "member_status", "value": value}]
	for e in extra:
		conds.append(e)
	return {"conditions": conds, "actions": [{"type": "stop_grinding"}], "enabled": true}


func _statuses(rules: Array) -> Array:
	var out: Array = []
	for r in rules:
		for c in r.get("conditions", []):
			if str(c.get("type", "")) == "member_status":
				out.append(str(c.get("value", "")))
	return out


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_list_becomes_one_rule_per_status() -> void:
	## THE ARM. Today this composition is discarded entirely.
	var rules: Array = [_rule(["stun", "poison"])]
	var notes: Array = _rc()._normalise_member_status(rules)
	assert_eq(rules.size(), 2, "an OR of two statuses is two rules in this grammar")
	assert_eq(_statuses(rules), ["stun", "poison"], "each rule asks for one of them")
	assert_gt(notes.size(), 0, "and the player is told the composer split it")


func test_the_split_keeps_every_other_condition_and_the_actions() -> void:
	## Conditions are AND-chained, so (A and (s1 or s2)) is (A and s1) or (A and s2).
	## A clone that dropped A would widen the rule into one the player never wrote.
	var guard := {"type": "battles_done", "op": ">=", "value": 5}
	var rules: Array = [_rule(["stun", "poison"], [guard])]
	_rc()._normalise_member_status(rules)
	assert_eq(rules.size(), 2, "CONTROL: it must have split")
	for r in rules:
		assert_true(r["conditions"].has(guard), "the AND-chained guard must survive: %s" % str(r))
		assert_eq(r["actions"], [{"type": "stop_grinding"}], "and so must the actions")
		assert_eq(r.get("enabled"), true, "and the enabled flag")


func test_the_clone_sits_immediately_after_its_original() -> void:
	## First match wins. A clone appended at the END would be shadowed by whatever the
	## player put between, which silently changes which rule fires.
	var tail := {"conditions": [{"type": "always"}], "actions": [{"type": "heal_party"}]}
	var rules: Array = [_rule(["stun", "poison"]), tail]
	_rc()._normalise_member_status(rules)
	assert_eq(rules.size(), 3, "CONTROL: one split plus the untouched tail")
	assert_eq(_statuses(rules), ["stun", "poison"], "the pair stays adjacent and in order")
	assert_eq(rules[2], tail, "and the player's later rule stays last")


func test_an_english_participle_becomes_its_id() -> void:
	## The residual single-value case. `frozen` is the one the model kept writing, and it
	## is the one with no landing site: no frozen status exists, freeze is applied AS stun.
	var rules: Array = [_rule("frozen")]
	var notes: Array = _rc()._normalise_member_status(rules)
	assert_eq(_statuses(rules), ["stun"], "frozen is stun, per BattleManager's own alias")
	assert_gt(notes.size(), 0, "and the player is told what it was read as")


func test_a_list_of_participles_is_mapped_and_split() -> void:
	## The exact shape measured twice: an OR whose members are BOTH wrong.
	var rules: Array = [_rule(["frozen", "poisoned"])]
	_rc()._normalise_member_status(rules)
	assert_eq(_statuses(rules), ["stun", "poison"], "both mapped, both kept")


# ── it must not invent, and must not repair what is already right ─────────────

func test_a_correct_value_is_left_exactly_alone() -> void:
	## A phantom note is its own defect: the notes panel tells the player what the composer
	## CHANGED, so a note for an untouched rule is a lie about their own ruleset.
	var rules: Array = [_rule("poison")]
	var notes: Array = _rc()._normalise_member_status(rules)
	assert_eq(_statuses(rules), ["poison"], "an id the engine matches must not be rewritten")
	assert_eq(notes, [], "and must produce no note")


func test_a_word_nobody_authored_is_not_guessed_at() -> void:
	## The repair is a LOOKUP. Inventing a mapping here would teach the model a vocabulary
	## the engine does not have — the defect this whole branch exists to remove.
	var rules: Array = [_rule("bamboozled")]
	var notes: Array = _rc()._normalise_member_status(rules)
	assert_eq(_statuses(rules), ["bamboozled"], "an unknown word is left for the validator")
	assert_eq(notes, [], "and no repair is claimed")
	assert_eq(rules.size(), 1, "and nothing is split")


func test_the_mapping_is_the_prompts_own_table() -> void:
	## A second copy here would drift from the list the model is actually shown. Every
	## spelling the prompt advertises must be one the repair accepts.
	var rc = _rc()
	for id in DP.AUTOGRIND_STATUS_VOCABULARY.keys():
		for word in (DP.AUTOGRIND_STATUS_VOCABULARY[id] as Array):
			var rules: Array = [_rule(str(word))]
			rc._normalise_member_status(rules)
			assert_eq(_statuses(rules), [str(id)],
				"the prompt offers '%s' for '%s', so the repair must accept it" % [word, id])


func test_a_rule_without_member_status_is_untouched() -> void:
	## CONTROL on the scan: it must key on the condition type, not on any rule that has a
	## value it recognises.
	var other := {"conditions": [{"type": "member_hp", "op": "<", "value": 30}],
		"actions": [{"type": "heal_party"}]}
	var rules: Array = [other.duplicate(true)]
	var notes: Array = _rc()._normalise_member_status(rules)
	assert_eq(rules, [other], "a numeric condition must not be read as a status")
	assert_eq(notes, [], "and must produce no note")


# ── what the player actually loses, driven through the real path ──────────────

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


func _replay(reply: String) -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist")
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_backend = preload("res://tools/replay_backend.gd").new()
	_backend.name = "ReplayBE"
	_backend.next_text = reply
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend


func test_the_composition_survives_instead_of_being_discarded() -> void:
	## THE CONSEQUENCE ARM. One malformed value makes compose_async return
	## _fallback_result — the canned draft — so the player loses every rule they asked
	## for, not the one that carried the list. This is the 3-in-20.
	var rc = get_tree().root.get_node_or_null("RuleComposer")
	assert_not_null(rc, "CONTROL: RuleComposer autoload must exist")
	_replay(JSON.stringify({
		"name": "stop when hurt", "description": "d",
		"rules_json": JSON.stringify([_rule(["frozen", "poisoned"])]),
	}))
	var res: Dictionary = await rc.compose_async("autogrind", "stop if frozen or poisoned", "", [])
	assert_eq(str(res.get("source", "")), "llm",
		"the player's composition must survive: %s" % str(res.get("errors", [])))
	assert_eq(res.get("errors", []), [], "with no grammar errors left")
	assert_eq(_statuses(res.get("rules", [])), ["stun", "poison"],
		"and both statuses they asked for must be there")
	assert_gt((res.get("notes", []) as Array).size(), 0, "and the notes must say what changed")
