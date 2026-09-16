extends GutTest

## Autogrind has no per-rule rescue — one bad rule and the WHOLE composition falls back
## to the canned draft — so a near-miss condition name is a total loss.
##
## Measured on 24 live llama3 autogrind compositions replayed through the shipped chain:
##
##   party_corruption                       2 of 24, each the composition's ONLY rule
##   {"type":"always","op":"","value":""}   1 of 24, beside two perfectly valid rules
##   accepted before 21/24 · after 24/24
##
## Both repairs are normalisations read from AutogrindSystem's own vocabulary, not a
## table of guesses kept in this lane: the `party_` prefix is stripped ONLY when the
## remainder is itself a live condition type, and an empty payload key is erased ONLY
## from a condition the system lists as taking no payload.

const FakeBackendScript := preload("res://test/unit/test_llm_fake_backend.gd")

var rc
var svc
var fake_backend: FakeBackendScript.FakeBackend
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


func before_each() -> void:
	var root := get_tree().root
	rc = root.get_node_or_null("RuleComposer")
	svc = root.get_node_or_null("LLMService")
	assert_not_null(rc, "CONTROL: RuleComposer must be reachable")
	assert_not_null(svc, "CONTROL: LLMService must be reachable")
	_orig_enabled = svc.llm_enabled
	svc.llm_enabled = true
	svc.cancel_all("autogrind near-miss fixture isolation")
	fake_backend = FakeBackendScript.FakeBackend.new()
	fake_backend.name = "FakeBE"
	_orig_backends = svc._backends.duplicate()
	_orig_active = svc._active_backend
	svc.add_child(fake_backend)
	svc._backends.clear()
	svc._backends.append(fake_backend)
	fake_backend.request_finished.connect(svc._on_backend_finished)
	svc._active_backend = fake_backend


func after_each() -> void:
	if fake_backend and is_instance_valid(fake_backend):
		fake_backend.request_finished.disconnect(svc._on_backend_finished)
		svc._backends.clear()
		for b in _orig_backends:
			svc._backends.append(b)
		svc._active_backend = _orig_active
		svc.remove_child(fake_backend)
		fake_backend.free()
	if svc != null:
		svc.llm_enabled = _orig_enabled


func _compose(rules_json: String) -> Dictionary:
	fake_backend.prime_next(JSON.stringify({
		"name": "Measured", "description": "Replay of a real grind composition.",
		"rules_json": rules_json,
	}))
	return await rc.compose_async(rc.DOMAIN_AUTOGRIND, "stop if the party is in trouble", "", [])


func _condition_types(result: Dictionary) -> Array:
	var out: Array = []
	for r in result.get("rules", []):
		for c in (r as Dictionary).get("conditions", []):
			out.append(str((c as Dictionary).get("type", "")))
	return out


## The exact shape llama3 produced, twice in twenty-four, as the only rule each time.
const PARTY_CORRUPTION := """[
 {"conditions":[{"type":"party_corruption","op":">=","value":50}],"actions":[{"type":"stop_grinding"}],"enabled":true}
]"""

## And the other one: `always` carrying an empty payload it is not allowed to have.
const EMPTY_PAYLOAD := """[
 {"conditions":[{"type":"party_hp_min","op":"<","value":30}],"actions":[{"type":"heal_party"}],"enabled":true},
 {"conditions":[{"type":"always","op":"","value":""}],"actions":[{"type":"stop_grinding"}],"enabled":true}
]"""


func test_a_near_miss_name_is_read_as_the_condition_it_meant() -> void:
	var result: Dictionary = await _compose(PARTY_CORRUPTION)
	assert_eq(str(result.get("source", "")), "llm",
		"the grind ruleset must reach the player, not the canned draft")
	assert_true("corruption" in _condition_types(result),
		"party_corruption must be read as corruption; got %s" % str(_condition_types(result)))


func test_the_player_is_told_it_was_read_differently() -> void:
	var result: Dictionary = await _compose(PARTY_CORRUPTION)
	var blob: String = "|".join(result.get("notes", []))
	assert_true(blob.find("Read 'party_corruption' as 'corruption'") != -1,
		"a silent rename is worse than a refusal — the note must name both; got: %s" % blob)


func test_an_invented_name_is_still_refused() -> void:
	## The prefix is stripped ONLY when what remains is a real condition. Otherwise this
	## would launder any `party_*` the model invents into a rule that cannot fire.
	var invented := """[
	 {"conditions":[{"type":"party_morale","op":">=","value":50}],"actions":[{"type":"stop_grinding"}],"enabled":true}
	]"""
	var result: Dictionary = await _compose(invented)
	assert_eq(str(result.get("source", "")), "fallback",
		"party_morale is not a condition with or without its prefix — it must still be refused")
	## The end-to-end half above is NOT enough, measured: with the validity check removed,
	## `party_morale` becomes `morale`, which is also not a condition, so the composition
	## still falls back — and a fallback carries NO notes, so a note assertion here passes
	## vacuously. The repair has to be asked directly.
	var rules: Array = [{"conditions": [{"type": "party_morale", "op": ">=", "value": 50}], "actions": [{"type": "stop_grinding"}]}]
	var sys = get_tree().root.get_node_or_null("AutogrindSystem")
	var notes: Array = rc._normalise_autogrind_conditions(rules, sys)
	assert_eq(notes.size(), 0, "nothing may claim to have read an invented name; got %s" % str(notes))
	assert_eq(str((rules[0]["conditions"][0] as Dictionary)["type"]), "party_morale",
		"and the type must be left exactly as written, not stripped to something equally unreal")


