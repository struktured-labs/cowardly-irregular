extends GutTest

## Two defects in complete_json, found by asking which entry point a test reaches.
##
## ONE — `supports_json()` was declared on LLMBackend, implemented by every
## concrete backend, and read by NOTHING. NullBackend is registered LAST as the
## guaranteed fallback with `is_ready()` always true, so it becomes the active
## backend whenever no real one is ready, and it declares
## `supports_json() == false`. complete_json checked is_ready() only, so with the
## LLM enabled and no server every JSON call did a full round-trip to a backend
## that had already declared it could not answer, and reported (measured, not
## assumed):
##
##     before   inference_failed(MODE_JSON, "request failed or cancelled")
##     after    inference_failed(MODE_JSON, "backend cannot produce JSON")
##
## The old reason is not a lie, it is the wrong KIND of cause: it reads as
## transient — a timeout, a dropped connection, something a retry might fix —
## when the real state is that nothing configured can ever serve this call.
## GameLoop latches the FIRST inference_failed as its developer-facing
## breadcrumb, so that distinction is the whole diagnostic.
##
## TWO — line 334 read `if guarded == fallback:`. `fallback` is typed Variant and
## `_guard_json` returns a Dictionary on success, so a caller passing a String
## fallback hit `Dictionary == String`, which is a GDScript ERROR. The error
## ABORTS complete_json, and an aborted `-> Variant` function returns its type
## default: null. The SUCCESS path destroyed the successful result, and the
## contract in the docstring — "Returns `fallback` on any failure" — was false
## for every non-Dictionary, non-null fallback.
##
## Nothing caught it because a GDScript error does not fail a GUT test, and all
## eight production fallbacks are Dictionaries (RebalanceDaemon passes null;
## `Dictionary == null` is false, not an error). So no caller had yet used the
## range the signature advertises. This test is the first, which is how it
## surfaced — the defect is latent, not player-facing, and is recorded as such.

var _svc = null
var _be = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


class NoJSONBackend extends LLMBackend:
	var submitted: int = 0
	func backend_id() -> String: return "nojson"
	func is_ready() -> bool: return true
	func supports_json() -> bool: return false
	func submit(id: String, _p: String, _o: Dictionary = {}) -> void:
		submitted += 1
		_emit.call_deferred(id)
	func _emit(id: String) -> void:
		request_finished.emit(id, true, "not json at all", "")


class YesJSONBackend extends LLMBackend:
	var submitted: int = 0
	func backend_id() -> String: return "yesjson"
	func is_ready() -> bool: return true
	func supports_json() -> bool: return true
	func submit(id: String, _p: String, _o: Dictionary = {}) -> void:
		submitted += 1
		_emit.call_deferred(id)
	func _emit(id: String) -> void:
		request_finished.emit(id, true, '{"line":"ok"}', "")


## Capable, but answers with something the schema guard must reject.
class BadJSONBackend extends LLMBackend:
	var submitted: int = 0
	func backend_id() -> String: return "badjson"
	func is_ready() -> bool: return true
	func supports_json() -> bool: return true
	func submit(id: String, _p: String, _o: Dictionary = {}) -> void:
		submitted += 1
		_emit.call_deferred(id)
	func _emit(id: String) -> void:
		request_finished.emit(id, true, "absolutely not json", "")


## Uses the REAL LLMService autoload — a bare .new() lacks the request machinery
## _ready() sets up, and every call falls back without ever reaching a backend.
func _install(be) -> void:
	_be = be
	_be.name = "TestBE"
	_svc.add_child(_be)
	_svc._backends.clear()
	_svc._backends.append(_be)
	_be.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _be


func before_each() -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist")
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_svc.cancel_all("json-capability fixture isolation")


func after_each() -> void:
	if _be and is_instance_valid(_be):
		_be.request_finished.disconnect(_svc._on_backend_finished)
		_svc.remove_child(_be)
		_be.free()
		_be = null
	_svc._backends.clear()
	for b in _orig_backends:
		_svc._backends.append(b)
	_svc._active_backend = _orig_active
	_svc.llm_enabled = _orig_enabled


# ── defect one: the declared capability is consulted ───────────────────────────

func test_a_backend_that_cannot_do_json_is_not_asked() -> void:
	_install(NoJSONBackend.new())
	var got: Variant = await _svc.complete_json("p", {"line": "String"}, {"line": "fb"})
	assert_eq(_be.submitted, 0,
		"the request must NOT be sent to a backend that declared it cannot answer it")
	assert_true(got is Dictionary, "and the fallback must come back")


