extends GutTest

## The bench re-implemented the composer, and twice published a wrong number.
##
## tools/rule_composition_validate.gd scores captured model replies by calling the
## guard, the validator and the repair functions itself, in an order it has to
## keep in step with compose_async BY HAND. That drifted twice:
##
##   hour 24  scored a shape the game never sees — the contract nests the rule
##            list inside rules_json — and called a correctly-encoded reply a
##            parse failure, reporting "9 of 11 rules valid" for a pipeline that
##            was delivering 0 of 20 compositions
##   hour 30  called a repair function that did not exist on the branch under
##            measurement, which aborted the script; godot then hung to timeout
##            and the bench file read back was the PREVIOUS run's output
##
## Both produced confident, plausible numbers. tools/replay_backend.gd removes
## the second opinion: it satisfies LLMBackend by holding one string and handing
## it back, so measurement drives LLMService.complete_json and
## RuleComposer.compose_async and takes compose_async's own verdict.
##
## Cross-checked before shipping — the two benches agree on three real corpora
## (cleric 9/12, fighter 2/12, and a deliberately mismatched kit 0/12). Agreement
## is what makes the replacement safe; the point is that only ONE of them can
## drift from here.
##
## This file guards the mechanism the tool depends on, so a change to the backend
## interface fails here rather than silently in a measurement nobody re-checks.

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
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist")
	assert_not_null(_rc, "CONTROL: RuleComposer autoload must exist")
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_backend = ReplayBackend.new()
	_backend.name = "ReplayBE"
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_backend.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _backend


func after_each() -> void:
	if _backend and is_instance_valid(_backend):
		_backend.request_finished.disconnect(_svc._on_backend_finished)
		_svc.remove_child(_backend)
		_backend.free()
	_svc._backends.clear()
	for b in _orig_backends:
		_svc._backends.append(b)
	_svc._active_backend = _orig_active
	_svc.llm_enabled = _orig_enabled


func _payload(rules_json: String) -> String:
	return JSON.stringify({"name": "n", "description": "d", "rules_json": rules_json})


# ── the backend satisfies the contract LLMService drives ──────────────────────

func test_it_reports_itself_ready_and_json_capable() -> void:
	## LLMService refuses a backend that is not ready, and routes JSON mode only to
	## one that claims to support it. A bench whose backend quietly failed either
	## check would measure fallbacks and call them model failures.
	assert_true(_backend.is_ready(), "must be ready or complete_json returns the fallback")
	assert_true(_backend.supports_json(), "must accept JSON mode")
	assert_eq(_backend.backend_id(), "replay", "must be identifiable in logs")


func test_it_answers_asynchronously() -> void:
	## submit() defers its reply. Emitting inside submit() would fire before the
	## caller is awaiting and the request would hang — the failure mode is a
	## timeout, which reads as a slow model rather than a broken harness.
	var got: Array = []
	_backend.request_finished.connect(func(_i, ok, text, _e): got.append([ok, text]))
	_backend.next_text = "hello"
	_backend.submit("req1", "prompt")
	assert_eq(got.size(), 0, "must not have answered synchronously")
	await get_tree().process_frame
	assert_eq(got.size(), 1, "must answer on a later frame")
	assert_eq(str((got[0] as Array)[1]), "hello", "and hand back exactly what it was given")


# ── it drives the real path end to end ────────────────────────────────────────

func test_a_valid_reply_reaches_the_player_through_compose_async() -> void:
	_backend.next_text = _payload(
		'[{"conditions":[{"type":"always"}],"actions":[{"type":"attack","target":"lowest_hp_enemy"}],"enabled":true}]')
	var res: Dictionary = await _rc.compose_async(_rc.DOMAIN_AUTOBATTLE, "just attack", "hero", [])
	assert_eq(str(res.get("source", "")), "llm",
		"a valid reply must come back as an llm composition, not a fallback")
	assert_eq((res.get("rules", []) as Array).size(), 1, "carrying the rule it described")


func test_a_rejected_reply_comes_back_as_a_fallback_with_its_reason() -> void:
	## The other verdict the bench counts. If this ever stopped reporting errors,
	## the bench would show fallbacks with no cause and look like a model problem.
	_backend.next_text = _payload(
		'[{"conditions":[{"type":"always"}],"actions":[{"type":"attack","target":"weakest_enemy"}],"enabled":true}]')
	var res: Dictionary = await _rc.compose_async(_rc.DOMAIN_AUTOBATTLE, "attack", "hero", [])
	assert_eq(str(res.get("source", "")), "fallback", "an invalid target must not reach the player")
	assert_true(", ".join(res.get("errors", [])).find("weakest_enemy") != -1,
		"and the reason must be reported, or the bench counts a loss with no cause")


func test_the_verdict_distinguishes_the_two_outcomes() -> void:
	## CONTROL for the whole instrument: it must be able to return BOTH answers.
	## A bench that always said "fallback" would have agreed with the old scorer on
	## the fighter corpus and been useless.
	_backend.next_text = _payload('[{"conditions":[{"type":"always"}],"actions":[{"type":"attack"}],"enabled":true}]')
	var good: Dictionary = await _rc.compose_async(_rc.DOMAIN_AUTOBATTLE, "a", "hero", [])
	_backend.next_text = "this is not JSON at all"
	var bad: Dictionary = await _rc.compose_async(_rc.DOMAIN_AUTOBATTLE, "a", "hero", [])
	assert_eq(str(good.get("source", "")), "llm", "the good reply must be llm")
	assert_eq(str(bad.get("source", "")), "fallback", "the unparseable reply must be fallback")


func test_unparseable_text_does_not_crash_the_run() -> void:
	## A bench walks a whole corpus; one bad file must not abort the sweep — that
	## is exactly how the hour-30 stale-output failure happened.
	_backend.next_text = ""
	var res: Dictionary = await _rc.compose_async(_rc.DOMAIN_AUTOBATTLE, "a", "hero", [])
	assert_eq(str(res.get("source", "")), "fallback", "an empty reply must fall back cleanly")