func test_a_real_party_prefixed_condition_is_untouched() -> void:
	## party_hp_min IS the live name. Stripping it would break a correct rule.
	var result: Dictionary = await _compose(EMPTY_PAYLOAD)
	assert_true("party_hp_min" in _condition_types(result),
		"a condition whose real name starts with party_ must survive intact; got %s" % str(_condition_types(result)))


func test_an_empty_payload_on_a_nullary_condition_is_dropped() -> void:
	var result: Dictionary = await _compose(EMPTY_PAYLOAD)
	assert_eq(str(result.get("source", "")), "llm",
		"two valid rules must not be lost to an empty op on the third")
	for r in result.get("rules", []):
		for c in (r as Dictionary).get("conditions", []):
			if str((c as Dictionary).get("type", "")) == "always":
				assert_false((c as Dictionary).has("op"), "the empty op must be gone")
				assert_false((c as Dictionary).has("value"), "and the empty value with it")


func test_a_payload_that_is_not_empty_is_left_to_the_validator() -> void:
	## Erasing a NON-empty payload would be editing what the rule asks, not normalising
	## how it is written. An `always` carrying a real operator is the validator's to refuse.
	var rules: Array = [{"conditions": [{"type": "always", "op": ">=", "value": 5}], "actions": [{"type": "stop_grinding"}]}]
	var sys = get_tree().root.get_node_or_null("AutogrindSystem")
	var notes: Array = rc._normalise_autogrind_conditions(rules, sys)
	assert_eq(notes.size(), 0, "nothing may be normalised here")
	assert_true((rules[0]["conditions"][0] as Dictionary).has("op"), "the real operator must survive")


func test_the_vocabulary_is_the_live_one_not_a_copy() -> void:
	var sys = get_tree().root.get_node_or_null("AutogrindSystem")
	assert_not_null(sys, "CONTROL: AutogrindSystem must be reachable")
	assert_true("PARTY_CONDITION_TYPES" in sys, "CONTROL: the vocabulary must live on the system")
	assert_true((sys.PARTY_CONDITION_TYPES as Dictionary).has("corruption"),
		"corruption must still be the real name this repair maps onto")
	assert_false((sys.PARTY_CONDITION_TYPES as Dictionary).has("party_corruption"),
		"and party_corruption must still NOT be one, or this repair is measuring nothing")
	var src: String = FileAccess.get_file_as_string("res://src/llm/RuleComposer.gd")
	assert_true(src.find("domain_system.PARTY_CONDITION_TYPES") != -1,
		"the repair must read the live vocabulary rather than hold its own list")


func test_without_a_system_nothing_is_normalised() -> void:
	var rules: Array = [{"conditions": [{"type": "party_corruption", "op": ">=", "value": 50}], "actions": [{"type": "stop_grinding"}]}]
	var notes: Array = rc._normalise_autogrind_conditions(rules, null)
	assert_eq(notes.size(), 0, "no system means no repair")
	assert_eq(str((rules[0]["conditions"][0] as Dictionary)["type"]), "party_corruption",
		"and the rule is left exactly as the model wrote it")


func test_every_live_condition_name_is_handled_not_a_hardcoded_few() -> void:
	## Same measured hole as the target repair (@cowir-sprites' mutation 7 shape): code
	## that READS PARTY_CONDITION_TYPES and then uses a hardcoded short list satisfies the
	## source arm above. Drive it with EVERY condition the system declares instead.
	var sys = get_tree().root.get_node_or_null("AutogrindSystem")
	assert_not_null(sys, "CONTROL: AutogrindSystem must be reachable")
	var types: Dictionary = sys.PARTY_CONDITION_TYPES
	assert_gt(types.size(), 10, "CONTROL: the vocabulary must be non-trivial")
	var unhandled: Array = []
	for name in types:
		var t: String = str(name)
		if t.begins_with("party_"):
			continue  # already the real name; prefixing it again is not a near miss
		var rules: Array = [{"conditions": [{"type": "party_" + t, "op": ">=", "value": 1}],
			"actions": [{"type": "stop_grinding"}]}]
		var notes: Array = rc._normalise_autogrind_conditions(rules, sys)
		if notes.is_empty() or str((rules[0]["conditions"][0] as Dictionary)["type"]) != t:
			unhandled.append(t)
	assert_eq(unhandled, [],
		"a party_-prefixed near miss must resolve for every declared condition — these did not: %s"
			% str(unhandled))