func test_the_reported_reason_names_a_permanent_cause_not_a_transient_one() -> void:
	## THE POINT. "request failed or cancelled" reads as a retryable blip; the
	## real state is that no configured backend can ever serve this call.
	_install(NoJSONBackend.new())
	var reasons: Array = []
	_svc.inference_failed.connect(func(_m, r): reasons.append(str(r)))
	await _svc.complete_json("p", {"line": "String"}, {"line": "fb"})
	assert_eq(reasons.size(), 1, "exactly one failure must be reported")
	assert_true(str(reasons[0]).find("cannot produce JSON") != -1,
		"the reason must name the backend's capability, got: %s" % str(reasons[0]))
	assert_eq(str(reasons[0]).find("rejected"), -1,
		"and must not blame the guard for output nothing should have requested — this fixture's pre-fix reason; the real NullBackend's was 'request failed or cancelled'")


func test_the_capability_default_fails_closed() -> void:
	## LLMBackend.supports_json() defaults to FALSE, so a backend that forgets to
	## declare is refused rather than sent a request it may not handle. Pinning
	## the default because the gate's safety depends on which way it points.
	var base := LLMBackend.new()
	autofree(base)
	assert_false(base.supports_json(),
		"the interface default must be false — the gate fails closed on an undeclared backend")


# ── defect two: the contract holds for every fallback type ────────────────────

func test_a_successful_reply_survives_a_string_fallback() -> void:
	## THE ABORT. guarded is a Dictionary, fallback is a String; `==` on those is
	## a GDScript error that aborted complete_json and returned null — discarding
	## a reply the model produced correctly.
	_install(YesJSONBackend.new())
	var got: Variant = await _svc.complete_json("p", {"line": "String"}, "FB")
	assert_eq(_be.submitted, 1, "exactly one request must have been sent")
	assert_true(got is Dictionary,
		"a valid reply must be returned, not destroyed by the fallback comparison (pre-fix: null)")
	if not (got is Dictionary):
		return  # a cast is not an assertion — bail rather than error past the assert
	assert_eq(str((got as Dictionary).get("line", "")), "ok", "and carry the parsed value")


func test_a_rejected_reply_returns_a_string_fallback_intact() -> void:
	## The other half of the contract: "Returns `fallback` on any failure" must
	## hold for a String too, and must still be REPORTED as a failure.
	_install(BadJSONBackend.new())
	var reasons: Array = []
	_svc.inference_failed.connect(func(_m, r): reasons.append(str(r)))
	var got: Variant = await _svc.complete_json("p", {"line": "String"}, "FB")
	assert_eq(str(got), "FB", "a String fallback must come back as itself")
	assert_eq(reasons.size(), 1, "and the rejection must still be reported")


func test_a_dictionary_fallback_still_compares_by_value() -> void:
	## CONTROL: the type check must not make every call look successful. Same
	## types, guard rejected, so guarded IS fallback and a failure must fire.
	_install(BadJSONBackend.new())
	var reasons: Array = []
	_svc.inference_failed.connect(func(_m, r): reasons.append(str(r)))
	var got: Variant = await _svc.complete_json("p", {"line": "String"}, {"line": "fb"})
	assert_true(got is Dictionary, "the Dictionary fallback must come back")
	assert_eq(reasons.size(), 1,
		"a rejected reply with a same-typed fallback must still report — otherwise the type guard has silenced every failure")


func test_a_success_with_a_dictionary_fallback_still_reports_success() -> void:
	## CONTROL the other way: the ordinary production shape must be untouched.
	_install(YesJSONBackend.new())
	var ok: Array = []
	_svc.inference_succeeded.connect(func(_m): ok.append(1))
	var got: Variant = await _svc.complete_json("p", {"line": "String"}, {"line": "fb"})
	assert_true(got is Dictionary, "a valid reply must be returned")
	if not (got is Dictionary):
		return
	assert_eq(str((got as Dictionary).get("line", "")), "ok",
		"the model's value must win over the fallback — this is the production path")
	assert_eq(ok.size(), 1, "and success must be reported exactly once")


# ── the surrounding guards must keep their own cases ──────────────────────────

func test_the_no_ready_backend_path_is_unchanged() -> void:
	_svc._backends.clear()
	_svc._active_backend = null
	var reasons: Array = []
	_svc.inference_failed.connect(func(_m, r): reasons.append(str(r)))
	var got: Variant = await _svc.complete_json("p", {"line": "String"}, "FB")
	assert_eq(str(got), "FB", "no backend must still fall back")
	assert_eq(reasons.size(), 1, "exactly one reason must be reported")
	assert_true(str(reasons[0]).find("no ready backend") != -1,
		"and must still be 'no ready backend', not the new capability reason")


func test_disabled_still_short_circuits_before_any_of_this() -> void:
	_install(NoJSONBackend.new())
	_svc.llm_enabled = false
	var reasons: Array = []
	_svc.inference_failed.connect(func(_m, r): reasons.append(str(r)))
	assert_eq(str(await _svc.complete_json("p", {}, "FB")), "FB", "must fall back")
	assert_eq(reasons.size(), 0, "a disabled LLM is not a failure and must report nothing")
	assert_eq(_be.submitted, 0, "and nothing may be sent")
