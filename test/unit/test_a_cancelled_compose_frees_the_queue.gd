extends GutTest

## Cancelling the Rule Composer while it read "Thinking..." hid the panel and left the request running.
## LLMService runs one request at a time, so the composer's abandoned reply held the queue until the
## 6 s client timeout: a re-compose, a party line or an NPC reply waited behind a request nobody wanted,
## and on a BYOK backend the player paid for it. A cancel token in the request's opts now abandons it
## the way the timeout does, at once.

const FakeBackendScript := preload("res://test/unit/test_llm_fake_backend.gd")
const OVERLAY_SCENE := preload("res://src/ui/autobattle/RuleComposerOverlay.tscn")
const FALLBACK: Dictionary = {"line": "FALLBACK"}
const SCHEMA: Dictionary = {"line": "String"}
## Well under CLIENT_TIMEOUT_SEC, so an abandon inside it is the token and not the timeout.
const QUICK_MS: int = 1000

var _svc = null
var _be: FakeBackendScript.FakeBackend = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true
var _results: Dictionary = {}
var _failures: Array = []


func before_each() -> void:
	_results = {}
	_failures = []
	_svc = get_tree().root.get_node_or_null("LLMService")
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist")
	if _svc == null:
		return
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_svc.cancel_all("cancel-token fixture isolation")
	_be = FakeBackendScript.FakeBackend.new()
	_be.name = "CancelTokenFakeBE"
	_svc.add_child(_be)
	_svc._backends.clear()
	_svc._backends.append(_be)
	_be.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _be
	_be.hang()
	_svc.inference_failed.connect(_on_failed)


func after_each() -> void:
	if _svc == null:
		return
	if _svc.inference_failed.is_connected(_on_failed):
		_svc.inference_failed.disconnect(_on_failed)
	_svc.cancel_all("cancel-token fixture teardown")
	if _be and is_instance_valid(_be):
		_be.request_finished.disconnect(_svc._on_backend_finished)
		_svc.remove_child(_be)
		_be.free()
	_svc._backends.clear()
	_svc._backends.append_array(_orig_backends)
	_svc._active_backend = _orig_active
	_svc.llm_enabled = _orig_enabled


func _on_failed(mode: String, reason: String) -> void:
	_failures.append("%s/%s" % [mode, reason])


func _ask(key: String, opts: Dictionary) -> void:
	_results[key] = await _svc.complete_json("prompt " + key, SCHEMA, FALLBACK, opts)


func _frames_until(cond: Callable, max_ms: int = 2000) -> int:
	var t0: int = Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < max_ms:
		await get_tree().process_frame
	return Time.get_ticks_msec() - t0


func test_a_cancelled_request_frees_the_queue_at_once() -> void:
	var token := {"cancelled": false}
	_ask("a", {_svc.CANCEL_TOKEN: token})
	await _frames_until(func() -> bool: return _svc._inflight_id != "")
	assert_ne(_svc._inflight_id, "", "PRECONDITION: the request is in flight on a hung backend")
	token["cancelled"] = true
	var waited: int = await _frames_until(func() -> bool: return _results.has("a"))
	assert_true(_results.has("a"), "the caller is answered once its token is cancelled")
	assert_lt(waited, QUICK_MS, "at once, not at the 6 s client timeout (%d ms)" % waited)
	assert_eq(_results.get("a"), FALLBACK, "with the fallback, like a timeout")
	assert_eq(_svc._inflight_id, "", "the one-at-a-time slot is free again")
	assert_eq(_be.cancel_count, 1, "and the backend was asked to abort the request")
	assert_false(_failures.has("json/client_timeout"), "a cancel is not reported as a timeout: %s" % [_failures])


