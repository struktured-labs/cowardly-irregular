extends GutTest

## Item 13 fast-follow (cowir-ai + cowir-battle convergence, msgs 2075/2079):
## verifies RuleComposer.compose_async passes character_id through to
## AutobattleSystem.validate_rule so the LLM-emitted rules are deep-checked
## (unknown ability id, out-of-kit ability, mp-starve, unknown item id),
## and confirms the autogrind path stays shallow (1-arg, no character_id).

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
	if rc == null:
		rc = preload("res://src/llm/RuleComposer.gd").new()
		rc.name = "RuleComposer"
		root.add_child(rc)
	svc = root.get_node_or_null("LLMService")
	if svc == null:
		svc = preload("res://src/llm/LLMService.gd").new()
		svc.name = "LLMService"
		root.add_child(svc)
	assert_not_null(rc)
	assert_not_null(svc)
	_orig_enabled = svc.llm_enabled
	svc.llm_enabled = true
	svc.cancel_all("fizzle-deepcheck fixture isolation")
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

func _payload(rules_json: String) -> String:
	return JSON.stringify({
		"name": "fizzle_test",
		"description": "Deep-check regression coverage.",
		"rules_json": rules_json,
	})

func _error_blob(result: Dictionary) -> String:
	return "|".join(result.get("errors", []))

## ── Deep check catches hallucinated ability ─────────────────────────────

func test_deep_check_rejects_hallucinated_ability_id() -> void:
	watch_signals(rc)
	fake_backend.prime_next(_payload(
		"[{\"conditions\":[{\"type\":\"always\"}],\"actions\":[{\"type\":\"ability\",\"id\":\"summon_meteor_9000\",\"target\":\"lowest_hp_enemy\"}],\"enabled\":true}]"))
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "big flashy attack", "hero", [])
	assert_eq(result.get("source", ""), "fallback",
			  "hallucinated ability id must resolve to fallback via grammar_errors")
	assert_true("unknown ability" in _error_blob(result),
				"deep-check error must mention 'unknown ability'; got: %s" % _error_blob(result))
	assert_signal_emitted(rc, "composition_failed")

## ── Deep check catches out-of-kit ability ───────────────────────────────

func test_deep_check_rejects_out_of_kit_ability() -> void:
	watch_signals(rc)
	# 'cure' is a real ability but not in fighter's kit — must reject when character_id=hero.
	fake_backend.prime_next(_payload(
		"[{\"conditions\":[{\"type\":\"mp_percent\",\"op\":\">=\",\"value\":50}],\"actions\":[{\"type\":\"ability\",\"id\":\"cure\",\"target\":\"lowest_hp_ally\"}],\"enabled\":true}]"))
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "self-heal", "hero", [])
	assert_eq(result.get("source", ""), "fallback")
	assert_true("not in fighter's level-1 kit" in _error_blob(result),
				"deep-check error must name the kit-mismatch; got: %s" % _error_blob(result))

## ── the prompt actually receives the kit ────────────────────────────────

func test_the_composed_prompt_carries_the_characters_real_kit() -> void:
	## WIRING. build_rule_composition renders the kit block correctly when handed
	## one, but that proves nothing about whether compose_async hands it one — for
	## months it did not, while the grammar told the model to respect a kit it was
	## never shown. This reads the prompt the backend actually received.
	fake_backend.prime_next(_payload("[]"))
	await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "fight well", "hero", [])
	assert_true(fake_backend.last_prompt.find("THIS CHARACTER is a fighter") != -1,
				"the prompt sent to the model must name the character's job")
	assert_true(fake_backend.last_prompt.find("power_strike") != -1,
				"and list the ability ids it is allowed to use")


