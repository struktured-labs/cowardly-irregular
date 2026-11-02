extends GutTest

## struktured's .758 session log: "[LLMService][guard/json] Missing required key 'deltas'" then "[REBALANCE] area_entered
## produced no proposal — the model's reply was not usable". Since .751 the prompt says most events need no change, and a
## model answering no_change naturally leaves the deltas list out, so the schema guard threw the right answer away.
## deltas is now checked in request_llm_proposal: optional for no_change only, and still an Array when present.

const DAEMON := preload("res://src/llm/RebalanceDaemon.gd")

var _llm: Node
var _be = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


class ReplyModel extends LLMBackend:
	var reply: String = ""
	func backend_id() -> String: return "reply_model"
	func is_ready() -> bool: return true
	func supports_json() -> bool: return true
	func submit(id: String, _p: String, _o: Dictionary = {}) -> void:
		_emit.call_deferred(id)
	func _emit(id: String) -> void:
		request_finished.emit(id, true, reply, "")


func before_each() -> void:
	_llm = get_tree().root.get_node("LLMService")
	_orig_enabled = _llm.llm_enabled
	_orig_backends = _llm._backends.duplicate()
	_orig_active = _llm._active_backend
	_llm.llm_enabled = true
	_llm.cancel_all("no_change fixture isolation")
	_llm.clear_cache()
	_be = ReplyModel.new()
	_llm.add_child(_be)
	_llm._backends.clear()
	_llm._backends.append(_be)
	_be.request_finished.connect(_llm._on_backend_finished)
	_llm._active_backend = _be


func after_each() -> void:
	_llm.cancel_all("no_change fixture teardown")
	_be.request_finished.disconnect(_llm._on_backend_finished)
	_llm.remove_child(_be)
	_be.free()
	_llm._backends.clear()
	for b in _orig_backends:
		_llm._backends.append(b)
	_llm._active_backend = _orig_active
	_llm.llm_enabled = _orig_enabled
	_llm.clear_cache()


## The proposal the daemon recorded for one model reply, plus request_llm_proposal's return.
func _propose(reply: String) -> Dictionary:
	_be.reply = reply
	_llm.clear_cache()
	var d = DAEMON.new()
	d.pending.append({"trigger": "area_entered", "ts": 0, "context_summary": "map_id=overworld", "status": "pending"})
	var ok: bool = await d.request_llm_proposal(0)
	var p: Dictionary = d.pending[0] if d.pending.size() > 0 else {}
	return {"ok": ok, "p": p}


func test_a_no_change_reply_without_deltas_is_heard() -> void:
	var r: Dictionary = await _propose('{"verdict": "no_change", "confidence": 1.0, "reason": "the curve is fine"}')
	assert_true(r["ok"], "THE DEFECT: the model's correct no_change was dropped as unusable")
	assert_eq(str(r["p"].get("verdict", "")), "no_change", "and recorded as what the model said")
	assert_eq(r["p"].get("deltas"), [], "with an empty list of changes")


func test_a_nudge_without_deltas_is_still_refused() -> void:
	var r: Dictionary = await _propose('{"verdict": "nudge_easier", "confidence": 0.9, "reason": "too hard"}')
	assert_false(r["ok"], "a nudge that does not say what it moves is not a proposal")
	assert_eq(str(r["p"].get("status", "")), "failed_fallback", "and it says so")


func test_deltas_that_are_not_a_list_are_refused() -> void:
	var r: Dictionary = await _propose('{"verdict": "no_change", "confidence": 1.0, "deltas": "none", "reason": "x"}')
	assert_false(r["ok"], "a present deltas must still be a list, whatever the verdict")


## CONTROL: an ordinary nudge with its list still lands, so the arms above are not passing on a path that refuses all.
func test_control_a_nudge_with_deltas_lands() -> void:
	var r: Dictionary = await _propose(
		'{"verdict": "nudge_easier", "confidence": 0.9, "deltas": [{"constant": "exp_multiplier", "multiplier": 1.05}], "reason": "x"}')
	assert_true(r["ok"], "a complete nudge must still be proposed")
	assert_eq((r["p"].get("deltas", []) as Array).size(), 1, "with its delta intact")
