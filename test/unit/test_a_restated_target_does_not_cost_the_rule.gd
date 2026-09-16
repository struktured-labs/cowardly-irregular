extends GutTest

## The model writes a TARGET name where a CONDITION type goes —
## {"type":"lowest_hp_enemy"} sitting beside an action that already aims there.
##
## It is not a condition type, so the whole rule was dropped as unrunnable, and in the
## measured case that rule was the player's actual request. Live llama3, 12 real
## fighter compositions replayed through the shipped chain: 2 reached the player as a
## one-rule script with the attack line gone. With this repair the same 12 keep it
## (rules per composition 1,2,1,... -> 2,2,2,...), and nothing else in the set moved.
##
## The repair is deliberately narrow, because dropping a condition makes a rule fire
## MORE often: the type must be a live TARGET_TYPES key, an action in that same rule
## must already aim there, and a non-`always` condition must survive.

const FakeBackendScript := preload("res://test/unit/test_llm_fake_backend.gd")

var rc
var svc
var fake_backend: FakeBackendScript.FakeBackend
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true
var _orig_persist: bool = false


func before_each() -> void:
	var root := get_tree().root
	rc = root.get_node_or_null("RuleComposer")
	if rc == null:
		rc = preload("res://src/llm/RuleComposer.gd").new()
		rc.name = "RuleComposer"
		root.add_child(rc)
	svc = root.get_node_or_null("LLMService")
	assert_not_null(rc, "CONTROL: RuleComposer must be reachable")
	assert_not_null(svc, "CONTROL: LLMService must be reachable")
	var abs_sys = root.get_node_or_null("AutobattleSystem")
	if abs_sys != null and "_test_disable_persistence" in abs_sys:
		_orig_persist = abs_sys._test_disable_persistence
		abs_sys._test_disable_persistence = true
	_orig_enabled = svc.llm_enabled
	svc.llm_enabled = true
	svc.cancel_all("restated-target fixture isolation")
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
	var abs_sys = get_tree().root.get_node_or_null("AutobattleSystem")
	if abs_sys != null and "_test_disable_persistence" in abs_sys:
		abs_sys._test_disable_persistence = _orig_persist


func _payload(rules_json: String) -> String:
	return JSON.stringify({
		"name": "Measured",
		"description": "Replay of a real composition shape.",
		"rules_json": rules_json,
	})


func _compose(rules_json: String) -> Dictionary:
	fake_backend.prime_next(_payload(rules_json))
	return await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "attack the weakest enemy", "hero", [])


## The exact shape llama3 produced, twice in twelve.
const REAL_SHAPE := """[
 {"conditions":[{"type":"ally_hp_percent","op":"<","value":30}],"actions":[{"type":"item","id":"potion","target":"self"}],"enabled":true},
 {"conditions":[{"type":"lowest_hp_enemy"},{"type":"mp_percent","op":">=","value":30}],"actions":[{"type":"attack","target":"lowest_hp_enemy"}],"enabled":true}
]"""


func test_the_players_attack_rule_survives_a_restated_target() -> void:
	var result: Dictionary = await _compose(REAL_SHAPE)
	assert_eq(str(result.get("source", "")), "llm",
		"the composition must reach the player, not the canned fallback")
	assert_eq((result.get("rules", []) as Array).size(), 2,
		"both rules must survive — the attack rule is what the player asked for")
	var aimed: bool = false
	for r in result.get("rules", []):
		for a in (r as Dictionary).get("actions", []):
			if str((a as Dictionary).get("type", "")) == "attack":
				aimed = true
	assert_true(aimed, "the surviving set must still contain the attack")


func test_the_repair_says_what_it_did() -> void:
	var result: Dictionary = await _compose(REAL_SHAPE)
	## Matching only "lowest_hp_enemy" was a WEAK arm: the pre-fix drop note names the
	## same id, so it stayed green under the mutation that removes this repair
	## (measured). The note must be THIS repair's, and it must name the id it removed.
	var blob: String = "|".join(result.get("notes", []))
	assert_true(blob.find("it is a target, and the rule already aims there") != -1,
		"a silent edit is what this codebase calls a defect — the note must say what was done; got: %s" % blob)
	assert_true(blob.find("lowest_hp_enemy") != -1,
		"and it must name the condition it dropped; got: %s" % blob)


