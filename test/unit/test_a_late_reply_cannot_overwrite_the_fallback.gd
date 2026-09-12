extends GutTest

## The NPC says one thing, then says something else two seconds later.
##
## LLMService runs two timers on every request: CLIENT_TIMEOUT_SEC (6s) after
## which the awaiting caller takes the fallback, and the HTTPRequest's own 30s.
## That gap is deliberate — a player must never freeze for 30s — and it means a
## real reply can arrive AFTER the fallback is already on screen.
##
## The reply is not a slow model — it is the backend's own cancel(). The timeout
## path asks the backend to abort, and HTTPBackend.cancel() emits
## request_finished SYNCHRONOUSLY (bug #3). So the "late" reply arrives inside the
## timeout handler itself, and what stops it being applied is ORDERING:
##
##     _pending_boxes.erase(id)          LOAD-BEARING, measured
##     if _inflight_id == id: ... = ""    belt and braces, measured
##     _active_backend.cancel(id)        <- may emit request_finished HERE
##
## MEASURED which one carries it, rather than trusting the comment that was there:
##
##     move the _inflight_id clear to AFTER cancel   0 red   <- not the protection
##     remove _pending_boxes.erase(id)               1 red   <- this is
##
## The source comment said the sync emit was safe "precisely because _inflight_id
## was cleared above". It is not: moving that clear changes nothing observable. A
## refactor reading it would have protected the wrong line, so the comment now
## names the erase. Corrected in the same commit.
##
## ⚠️ THE ORDERING WAS NEVER OBSERVED. test_rule_composer_timeout hangs its
## backend, so cancel's sync emit never fires there; test_cancel_all_with_sync_emit
## covers cancel_all, which takes the _draining path instead. The timeout firing
## was covered, and the four lines of reasoning about why the sync emit is harmless
## were not.
##
## That matters because the comments are the kind a later refactor removes as
## redundant. `if _inflight_id == id: _inflight_id = ""` reads like a no-op when
## the next two lines are about to erase the box.
##
## What a player would see: the fallback line, read, and then the NPC's dialogue
## replaced under them — or a queued request dispatched a beat early.

const FakeBackendScript := preload("res://test/unit/test_llm_fake_backend.gd")

const TINY_TIMEOUT: float = 0.4
const FALLBACK: Dictionary = {"line": "FALLBACK"}
const SCHEMA: Dictionary = {"line": "String"}

var _svc = null
var _be: FakeBackendScript.FakeBackend = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


func before_each() -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist")
	if _svc == null:
		return
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_svc.cancel_all("late-reply fixture isolation")
	_be = FakeBackendScript.FakeBackend.new()
	_be.name = "LateFakeBE"
	_svc.add_child(_be)
	_svc._backends.clear()
	_svc._backends.append(_be)
	_be.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _be


func after_each() -> void:
	if _svc == null:
		return
	if _be and is_instance_valid(_be):
		_be.request_finished.disconnect(_svc._on_backend_finished)
		_svc.remove_child(_be)
		_be.free()
	_svc._backends.clear()
	for b in _orig_backends:
		_svc._backends.append(b)
	_svc._active_backend = _orig_active
	_svc.llm_enabled = _orig_enabled


## Time out a request against a backend that emits request_finished SYNCHRONOUSLY
## from inside cancel() — i.e. the real HTTPBackend bug #3 shape. The "late" reply
## is delivered by the shipping code path, not by the test.
func _time_out_against_a_sync_emitting_backend() -> Variant:
	_be.hang()
	_be.emit_finish_sync_during_cancel = true
	return await _svc.complete_json(
		"a prompt", SCHEMA, FALLBACK, {"client_timeout_sec": TINY_TIMEOUT})


# ── the premise ───────────────────────────────────────────────────────────────

func test_the_client_timeout_fires_and_the_backend_is_cancelled() -> void:
	## CONTROL. Every arm below depends on the caller having given up AND the
	## backend having been asked to abort — that ask is what emits synchronously.
	var got: Variant = await _time_out_against_a_sync_emitting_backend()
	assert_eq(str((got as Dictionary).get("line", "")), "FALLBACK",
		"the caller must take the fallback")
	assert_gt(_be.cancel_count, 0,
		"the timeout must ask the backend to abort, or the sync emit never happens")


# ── the defect ────────────────────────────────────────────────────────────────

func test_the_sync_emit_from_cancel_does_not_revive_the_request() -> void:
	## THE ARM. cancel() fires request_finished in the same call frame, with the
	## id the service was holding a moment earlier. Ordering is the only thing
	## that makes it inert.
	await _time_out_against_a_sync_emitting_backend()
	await get_tree().process_frame
	assert_eq(_svc._pending_boxes.size(), 0,
		"no box may survive: the sync emit must not re-resolve or re-create one")
	assert_eq(str(_svc._inflight_id), "",
		"and the in-flight slot must stay clear, or nothing else can ever run")


func test_the_service_still_works_after_the_sync_emit() -> void:
	## The consequence a player would meet. If the sync emit were accepted,
	## _on_backend_finished would clear _inflight_id and pump the queue for a
	## request nobody awaits — so the NEXT line is what breaks, not this one.
	await _time_out_against_a_sync_emitting_backend()
	await get_tree().process_frame
	_be.resume()
	_be.emit_finish_sync_during_cancel = false
	_be.prime_next('{"line": "THE NEXT LINE"}')
	var second: Variant = await _svc.complete_json(
		"another prompt", SCHEMA, FALLBACK, {"client_timeout_sec": 5.0})
	assert_eq(str((second as Dictionary).get("line", "")), "THE NEXT LINE",
		"the conversation must continue normally after a cancelled request emitted late")


# ── it must not break the normal path ─────────────────────────────────────────

func test_a_reply_that_arrives_in_time_is_still_used() -> void:
	## CORRECT-WORK. These defences must only drop replies nobody is waiting for.
	_be.prime_next('{"line": "ON TIME"}')
	var got: Variant = await _svc.complete_json(
		"prompt", SCHEMA, FALLBACK, {"client_timeout_sec": 5.0})
	assert_eq(str((got as Dictionary).get("line", "")), "ON TIME",
		"a timely reply must reach the caller — this guards a race, not the feature")


func test_an_unknown_id_is_ignored_without_disturbing_anything() -> void:
	## CONTROL on the guard itself: a signal for an id the service never issued
	## must be inert, not merely dropped-by-luck.
	_be.request_finished.emit("an-id-that-never-existed", true, '{"line": "GHOST"}', "")
	await get_tree().process_frame
	_be.prime_next('{"line": "STILL FINE"}')
	var got: Variant = await _svc.complete_json(
		"prompt", SCHEMA, FALLBACK, {"client_timeout_sec": 5.0})
	assert_eq(str((got as Dictionary).get("line", "")), "STILL FINE",
		"a ghost id must not wedge the service")
