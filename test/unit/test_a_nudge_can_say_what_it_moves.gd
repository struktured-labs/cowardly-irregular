extends GutTest

## struktured's .808 session: 8 of 9 rebalance requests ended "the model's list of changes was missing or not a list".
## Since .805 a JSON request carries a schema built from the feature's GUARD, and the daemon's guard leaves `deltas`
## out on purpose (a no_change may omit it). A server that constrains to that schema cannot write `deltas` at all,
## so every nudge arrived without its list. Replayed on his Ollama: 6 of 6 wipes, verdict nudge_easier, no deltas.

const DAEMON := preload("res://src/llm/RebalanceDaemon.gd")
const DAEMON_SRC := "res://src/llm/RebalanceDaemon.gd"
const NUDGE := '{"verdict": "nudge_easier", "confidence": 0.8, "deltas": [{"constant": "exp_multiplier", "multiplier": 1.05, "reason": "three wipes"}], "reason": "a little more XP"}'
const NUDGE_AS_SHIPPED := '{"verdict": "nudge_easier", "confidence": 0.8, "reason": "a little more XP"}'

var _llm: Node
var _be = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true


class ReplyModel extends LLMBackend:
	var reply: String = ""
	var seen: Array = []
	func backend_id() -> String: return "reply_model"
	func is_ready() -> bool: return true
	func supports_json() -> bool: return true
	func submit(id: String, _p: String, o: Dictionary = {}) -> void:
		seen.append(o.duplicate(true))
		_emit.call_deferred(id)
	func _emit(id: String) -> void:
		request_finished.emit(id, true, reply, "")


func before_each() -> void:
	_llm = get_tree().root.get_node("LLMService")
	_orig_enabled = _llm.llm_enabled
	_orig_backends = _llm._backends.duplicate()
	_orig_active = _llm._active_backend
	_llm.llm_enabled = true
	_llm.cancel_all("nudge fixture isolation")
	_llm.clear_cache()
	_be = ReplyModel.new()
	_llm.add_child(_be)
	_llm._backends.clear()
	_llm._backends.append(_be)
	_be.request_finished.connect(_llm._on_backend_finished)
	_llm._active_backend = _be


func after_each() -> void:
	_llm.cancel_all("nudge fixture teardown")
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
	_be.seen.clear()
	_llm.clear_cache()
	var d = DAEMON.new()
	d.pending.append({"trigger": "party_wipe", "ts": 0, "context_summary": "third wipe in whispering_cave", "status": "pending"})
	var ok: bool = await d.request_llm_proposal(0)
	var p: Dictionary = d.pending[0] if d.pending.size() > 0 else {}
	return {"ok": ok, "p": p}


func _sent_schema() -> Dictionary:
	if _be.seen.is_empty() or not (_be.seen[0].get("json_schema") is Dictionary):
		return {}
	return _be.seen[0]["json_schema"]


## Every key the daemon reads off the reply, taken from its own source.
func _keys_the_daemon_reads() -> Array:
	var src: String = FileAccess.get_file_as_string(DAEMON_SRC)
	var from: int = src.find("func request_llm_proposal(")
	var to: int = src.find("\nfunc ", from + 1)
	var out: Array = []
	for m in RegEx.create_from_string("\\br\\.get\\(\"(\\w+)\"").search_all(src.substr(from, to - from)):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	return out


func test_the_request_lets_the_model_write_every_key_the_daemon_reads() -> void:
	var read: Array = _keys_the_daemon_reads()
	assert_true(read.has("deltas") and read.has("verdict") and read.size() >= 4, "CONTROL: the derivation finds the keys request_llm_proposal reads: %s" % str(read))
	await _propose(NUDGE)
	var props: Dictionary = _sent_schema().get("properties", {})
	assert_false(props.is_empty(), "CONTROL: the request carried a schema")
	for key in read:
		assert_true(props.has(key), "the schema on the wire must allow '%s', or a constrained model cannot write it" % key)
	assert_true((_sent_schema().get("required", []) as Array).has("deltas"), "and it asks for the list, so a nudge says what it moves")


func test_control_the_guard_schema_alone_had_no_deltas() -> void:
	var from_guard: Dictionary = _llm.to_json_schema(DAEMON.REBALANCE_SCHEMA)
	assert_false((from_guard.get("properties", {}) as Dictionary).has("deltas"), "CONTROL: built from the guard, the wire schema has no deltas: the .805-.811 defect")
	await _propose(NUDGE)
	assert_ne(_sent_schema(), from_guard, "so the daemon does not send that one")


func test_a_delta_names_one_of_the_allowed_constants() -> void:
	var deltas: Dictionary = (DAEMON.wire_schema().get("properties", {}) as Dictionary).get("deltas", {})
	assert_eq(deltas.get("type"), "array")
	assert_eq(int(deltas.get("maxItems", 0)), 1, "the prompt asks for at most ONE adjustment")
	var item: Dictionary = deltas.get("items", {})
	assert_eq(str(item.get("properties", {}).get("constant", {}).get("enum", [])), str(DAEMON.ALLOWED_CONSTANTS), "a delta can only name a dial the daemon may turn")
	assert_eq(item.get("required"), ["constant", "multiplier", "reason"])


func test_a_nudge_that_names_its_change_is_recorded() -> void:
	var r: Dictionary = await _propose(NUDGE)
	assert_true(r["ok"], "a nudge with its list is a proposal")
	assert_eq(str(r["p"].get("verdict", "")), "nudge_easier")
	assert_eq((r["p"].get("deltas", []) as Array).size(), 1)


func test_control_a_nudge_without_its_list_is_still_refused() -> void:
	var r: Dictionary = await _propose(NUDGE_AS_SHIPPED)
	assert_false(r["ok"], "CONTROL: the reply his log shows is still not a proposal; the fix is in what is asked, not in what is accepted")
	assert_eq(str(r["p"].get("fail_reason", "")), "deltas not a list")


func test_control_a_feature_with_no_wire_schema_sends_its_guards() -> void:
	_be.reply = '{"a": "x"}'
	_be.seen.clear()
	var guard := {"a": "String"}
	await _llm.complete_json("Say a.", guard, null)
	assert_eq(_sent_schema(), _llm.to_json_schema(guard), "CONTROL: every other JSON feature's request is unchanged")
	assert_false(_be.seen.is_empty() or _be.seen[0].has("wire_schema"), "and the option itself never reaches a backend")
