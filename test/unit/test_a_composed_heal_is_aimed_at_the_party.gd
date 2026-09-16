extends GutTest

## An ability action with no target key is sent at the LOWEST-HP ENEMY by the
## evaluator's default (AutobattleSystem._action_def_to_action), and
## _resolve_ability_targets only overrides that for all_allies / all_enemies /
## dead_ally — `single_ally` falls through. So a composed {"type":"ability","id":"cure"}
## with no target heals the thing you are fighting.
##
## Measured on the live evaluator, cleric + hurt ally (Bram 100/500) + enemy (Goblin
## 60/300): an untargeted cure resolved to ["Goblin"]; the same action aimed at
## lowest_hp_ally resolved to ["Bram"]. And 1 of 12 live llama3 cleric compositions
## emitted exactly the untargeted form.
##
## This guards the COMPOSER half — every composed heal leaves with an aim. The
## evaluator default itself is BattleManager/AutobattleSystem's, reported there with
## the measurement rather than changed from this lane.

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
	svc = root.get_node_or_null("LLMService")
	assert_not_null(rc, "CONTROL: RuleComposer must be reachable")
	assert_not_null(svc, "CONTROL: LLMService must be reachable")
	var abs_sys = root.get_node_or_null("AutobattleSystem")
	if abs_sys != null and "_test_disable_persistence" in abs_sys:
		_orig_persist = abs_sys._test_disable_persistence
		abs_sys._test_disable_persistence = true
	_orig_enabled = svc.llm_enabled
	svc.llm_enabled = true
	svc.cancel_all("untargeted-heal fixture isolation")
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


func _compose(rules_json: String, who: String, ask: String) -> Dictionary:
	fake_backend.prime_next(JSON.stringify({
		"name": "Measured", "description": "Replay of a real composition shape.",
		"rules_json": rules_json,
	}))
	return await rc.compose_async(rc.DOMAIN_AUTOBATTLE, ask, who, [])


func _targets_for(result: Dictionary, ability_id: String) -> Array:
	var out: Array = []
	for r in result.get("rules", []):
		for a in (r as Dictionary).get("actions", []):
			if str((a as Dictionary).get("id", "")) == ability_id:
				out.append(str((a as Dictionary).get("target", "<none>")))
	return out


## The shape a live cleric composition produced: cure, no target key.
const UNTARGETED_CURE := """[
 {"conditions":[{"type":"ally_hp_percent","op":"<","value":50},{"type":"mp_percent","op":">=","value":20}],"actions":[{"type":"ability","id":"cure"}],"enabled":true}
]"""


func test_a_composed_cure_leaves_with_an_ally_in_mind() -> void:
	var result: Dictionary = await _compose(UNTARGETED_CURE, "mira", "heal whoever is hurt worst")
	assert_eq(str(result.get("source", "")), "llm", "the composition must reach the player")
	assert_eq(_targets_for(result, "cure"), ["lowest_hp_ally"],
		"an untargeted heal must be aimed at the party — the evaluator's default sends it at the enemy")


func test_the_repair_says_it_aimed_the_heal() -> void:
	var result: Dictionary = await _compose(UNTARGETED_CURE, "mira", "heal whoever is hurt worst")
	var blob: String = "|".join(result.get("notes", []))
	assert_true(blob.find("Aimed 'cure' at lowest_hp_ally") != -1,
		"the player must be told their heal was aimed; got: %s" % blob)


func test_an_offensive_ability_is_left_to_the_engine_default() -> void:
	## The default is ALREADY an enemy. Writing a target here would be a second copy
	## of the engine's default — the shape that drifts (see restore_mp, heal_party).
	var untargeted_fire := """[
	 {"conditions":[{"type":"mp_percent","op":">=","value":20}],"actions":[{"type":"ability","id":"fire"}],"enabled":true}
	]"""
	var result: Dictionary = await _compose(untargeted_fire, "vex", "burn things")
	assert_eq(_targets_for(result, "fire"), ["<none>"],
		"an offensive ability must keep no target, so the engine default stays the single owner")


func test_an_aim_the_model_chose_is_not_overwritten() -> void:
	var self_cure := """[
	 {"conditions":[{"type":"hp_percent","op":"<","value":40},{"type":"mp_percent","op":">=","value":20}],"actions":[{"type":"ability","id":"cure","target":"self"}],"enabled":true}
	]"""
	var result: Dictionary = await _compose(self_cure, "mira", "heal myself when hurt")
	assert_eq(_targets_for(result, "cure"), ["self"],
		"a target the model DID choose must survive — the repair fills a gap, it does not judge")


func test_the_aim_comes_from_the_ability_not_from_a_list_here() -> void:
	## Anti-drift: the repair reads the ability's declared target_type. A copy in
	## RuleComposer (or in this test) would agree today and diverge the day an
	## ability is re-declared.
	var cure: Dictionary = JobSystem.get_ability("cure")
	assert_false(cure.is_empty(), "CONTROL: cure must resolve")
	assert_eq(str(cure.get("target_type", "")), "single_ally",
		"the repair is derived from this declaration — if it changed, the repair follows it")
	var src: String = FileAccess.get_file_as_string("res://src/llm/RuleComposer.gd")
	assert_true(src.find('get_ability(aid)') != -1,
		"the repair must ask the ability, not hold its own map of which ids are heals")


func test_a_revival_is_left_alone_for_the_engine_to_place() -> void:
	## `raise` declares dead_ally, which _resolve_ability_targets handles itself and
	## no script target can express. Aiming it here would break the one case the
	## engine already gets right.
	var raise_ab: Dictionary = JobSystem.get_ability("raise")
	if raise_ab.is_empty():
		pass_test("raise is not authored in this build")
		return
	assert_eq(str(raise_ab.get("target_type", "")), "dead_ally",
		"CONTROL: raise must still declare dead_ally, or this arm measures nothing")
	var rules: Array = [{"conditions": [{"type": "always"}], "actions": [{"type": "ability", "id": "raise"}]}]
	var notes: Array = rc._aim_untargeted_abilities(rules)
	assert_eq(notes.size(), 0, "a dead_ally ability must not be aimed by the composer")
	assert_false((rules[0]["actions"][0] as Dictionary).has("target"),
		"and it must be left with no target for the engine to place")


func test_every_ally_ability_is_aimed_not_a_hardcoded_few() -> void:
	## Same measured hole: code that calls get_ability() and then consults a hardcoded
	## list of "heals" satisfies the source arm. Drive the repair with EVERY ability that
	## DECLARES single_ally, read from the data.
	var abilities: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var root: Dictionary = (abilities as Dictionary).get("abilities", abilities)
	var checked: int = 0
	var unaimed: Array = []
	for aid in root:
		var ab: Variant = root[aid]
		if not (ab is Dictionary) or str((ab as Dictionary).get("target_type", "")) != "single_ally":
			continue
		checked += 1
		var rules: Array = [{"conditions": [{"type": "always"}],
			"actions": [{"type": "ability", "id": str(aid)}]}]
		rc._aim_untargeted_abilities(rules)
		if str((rules[0]["actions"][0] as Dictionary).get("target", "")) != "lowest_hp_ally":
			unaimed.append(str(aid))
	assert_gt(checked, 5, "CONTROL: several abilities must declare single_ally, or this measures nothing")
	assert_eq(unaimed, [],
		"every single_ally ability must be aimed at the party — these were left for the enemy default: %s"
			% str(unaimed))