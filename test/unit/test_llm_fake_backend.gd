extends GutTest

## Wave F — FakeBackend (LLMBackend) hook tests.
##
## FakeBackend is a controllable LLMBackend implementation used by the live-path
## test suite. This file verifies each hook in isolation so the live-path tests
## can rely on FakeBackend's contract.
##
## Hooks under test:
##   - backend_id() == "fake"
##   - is_ready / supports_json configurable
##   - prime_next(text)            FIFO queue, ok=true
##   - prime_next_error(err)       FIFO queue, ok=false
##   - prime_for_prompt_contains(needle, text) substring-keyed override
##   - last_prompt / prompt_history
##   - submit_count / cancel_count
##   - fail_next(reason)
##   - emit_finish_sync_during_cancel (cancel() emits request_finished
##     synchronously in the same call frame — mirrors HTTPBackend bug #3)


# ── FakeBackend (inline test stub) ───────────────────────────────────────────

class FakeBackend extends LLMBackend:
	var _is_ready: bool = true
	var _supports_json: bool = true
	var _primed_queue: Array = []           # FIFO of { text, ok, error }
	var _prompt_overrides: Array = []       # [{ needle, text }]
	var _fail_next_reason: String = ""

	var last_prompt: String = ""
	var prompt_history: Array[String] = []
	var submit_count: int = 0
	var cancel_count: int = 0
	var pending_ids: Array[String] = []

	# When true, cancel()/cancel_all() emit request_finished synchronously
	# (mirroring the original HTTPBackend.cancel() that caused bug #3).
	var emit_finish_sync_during_cancel: bool = false

	# Force a hang — submit() records the prompt but never emits.
	var _hang: bool = false

	func backend_id() -> String:
		return "fake"

	func is_ready() -> bool:
		return _is_ready

	func supports_json() -> bool:
		return _supports_json

	func set_ready(v: bool) -> void:
		_is_ready = v

	func set_supports_json(v: bool) -> void:
		_supports_json = v

	func prime_next(text: String) -> void:
		_primed_queue.append({"text": text, "ok": true, "error": ""})

	func prime_next_error(err: String) -> void:
		_primed_queue.append({"text": "", "ok": false, "error": err})

	func prime_for_prompt_contains(needle: String, text: String) -> void:
		_prompt_overrides.append({"needle": needle, "text": text})

	func fail_next(reason: String) -> void:
		_fail_next_reason = reason

	func hang() -> void:
		_hang = true

	func resume() -> void:
		_hang = false

	func clear_all() -> void:
		_primed_queue.clear()
		_prompt_overrides.clear()
		prompt_history.clear()
		last_prompt = ""
		submit_count = 0
		cancel_count = 0
		pending_ids.clear()
		_fail_next_reason = ""
		_hang = false

	func submit(id: String, prompt: String, _opts: Dictionary = {}) -> void:
		submit_count += 1
		last_prompt = prompt
		prompt_history.append(prompt)
		pending_ids.append(id)

		if _hang:
			return

		if _fail_next_reason != "":
			var reason: String = _fail_next_reason
			_fail_next_reason = ""
			call_deferred("_emit", id, false, "", reason)
			return

		# Prompt-needle overrides take priority over the FIFO queue.
		for ov in _prompt_overrides:
			if prompt.find(ov["needle"]) != -1:
				call_deferred("_emit", id, true, str(ov["text"]), "")
				return

		if _primed_queue.size() > 0:
			var entry: Dictionary = _primed_queue.pop_front()
			call_deferred("_emit", id, bool(entry.get("ok", true)), str(entry.get("text", "")), str(entry.get("error", "")))
			return

		# Nothing primed — emit a default failure.
		call_deferred("_emit", id, false, "", "no primed response")

	func cancel(id: String) -> void:
		cancel_count += 1
		pending_ids.erase(id)
		if emit_finish_sync_during_cancel:
			# Mirror the bug #3 backend: emit synchronously inside cancel().
			request_finished.emit(id, false, "", "cancelled")

	func cancel_all() -> void:
		cancel_count += 1
		var snapshot: Array = pending_ids.duplicate()
		pending_ids.clear()
		if emit_finish_sync_during_cancel:
			for id in snapshot:
				request_finished.emit(id, false, "", "cancelled")

	func _emit(id: String, ok: bool, text: String, error: String) -> void:
		pending_ids.erase(id)
		request_finished.emit(id, ok, text, error)


# ── GUT lifecycle ────────────────────────────────────────────────────────────

