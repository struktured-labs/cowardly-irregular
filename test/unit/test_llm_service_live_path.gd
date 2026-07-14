extends GutTest

## Wave F — LLMService live-path tests using FakeBackend.
##
## We install a FakeBackend as the active backend on an LLMService instance and
## drive the full async pipeline through it. This exercises the code paths that
## the existing test_llm_infra.gd cannot — those tests run with llm_enabled=false
## and never actually traverse the backend.
##
## Critical regression test (bug #3): cancel_all() with a backend that emits
## request_finished SYNCHRONOUSLY inside cancel_all() must NOT hang the
## awaiting coroutine. Before the fix in LLMService.cancel_all + _draining
## guard, the awaiting coroutine looped forever on get_tree().process_frame.

const FakeBackendScript := preload("res://test/unit/test_llm_fake_backend.gd")


# ── GUT lifecycle ────────────────────────────────────────────────────────────

var _svc: Node
var _be: FakeBackendScript.FakeBackend


func before_each() -> void:
	_svc = preload("res://src/llm/LLMService.gd").new()
	_svc.name = "TestLLMService"
	_svc.llm_enabled = true
	add_child_autofree(_svc)
	# _ready() already added HTTPBackend + NullBackend; replace with FakeBackend.
	# Disconnect the auto-built backends so they don't fire stale signals.
	for be in _svc._backends:
		if be.request_finished.is_connected(_svc._on_backend_finished):
			be.request_finished.disconnect(_svc._on_backend_finished)
	_be = FakeBackendScript.FakeBackend.new()
	_be.name = "FakeBE"
	_svc.add_child(_be)
	# _backends is a strictly-typed Array[LLMBackend]; reassigning to an
	# untyped Array literal triggers SCRIPT ERROR. Clear + append preserves
	# the typed array.
	_svc._backends.clear()
	_svc._backends.append(_be)
	_be.request_finished.connect(_svc._on_backend_finished)
	_svc._select_backend()


# ── Live-path tests ──────────────────────────────────────────────────────────

func test_is_available_with_fake_backend() -> void:
	assert_true(_svc.is_available(), "FakeBackend.is_ready() = true ⇒ service available")


func test_complete_returns_primed_text_not_fallback() -> void:
	_be.prime_next("live model output")
	var result: Variant = await _svc.complete("any prompt", "fallback-text")
	assert_eq(str(result), "live model output", "complete() should return primed FakeBackend text")
	assert_eq(_be.submit_count, 1)


func test_complete_uses_fallback_on_backend_failure() -> void:
	_be.fail_next("simulated error")
	var result: Variant = await _svc.complete("prompt", "fb")
	assert_eq(str(result), "fb", "fallback returned when backend reports failure")


func test_cache_hit_avoids_second_submit() -> void:
	_be.prime_next("cached value")
	var first: Variant = await _svc.complete("same prompt", "fb")
	assert_eq(str(first), "cached value")
	assert_eq(_be.submit_count, 1)

	# Second call with identical prompt+opts should hit cache — no new submit.
	var second: Variant = await _svc.complete("same prompt", "fb")
	assert_eq(str(second), "cached value", "cache hit returns same text")
	assert_eq(_be.submit_count, 1, "cache hit must not call submit() again")


func test_queue_ordering_fifo() -> void:
	# Hang the backend; submit three completes in parallel; resume; check order.
	# Each await yields back here only when its turn is up.
	_be.prime_next("A")
	_be.prime_next("B")
	_be.prime_next("C")
	# We must serialize awaits; LLMService already serializes via _inflight_id.
	var a: Variant = await _svc.complete("first", "fb")
	var b: Variant = await _svc.complete("second", "fb")
	var c: Variant = await _svc.complete("third", "fb")
	assert_eq(str(a), "A")
	assert_eq(str(b), "B")
	assert_eq(str(c), "C")
	assert_eq(_be.submit_count, 3)


func test_inference_failed_fires_on_backend_failure() -> void:
	var failures: Array = []
	_svc.inference_failed.connect(func(mode: String, reason: String) -> void:
		failures.append({"mode": mode, "reason": reason})
	)
	_be.fail_next("nope")
	var _r: Variant = await _svc.complete("prompt", "fb")
	assert_gt(failures.size(), 0, "inference_failed should emit on backend failure")


# ─── REGRESSION (bug #3): cancel_all + synchronous-finish backend ────────────

## Submit a request; before backend resolves, cancel_all() with a sync-emit
## backend. The awaiting coroutine MUST resolve to fallback within a small
## frame budget — never hang.
func test_cancel_all_with_sync_emit_does_not_hang() -> void:
	_be.emit_finish_sync_during_cancel = true
	_be.hang()  # never deliver on its own
	_be.prime_next("won't be used")

	var resolved: Array = [false, null]
	# Kick off the request as a coroutine that records its return value.
	var coro: Callable = func() -> void:
		var r: Variant = await _svc.complete("hung prompt", "fb-text")
		resolved[0] = true
		resolved[1] = r
	coro.call_deferred()

	# Let it queue / submit.
	await get_tree().process_frame
	await get_tree().process_frame

	# Now cancel — the sync-emit FakeBackend mirrors the original bug #3.
	_svc.cancel_all("test cancel")

	# Bounded wait: the coroutine MUST resolve within 30 frames. If it does
	# not, the bug has regressed and we'd otherwise hang indefinitely.
	var max_frames: int = 30
	var i: int = 0
	while not resolved[0] and i < max_frames:
		await get_tree().process_frame
		i += 1

	assert_true(resolved[0], "cancel_all must let awaiting coroutine resolve (bug #3 regression)")
	# Either fallback or null is acceptable — what matters is the
	# coroutine completes. complete() returns fallback when the resolved
	# raw is null.
	assert_eq(str(resolved[1]), "fb-text", "awaited result should be the fallback after cancel_all")
