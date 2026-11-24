extends GutTest

## Engine path, llama3, real kits, 4 asks x3 (2026-11-23): with the guard's schema (.815 as shipped) 9 of 12 Rule Composer
## replies could be read and none kept two rules apart; with a list schema of its own, 10 of 12 and 6; with NO schema,
## plain JSON mode as every request was before .805, 12 of 12 and 10. The composer now asks in plain JSON mode.

var _llm: Node
var _rc: Node
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
	_rc = get_tree().root.get_node("RuleComposer")
	_orig_enabled = _llm.llm_enabled
	_orig_backends = _llm._backends.duplicate()
	_orig_active = _llm._active_backend
	_llm.llm_enabled = true
	_llm.cancel_all("plain json fixture isolation")
	_llm.clear_cache()
	_be = ReplyModel.new()
	_be.reply = '{"name": "n", "description": "d", "rules_json": [{"conditions": [{"type": "always"}], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]}'
	_llm.add_child(_be)
	_llm._backends.clear()
	_llm._backends.append(_be)
	_be.request_finished.connect(_llm._on_backend_finished)
	_llm._active_backend = _be


func after_each() -> void:
	_llm.cancel_all("plain json fixture teardown")
	_be.request_finished.disconnect(_llm._on_backend_finished)
	_llm.remove_child(_be)
	_be.free()
	_llm._backends.clear()
	for b in _orig_backends:
		_llm._backends.append(b)
	_llm._active_backend = _orig_active
	_llm.llm_enabled = _orig_enabled
	_llm.clear_cache()


func _first_sent() -> Dictionary:
	return _be.seen[0] if not _be.seen.is_empty() and _be.seen[0] is Dictionary else {}


func test_the_composer_asks_for_json_without_a_schema() -> void:
	var out: Dictionary = await _rc.compose_async(_rc.DOMAIN_AUTOBATTLE, "always attack", "fighter", [])
	assert_eq(_be.seen.size(), 1, "CONTROL: the composer sent one request")
	assert_true(bool(_first_sent().get("json_mode", false)), "it still asks for JSON")
	var schema: Variant = _first_sent().get("json_schema", {})
	assert_true(not (schema is Dictionary) or (schema as Dictionary).is_empty(), "and sends no schema: under one, llama3 kept fewer rules apart: %s" % str(schema).left(120))
	assert_false(_first_sent().has(_llm.PLAIN_JSON), "the option itself never reaches a backend")
	assert_eq(str(out.get("source", "")), "llm", "CONTROL: the reply is read as rules")


func test_control_every_other_json_request_keeps_its_schema() -> void:
	var guard := {"a": "String"}
	await _llm.complete_json("Say a.", guard, null)
	assert_eq(_first_sent().get("json_schema", {}), _llm.to_json_schema(guard), "CONTROL: a request without the option still carries its guard's schema")
	_be.seen.clear()
	await _llm.complete_json("Say a.", guard, null, {"wire_schema": {"type": "object", "properties": {"a": {"type": "string"}}}})
	assert_false((_first_sent().get("json_schema", {}) as Dictionary).is_empty(), "CONTROL: and a feature's own wire schema, the daemon's shape, still goes out")


func test_on_the_wire_the_composer_request_is_plain_json() -> void:
	var opts: Dictionary = {"json_mode": true}
	var ollama := HTTPBackend.new()
	ollama.api_format = "ollama"
	ollama.model = "m"
	autofree(ollama)
	var body: Dictionary = JSON.parse_string(ollama._build_body("Compose.", opts))
	assert_eq(body.get("format"), "json", "Ollama gets format json, not a schema")
	var openai := HTTPBackend.new()
	openai.api_format = "openai"
	openai.model = "m"
	autofree(openai)
	var obody: Dictionary = JSON.parse_string(openai._build_body("Compose.", opts))
	assert_eq(obody.get("response_format"), {"type": "json_object"}, "an OpenAI server gets json_object, not json_schema")
