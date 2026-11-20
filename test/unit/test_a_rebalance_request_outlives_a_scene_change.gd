extends GutTest

## struktured's .808 session: a level-up asked the rebalance daemon for a proposal, he walked through a door, and the
## scene change cancelled the request ("[LLMService] cancel_all: scene_change", then "produced no proposal — the
## request was cancelled"). A scene change drops NPC dialogue from the old map on purpose; a difficulty proposal
## belongs to no map. A request that says so now survives a scene change, and only a scene change.

const DAEMON := preload("res://src/llm/RebalanceDaemon.gd")
const GUARD := {"a": "String"}
const NUDGE := '{"verdict": "nudge_easier", "confidence": 0.8, "deltas": [{"constant": "exp_multiplier", "multiplier": 1.05, "reason": "three wipes"}], "reason": "a little more XP"}'

var _llm: Node
var _be = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true
var _got: Dictionary = {}


## A model that holds every request until the test lets it answer.
class HeldModel extends LLMBackend:
	var reply: String = ""
	var waiting: Array = []
	var cancels: int = 0
	func backend_id() -> String: return "held_model"
	func is_ready() -> bool: return true
	func supports_json() -> bool: return true
	func submit(id: String, _p: String, _o: Dictionary = {}) -> void:
		waiting.append(id)
	func cancel_all() -> void:
		cancels += 1
		waiting.clear()
	func answer() -> void:
		var ids: Array = waiting.duplicate()
		waiting.clear()
		for id in ids:
			request_finished.emit(id, true, reply, "")


func before_each() -> void:
	_got = {}
	_llm = get_tree().root.get_node("LLMService")
	_orig_enabled = _llm.llm_enabled
	_orig_backends = _llm._backends.duplicate()
	_orig_active = _llm._active_backend
	_llm.llm_enabled = true
	_llm.cancel_all("outlives fixture isolation")
	_llm.clear_cache()
	_be = HeldModel.new()
	_be.reply = '{"a": "x"}'
	_llm.add_child(_be)
	_llm._backends.clear()
	_llm._backends.append(_be)
	_be.request_finished.connect(_llm._on_backend_finished)
	_llm._active_backend = _be


func after_each() -> void:
	_llm.cancel_all("outlives fixture teardown")
	_be.request_finished.disconnect(_llm._on_backend_finished)
	_llm.remove_child(_be)
	_be.free()
	_llm._backends.clear()
	for b in _orig_backends:
		_llm._backends.append(b)
	_llm._active_backend = _orig_active
	_llm.llm_enabled = _orig_enabled
	_llm.clear_cache()


## Starts one JSON request and records its result under `tag` when it resolves; "unresolved" until then.
func _ask(tag: String, keeps: bool) -> void:
	_got[tag] = "unresolved"
	var opts: Dictionary = {_llm.OUTLIVES_SCENE_CHANGE: true} if keeps else {}
	_got[tag] = await _llm.complete_json("Say a.", GUARD, null, opts)


func _frames(n: int = 3) -> void:
	for i in n:
		await get_tree().process_frame


func test_a_request_in_flight_that_belongs_to_no_scene_survives_the_door() -> void:
	_ask("kept", true)
	await _frames()
	assert_eq(_be.waiting.size(), 1, "CONTROL: the request is with the model")
	_llm.cancel_all("scene_change")
	await _frames()
	assert_eq(str(_got["kept"]), "unresolved", "a scene change leaves it waiting on the model")
	assert_eq(_be.cancels, 0, "and the model's request is not aborted under it")
	_be.answer()
	await _frames()
	assert_eq(_got["kept"], {"a": "x"}, "so the answer arrives after the door")


func test_control_an_ordinary_request_is_still_dropped_by_the_door() -> void:
	_ask("plain", false)
	await _frames()
	_llm.cancel_all("scene_change")
	await _frames()
	assert_null(_got["plain"], "CONTROL: dialogue from the old map still resolves to its fallback")
	assert_eq(_be.cancels, 1, "CONTROL: and its request is aborted")
	_be.answer()
	await _frames()
	assert_null(_got["plain"], "CONTROL: a late answer changes nothing")


func test_a_kept_request_waiting_behind_a_dropped_one_goes_out_next() -> void:
	_ask("plain", false)
	_ask("kept", true)
	await _frames()
	assert_eq(_be.waiting.size(), 1, "CONTROL: one in flight, one queued behind it")
	_llm.cancel_all("scene_change")
	await _frames()
	assert_null(_got["plain"], "the old map's request is dropped")
	assert_eq(str(_got["kept"]), "unresolved", "the kept one is not")
	assert_eq(_be.waiting.size(), 1, "and it has been sent, with nothing left ahead of it")
	_be.answer()
	await _frames()
	assert_eq(_got["kept"], {"a": "x"})


func test_control_any_other_cancel_takes_a_kept_request_too() -> void:
	_ask("kept", true)
	_ask("queued", true)
	await _frames()
	_llm.cancel_all("llm_switched_off")
	await _frames()
	assert_null(_got["kept"], "CONTROL: only a scene change spares it; switching the LLM off cancels everything")
	assert_null(_got["queued"], "CONTROL: in the queue as well")
	assert_eq(_be.cancels, 1)


func test_the_daemons_proposal_arrives_after_a_scene_change() -> void:
	var d = DAEMON.new()
	d.pending.append({"trigger": "level_up", "ts": 0, "context_summary": "member=Fighter, new_level=2", "status": "pending"})
	var done := {"ok": null}
	var run := func() -> void: done["ok"] = await d.request_llm_proposal(0)
	run.call()
	await _frames()
	assert_eq(_be.waiting.size(), 1, "CONTROL: the daemon's request is with the model")
	_llm.cancel_all("scene_change")
	await _frames()
	assert_null(done["ok"], "the door does not end it")
	_be.reply = NUDGE
	_be.answer()
	await _frames()
	assert_eq(done["ok"], true, "THE DEFECT: his log's level-up proposal was cancelled by the next door")
	assert_eq(str(d.pending[0].get("status", "")), "proposed")