func test_the_next_request_runs_when_the_first_is_cancelled() -> void:
	var token := {"cancelled": false}
	_ask("a", {_svc.CANCEL_TOKEN: token})
	await _frames_until(func() -> bool: return _svc._inflight_id != "")
	_ask("b", {})
	await get_tree().process_frame
	assert_eq(_be.submit_count, 1, "PRECONDITION: the second request waits behind the first")
	token["cancelled"] = true
	var waited: int = await _frames_until(func() -> bool: return _be.submit_count == 2)
	assert_eq(_be.submit_count, 2, "the queued request is sent once the cancelled one lets go")
	assert_lt(waited, QUICK_MS, "without waiting out the cancelled one (%d ms)" % waited)


func test_a_request_cancelled_while_queued_is_never_sent() -> void:
	_ask("a", {})
	await _frames_until(func() -> bool: return _svc._inflight_id != "")
	var token := {"cancelled": false}
	_ask("b", {_svc.CANCEL_TOKEN: token})
	await get_tree().process_frame
	token["cancelled"] = true
	await _frames_until(func() -> bool: return _results.has("b"))
	assert_eq(_results.get("b"), FALLBACK, "the queued caller is answered with the fallback")
	assert_eq(_be.submit_count, 1, "CONTROL: only the first request has reached the backend")
	_be.resume()
	_svc._on_backend_finished(_svc._inflight_id, true, "{\"line\": \"real\"}", "")
	await get_tree().process_frame
	assert_eq(_be.submit_count, 1, "and the cancelled one is not sent when the queue moves")


func test_without_a_token_the_request_keeps_the_queue() -> void:
	_ask("a", {})
	await _frames_until(func() -> bool: return _svc._inflight_id != "")
	await _frames_until(func() -> bool: return _results.has("a"), 400)
	assert_false(_results.has("a"), "CONTROL: an uncancelled request on a hung backend is still waiting, so the arms above measure the token")
	assert_ne(_svc._inflight_id, "", "CONTROL: and still holds the slot")


func _composing_overlay() -> Control:
	var overlay: Control = OVERLAY_SCENE.instantiate()
	add_child(overlay)
	overlay.open("autogrind", "", [])
	overlay.compose("stop when the party is low")
	await _frames_until(func() -> bool: return _svc._inflight_id != "")
	return overlay


func test_the_composers_cancel_frees_the_queue() -> void:
	var overlay: Control = await _composing_overlay()
	assert_ne(_svc._inflight_id, "", "PRECONDITION: the composer's request is in flight")
	assert_true(overlay._busy, "PRECONDITION: the composer reads Thinking")
	overlay.cancel()
	var waited: int = await _frames_until(func() -> bool: return _svc._inflight_id == "")
	assert_eq(_svc._inflight_id, "", "Cancel on the composer lets the queue go")
	assert_lt(waited, QUICK_MS, "at once (%d ms)" % waited)
	await _frames_until(func() -> bool: return not overlay._busy)
	assert_false(overlay.visible, "CONTROL: the cancelled composer stays hidden")
	overlay.free()


func test_a_composer_freed_mid_compose_frees_the_queue() -> void:
	var overlay: Control = await _composing_overlay()
	assert_ne(_svc._inflight_id, "", "PRECONDITION: the composer's request is in flight")
	overlay.queue_free()
	var waited: int = await _frames_until(func() -> bool: return _svc._inflight_id == "")
	assert_eq(_svc._inflight_id, "", "a composer that leaves the tree mid-compose lets the queue go")
	assert_lt(waited, QUICK_MS, "at once (%d ms)" % waited)


func test_an_npc_conversation_aborted_while_thinking_frees_the_queue() -> void:
	var conv = preload("res://src/llm/DynamicConversation.gd").new()
	add_child_autofree(conv)
	conv._safe_complete_json("npc prompt", SCHEMA, FALLBACK)
	await _frames_until(func() -> bool: return _svc._inflight_id != "")
	assert_ne(_svc._inflight_id, "", "PRECONDITION: the NPC's request is in flight")
	conv.abort()
	var waited: int = await _frames_until(func() -> bool: return _svc._inflight_id == "")
	assert_eq(_svc._inflight_id, "", "cancel on the NPC's thinking box lets the queue go")
	assert_lt(waited, QUICK_MS, "at once (%d ms)" % waited)
