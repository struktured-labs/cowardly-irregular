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


# ── and the CONSUMER must never hand it an empty READ ─────────────────────────
#
# The arm above is the hazard, not a licence: an empty string scores as a fallback,
# so a capture file that cannot be READ is indistinguishable from a reply the model
# genuinely botched. FileAccess.get_file_as_string returns "" on failure and
# ReplayBackend emits it as a SUCCESSFUL reply, so the tool inflates the exact rate
# it exists to measure, one unreadable file at a time, silently.

const COMPOSE_TOOL := "res://tools/rule_composition_compose.gd"


## Source with comment lines removed — prose naming a guard must not satisfy a check for it.
func _tool_code() -> String:
	var raw: String = FileAccess.get_file_as_string(COMPOSE_TOOL)
	var keep: PackedStringArray = PackedStringArray()
	for line in raw.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		keep.append(line)
	return "\n".join(keep)


func test_the_scoring_tool_is_actually_read() -> void:
	## FLOOR, per-source and inside nothing: the three arms below all derive from one file,
	## and a moved or renamed tool would make every one of them pass over an empty string.
	assert_gt(FileAccess.get_file_as_string(COMPOSE_TOOL).length(), 1000,
		"CONTROL: %s must actually be read, or the arms below assert over ''" % COMPOSE_TOOL)


func test_an_unreadable_capture_leaves_the_scored_population() -> void:
	## The empty check must come BEFORE the assignment — a guard after it has already
	## paid the cost. Order is the invariant here, not the presence of a token.
	var code: String = _tool_code()
	var assign: int = code.find("backend.next_text = captured")
	var guard: int = code.find("captured == \"\"")
	assert_gt(assign, -1, "the tool must assign the capture through a named local")
	assert_gt(guard, -1, "the tool must test that capture for emptiness")
	assert_lt(guard, assign, "the emptiness check must precede the assignment, or it guards nothing")
	assert_gt(code.find("unreadable"), -1,
		"an excluded file must be reported, not dropped in silence")


func test_the_rate_denominator_is_what_was_scored() -> void:
	## A denominator counting files nobody could read reports a plausible, specific,
	## wrong fallback rate — the same wrong-population error the old bench made twice.
	var code: String = _tool_code()
	assert_gt(code.find("var scored: int = reached + fallback"), -1,
		"the tool must derive a scored population distinct from the file count")
	## Anchor on the OPERAND LIST, which occurs once each. Two earlier spellings were dead:
	## a literal spanning the whole format string baked in the prose between `%d/%d` and the
	## operands, and "REACHES THE PLAYER" finds the PER-FILE line before the summary one.
	for operand in ["[reached, ", "[fallback, "]:
		var at: int = code.find(operand)
		assert_gt(at, -1, "the tool must still report a `%s` rate" % operand)
		var line: String = code.substr(at, code.find("\n", at) - at)
		assert_gt(line.find("scored]"), -1,
			"`%s` must be reported over `scored`, got: %s" % [operand, line.strip_edges()])
		assert_eq(line.find("names.size()"), -1,
			"`%s` must NOT be reported over the files on disk: %s" % [operand, line.strip_edges()])


func test_a_corpus_that_went_entirely_dark_is_refused() -> void:
	## scored == 0 makes every rate 0/0, which prints as clean. The floor @cowir-controller's
	## three-way control names: a corpus member can go dark and take its own defect with it,
	## and the whole corpus going dark must be louder than a green, not quieter.
	var code: String = _tool_code()
	assert_gt(code.find("scored == 0 and names.size() > 0"), -1,
		"the tool must refuse to publish a rate derived from zero scored captures")