func test_the_real_condition_still_gates_the_rule() -> void:
	## The repair must remove ONLY the restatement. If it took the mp gate too, the
	## rule would fire in states the player excluded.
	var result: Dictionary = await _compose(REAL_SHAPE)
	var found_gate: bool = false
	for r in result.get("rules", []):
		for c in (r as Dictionary).get("conditions", []):
			if str((c as Dictionary).get("type", "")) == "mp_percent":
				found_gate = true
	assert_true(found_gate, "the mp_percent condition must survive the repair")


func test_a_gated_rule_never_becomes_a_catch_all() -> void:
	## Only `always` would remain here, so the repair must decline and leave the rule
	## to the existing drop path. Rescuing it would turn a gated rule into one that
	## fires every turn — a worse outcome than losing it.
	var only_always := """[
	 {"conditions":[{"type":"ally_hp_percent","op":"<","value":30}],"actions":[{"type":"item","id":"potion","target":"self"}],"enabled":true},
	 {"conditions":[{"type":"lowest_hp_enemy"},{"type":"always"}],"actions":[{"type":"attack","target":"lowest_hp_enemy"}],"enabled":true}
	]"""
	var result: Dictionary = await _compose(only_always)
	for r in result.get("rules", []):
		for c in (r as Dictionary).get("conditions", []):
			assert_ne(str((c as Dictionary).get("type", "")), "lowest_hp_enemy",
				"a rescued rule must never be one whose only surviving condition is 'always'")
	var blob: String = "|".join(result.get("notes", []))
	assert_eq(blob.find("it is a target, and the rule already aims there"), -1,
		"the repair must not claim this one; got: %s" % blob)


func test_a_target_the_rule_does_not_aim_at_is_left_alone() -> void:
	## Without the action aiming there, the condition is not evidently a restatement —
	## it could be lost intent, and inventing a reading is worse than dropping.
	var mismatched := """[
	 {"conditions":[{"type":"ally_hp_percent","op":"<","value":30}],"actions":[{"type":"item","id":"potion","target":"self"}],"enabled":true},
	 {"conditions":[{"type":"highest_hp_enemy"},{"type":"mp_percent","op":">=","value":30}],"actions":[{"type":"attack","target":"lowest_hp_enemy"}],"enabled":true}
	]"""
	var result: Dictionary = await _compose(mismatched)
	var blob: String = "|".join(result.get("notes", []))
	assert_eq(blob.find("highest_hp_enemy' from a rule's conditions"), -1,
		"a target the rule does not aim at must not be silently dropped; got: %s" % blob)


func test_the_vocabulary_is_the_live_one_not_a_copy() -> void:
	## Anti-drift: the repair reads AutobattleSystem.TARGET_TYPES. A second copy here
	## would agree today and diverge the day a target is added.
	var abs_sys = get_tree().root.get_node_or_null("AutobattleSystem")
	assert_not_null(abs_sys, "CONTROL: AutobattleSystem must be reachable")
	assert_true("TARGET_TYPES" in abs_sys, "CONTROL: the target vocabulary must live on the system")
	assert_true((abs_sys.TARGET_TYPES as Dictionary).has("lowest_hp_enemy"),
		"the shape this repair was measured against must still be a real target")
	var src: String = FileAccess.get_file_as_string("res://src/llm/RuleComposer.gd")
	assert_true(src.find("domain_system.TARGET_TYPES") != -1,
		"the repair must read the live vocabulary rather than hold its own list")


func test_without_a_system_the_repair_does_nothing() -> void:
	## Headless / no autoload: it must return empty rather than guess a vocabulary.
	var rules: Array = [{"conditions": [{"type": "lowest_hp_enemy"}], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}]}]
	var notes: Array = rc._drop_target_shaped_conditions(rules, null)
	assert_eq(notes.size(), 0, "no system means no repair")
	assert_eq((rules[0]["conditions"] as Array).size(), 1, "and the rule is left untouched")