## ── mp-starve: DERIVABLE, so now repaired rather than discarded ─────────
##
## CONTRACT CHANGE 2026-09-10 (cowir-ai). This test asserted that an unguarded
## costed rule sends the whole composition to fallback. It now asserts the guard
## is supplied instead, because the threshold is arithmetic the validator already
## performs — its own error text names the number it was discarding the ruleset
## over. Measured against local llama3: the model omitted this guard in 20 of 29
## rejected rules even when handed the ability costs and the MP pool, which made
## it the single largest cause of the player receiving a canned fallback (cleric
## 0/10 -> 8/10, fighter 0/10 -> 5/10 once supplied).
##
## "Stricter = safer for LLM-composed output" is NOT relaxed by this: the repair
## only ever ADDS a precondition or raises an existing one, so a repaired rule
## fires strictly less often than the model asked for and can never fizzle. The
## rejection path below is unchanged for everything arithmetic cannot fix.

func test_unguarded_costed_rule_is_repaired_not_discarded() -> void:
	watch_signals(rc)
	# power_strike costs 8 MP and IS in the fighter's kit, so the guard is derivable.
	fake_backend.prime_next(_payload(
		"[{\"conditions\":[{\"type\":\"always\"}],\"actions\":[{\"type\":\"ability\",\"id\":\"power_strike\",\"target\":\"lowest_hp_enemy\"}],\"enabled\":true}]"))
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "hit hard every turn", "hero", [])
	assert_eq(result.get("source", ""), "llm",
				"a derivable guard must be supplied, not cost the player the whole ruleset")
	var guarded: bool = false
	for r in result.get("rules", []):
		for c in r.get("conditions", []):
			if str(c.get("type", "")) == "mp_percent" and str(c.get("op", "")) == ">=":
				guarded = true
	assert_true(guarded, "the supplied rule must carry the mp_percent guard it needed")


func test_unguarded_rule_the_arithmetic_cannot_fix_is_still_rejected() -> void:
	## The fizzle protection must survive the repair. 'cure' is not in the fighter's
	## kit, so supplying a guard would dress a rule that still cannot run — the
	## repair deliberately leaves it alone and the deep check still discards it.
	watch_signals(rc)
	fake_backend.prime_next(_payload(
		"[{\"conditions\":[{\"type\":\"always\"}],\"actions\":[{\"type\":\"ability\",\"id\":\"cure\",\"target\":\"lowest_hp_ally\"}],\"enabled\":true}]"))
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "heal up", "hero", [])
	assert_eq(result.get("source", ""), "fallback",
				"an out-of-kit ability must still discard the composition")
	assert_true("not in fighter's level-1 kit" in _error_blob(result),
				"and for the kit reason, not a masked fizzle; got: %s" % _error_blob(result))

## ── Deep check accepts a well-formed guarded costed rule ────────────────

func test_deep_check_accepts_guarded_costed_rule() -> void:
	watch_signals(rc)
	# 'fire' costs 8 MP on mage (vex); 15% guard on 80 MP pool = 12 MP available → covers cost.
	fake_backend.prime_next(_payload(
		"[{\"conditions\":[{\"type\":\"mp_percent\",\"op\":\">=\",\"value\":15}],\"actions\":[{\"type\":\"ability\",\"id\":\"fire\",\"target\":\"lowest_magic_defense_enemy\"}],\"enabled\":true}]"))
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOBATTLE, "cast fire when I have juice", "vex", [])
	assert_eq(result.get("source", ""), "llm",
			  "well-formed guarded rule must pass deep check; errors: %s" % _error_blob(result))
	assert_signal_emitted(rc, "composition_ready")

## ── Autogrind path stays shallow (regression) ───────────────────────────

func test_autogrind_domain_does_not_deep_check() -> void:
	# A grammar-valid autogrind rule uses party-level verbs; validate_rule
	# 1-arg must accept it. If autogrind path silently deep-checked with an
	# empty character_id, we'd get 'deep check unavailable' and take fallback.
	watch_signals(rc)
	fake_backend.prime_next(_payload(
		"[{\"conditions\":[{\"type\":\"party_hp_avg\",\"op\":\"<\",\"value\":40}],\"actions\":[{\"type\":\"heal_party\"}],\"enabled\":true}]"))
	var result: Dictionary = await rc.compose_async(rc.DOMAIN_AUTOGRIND, "heal the party when low", "", [])
	assert_eq(result.get("source", ""), "llm",
			  "autogrind valid rule must pass shallow-only; errors: %s" % _error_blob(result))
	assert_signal_emitted(rc, "composition_ready")