var _be: FakeBackend


func before_each() -> void:
	_be = FakeBackend.new()
	_be.name = "TestFakeBackend"
	add_child_autofree(_be)


# ── Contract tests ───────────────────────────────────────────────────────────

func test_backend_id_is_fake() -> void:
	assert_eq(_be.backend_id(), "fake")


func test_is_ready_configurable() -> void:
	assert_true(_be.is_ready())
	_be.set_ready(false)
	assert_false(_be.is_ready())
	_be.set_ready(true)
	assert_true(_be.is_ready())


func test_supports_json_configurable() -> void:
	assert_true(_be.supports_json())
	_be.set_supports_json(false)
	assert_false(_be.supports_json())


func test_prime_next_returns_primed_text_async() -> void:
	_be.prime_next("hello world")
	var got: Array = []
	_be.request_finished.connect(func(id: String, ok: bool, text: String, error: String) -> void:
		got.append({"id": id, "ok": ok, "text": text, "error": error})
	)
	_be.submit("req-1", "any prompt")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(got.size(), 1)
	assert_eq(got[0]["ok"], true)
	assert_eq(got[0]["text"], "hello world")
	assert_eq(got[0]["id"], "req-1")


func test_prime_next_is_fifo() -> void:
	_be.prime_next("first")
	_be.prime_next("second")
	var got: Array[String] = []
	_be.request_finished.connect(func(_id: String, _ok: bool, text: String, _error: String) -> void:
		got.append(text)
	)
	_be.submit("a", "prompt-a")
	_be.submit("b", "prompt-b")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(got, ["first", "second"] as Array[String])


func test_prime_for_prompt_contains_overrides_queue() -> void:
	_be.prime_next("queued")
	_be.prime_for_prompt_contains("special-needle", "needle-hit")
	var got: Array[String] = []
	_be.request_finished.connect(func(_id: String, _ok: bool, text: String, _error: String) -> void:
		got.append(text)
	)
	_be.submit("r1", "a prompt mentioning special-needle here")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(got.size(), 1)
	assert_eq(got[0], "needle-hit", "needle override beats FIFO queue")


func test_last_prompt_and_history_tracked() -> void:
	_be.submit("a", "prompt one")
	_be.submit("b", "prompt two")
	assert_eq(_be.last_prompt, "prompt two")
	assert_eq(_be.prompt_history.size(), 2)
	assert_eq(_be.prompt_history[0], "prompt one")
	assert_eq(_be.prompt_history[1], "prompt two")
	assert_eq(_be.submit_count, 2)


func test_fail_next_emits_error() -> void:
	_be.fail_next("simulated boom")
	var got: Array = []
	_be.request_finished.connect(func(_id: String, ok: bool, text: String, error: String) -> void:
		got.append({"ok": ok, "text": text, "error": error})
	)
	_be.submit("f1", "prompt")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(got.size(), 1)
	assert_false(got[0]["ok"])
	assert_eq(got[0]["error"], "simulated boom")


func test_no_primed_response_emits_failure() -> void:
	var got: Array = []
	_be.request_finished.connect(func(_id: String, ok: bool, _text: String, _error: String) -> void:
		got.append(ok)
	)
	_be.submit("x", "prompt")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(got.size(), 1)
	assert_false(got[0])


func test_hang_blocks_emission() -> void:
	_be.hang()
	_be.prime_next("never delivered")
	var got: Array = []
	_be.request_finished.connect(func(_id: String, _ok: bool, _text: String, _error: String) -> void:
		got.append(true)
	)
	_be.submit("h1", "prompt")
	# Wait a few frames — nothing should be emitted.
	for i in range(5):
		await get_tree().process_frame
	assert_eq(got.size(), 0, "hang() must prevent any emission")


func test_emit_sync_during_cancel_fires_immediately() -> void:
	_be.emit_finish_sync_during_cancel = true
	_be.hang()
	_be.submit("c1", "prompt")
	var got_sync: Array = []
	_be.request_finished.connect(func(_id: String, _ok: bool, _text: String, error: String) -> void:
		got_sync.append(error)
	)
	# Cancel must emit synchronously (no frame wait).
	_be.cancel("c1")
	assert_eq(got_sync.size(), 1, "sync cancel must emit in same call frame")
	assert_eq(got_sync[0], "cancelled")
	assert_eq(_be.cancel_count, 1)


func test_cancel_count_increments() -> void:
	_be.cancel("noid")
	_be.cancel_all()
	assert_eq(_be.cancel_count, 2)
