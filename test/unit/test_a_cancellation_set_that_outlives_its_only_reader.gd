extends GutTest

## `_cancelled_ids` has exactly ONE reader — `_process_queue`, which skips an id
## that was cancelled while still sitting in `_queue`. Three of its four writers
## record ids that can never reach that read:
##
##   :426  cancel_all, the IN-FLIGHT id — in-flight and queued are mutually
##         exclusive in _submit_and_wait, so it is not in _queue
##   :433  cancel_all, the queued ids   — `_queue.clear()` on the next line
##   :472  queue overflow               — the id was already pop_front()ed (not
##         driven by this file: the branch needs a live await, and a hand-popped
##         queue would prove nothing)
##   :533  client timeout               — THE LIVE ONE: a queued id IS still
##         in _queue, and this is the write the reader exists for
##
## Only :605 erases, and only on dispatch — so the three dead writes accumulate
## for the life of the process. LLMService is an autoload, and cancel_all runs
## on every scene change.
##
## ⚠️ SEVERITY, STATED HONESTLY: this is NOT a correctness bug. `_generate_id`
## is a monotonic counter plus `Time.get_ticks_msec()`, so an id never repeats
## and a stale entry can never cancel a later request. It is unbounded growth of
## dead state in a session-long autoload, and the entries are short strings — so
## the cost is small and the reason to fix it is that the state is provably
## unreadable, not that anyone measured a memory problem.

const ReplayBackend := preload("res://tools/replay_backend.gd")

var _svc = null
var _backend = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


func before_each() -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	if _svc == null:
		return
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_backend = ReplayBackend.new()
	_backend.name = "ReplayCancelSet"
	_svc.add_child(_backend)
	_svc._backends.clear()
	_svc._backends.append(_backend)
	_svc._active_backend = _backend
	_svc._queue.clear()
	_svc._cancelled_ids.clear()
	_svc._pending_boxes.clear()
	_svc._inflight_id = ""


func after_each() -> void:
	## NET. LLMService is an autoload; leaving the stub installed would reach
	## every later FILE in the suite.
	if _backend and is_instance_valid(_backend):
		_svc.remove_child(_backend)
		_backend.free()
		_backend = null
	if _svc:
		_svc._queue.clear()
		_svc._cancelled_ids.clear()
		_svc._pending_boxes.clear()
		_svc._inflight_id = ""
		_svc._backends.clear()
		for b in _orig_backends:
			_svc._backends.append(b)
		_svc._active_backend = _orig_active
		_svc.llm_enabled = _orig_enabled


func _queue_one(id: String) -> void:
	_svc._pending_boxes[id] = [false, null]
	_svc._queue.append({"id": id, "prompt": "p", "opts": {}})


# ── floor ─────────────────────────────────────────────────────────────────────

func test_the_pieces_this_file_drives_are_reachable() -> void:
	assert_not_null(_svc, "LLMService autoload missing — nothing below runs")
	assert_true(_svc.has_method("_process_queue"),
		"LLMService._process_queue is gone — the only reader of _cancelled_ids")
	assert_true(_svc.has_method("cancel_all"), "LLMService.cancel_all is gone")
	assert_true("_cancelled_ids" in _svc, "LLMService._cancelled_ids is gone")


func test_an_id_is_never_reused_so_a_stale_entry_cannot_cancel_a_later_request() -> void:
	## PINS THE SEVERITY CLAIM. If ids ever repeated, the residue below would be
	## a correctness bug rather than growth, and this file's header would be wrong.
	var seen: Dictionary = {}
	for i in range(50):
		var id: String = _svc._generate_id()
		assert_false(seen.has(id), "_generate_id repeated '%s' — stale cancellations become live" % id)
		seen[id] = true


# ── the growth ────────────────────────────────────────────────────────────────

func test_cancel_all_does_not_leave_unreadable_entries_behind() -> void:
	## cancel_all clears _queue in the same breath, so nothing it marks can ever
	## reach _process_queue's check. Every entry it leaves is permanent.
	_queue_one("q1")
	_queue_one("q2")
	_svc._inflight_id = "inflight1"
	_svc._pending_boxes["inflight1"] = [false, null]
	_svc.cancel_all("test")
	assert_eq(_svc._queue.size(), 0, "cancel_all must drain the queue")
	assert_eq(_svc._cancelled_ids.size(), 0,
		("cancel_all left %d entry/entries in _cancelled_ids that no code path can "
		+ "read: the queue was cleared in the same call and the in-flight id was "
		+ "never in it. LLMService is an autoload and cancel_all runs on every "
		+ "scene change, so these accumulate for the session. keys=%s")
			% [_svc._cancelled_ids.size(), _svc._cancelled_ids.keys()])


# ── the control: the ONE live write must survive ─────────────────────────────

func test_a_request_cancelled_while_queued_is_still_skipped_on_dispatch() -> void:
	## LOAD-BEARING CONTROL. The client-timeout write at :533 is the only one the
	## reader exists for: that id IS still in _queue. If a cleanup removed it too,
	## a timed-out request would be dispatched anyway — burning an inference call
	## and handing the answer to a caller that already took its fallback.
	_queue_one("timed_out")
	_svc._cancelled_ids["timed_out"] = true
	_svc._inflight_id = ""
	_svc._process_queue()
	assert_eq(_svc._inflight_id, "",
		("a request cancelled while queued was dispatched anyway (_inflight_id=%s). "
		+ "_process_queue's _cancelled_ids check is the protection and it did not fire.")
			% [_svc._inflight_id])
	assert_false(_svc._cancelled_ids.has("timed_out"),
		"the live entry must be erased once its purpose is served")
