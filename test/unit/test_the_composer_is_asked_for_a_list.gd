extends GutTest

## Engine path, shipped .814, llama3, real kits: 12 of 12 Rule Composer requests came back "could not be read as rules".
## The request's schema was built from the guard, where rules_json is "any value", and the model wrote ONE object each
## time. The composer now sends its own schema: rules_json is a list of at least one rule, each with its conditions,
## actions and enabled flag. Measured on the server itself: a step without additionalProperties loses op, value, id and
## target ({"type": "hp_percent"} and nothing else), so each step says it may carry more.

const DP := preload("res://src/llm/DialoguePrompts.gd")

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
	_llm.cancel_all("composer list fixture isolation")
	_llm.clear_cache()
	_be = ReplyModel.new()
	_be.reply = '{"name": "n", "description": "d", "rules_json": [{"conditions": [{"type": "always"}], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]}'
	_llm.add_child(_be)
	_llm._backends.clear()
	_llm._backends.append(_be)
	_be.request_finished.connect(_llm._on_backend_finished)
	_llm._active_backend = _be


func after_each() -> void:
	_llm.cancel_all("composer list fixture teardown")
	_be.request_finished.disconnect(_llm._on_backend_finished)
	_llm.remove_child(_be)
	_be.free()
	_llm._backends.clear()
	for b in _orig_backends:
		_llm._backends.append(b)
	_llm._active_backend = _orig_active
	_llm.llm_enabled = _orig_enabled
	_llm.clear_cache()


func _sent_schema() -> Dictionary:
	if _be.seen.is_empty() or not (_be.seen[0].get("json_schema") is Dictionary):
		return {}
	return _be.seen[0]["json_schema"]


func _rules_spec(schema: Dictionary) -> Dictionary:
	var spec: Variant = (schema.get("properties", {}) as Dictionary).get("rules_json", {})
	return spec if spec is Dictionary else {}


func test_the_composer_asks_for_a_list_of_rules() -> void:
	await _rc.compose_async(_rc.DOMAIN_AUTOBATTLE, "always attack", "fighter", [])
	assert_false(_sent_schema().is_empty(), "CONTROL: the composer's request carried a schema")
	var rules: Dictionary = _rules_spec(_sent_schema())
	assert_eq(str(rules.get("type", "")), "array", "rules_json is a LIST on the wire, so a constrained model cannot answer with one object")
	assert_gt(int(rules.get("minItems", 0)), 0, "and an empty list is not an answer")
	var rule: Dictionary = rules.get("items", {}) if rules.get("items", {}) is Dictionary else {}
	for key in ["conditions", "actions", "enabled"]:
		assert_true((rule.get("required", []) as Array).has(key), "each rule carries its %s" % key)
		assert_true((rule.get("properties", {}) as Dictionary).has(key), "and the server is told what %s is" % key)


func test_control_the_guard_alone_asked_for_any_value() -> void:
	var from_guard: Dictionary = _llm.to_json_schema(DP.SCHEMA_RULE_COMPOSITION)
	assert_eq(_rules_spec(from_guard), {}, "CONTROL: built from the guard, rules_json is unconstrained: the shipped request")
	await _rc.compose_async(_rc.DOMAIN_AUTOBATTLE, "always attack", "fighter", [])
	assert_ne(_sent_schema(), from_guard, "so the composer does not send that one")


func test_a_condition_or_action_may_carry_more_than_its_type() -> void:
	var rule: Dictionary = _rules_spec(DP.rule_composition_wire_schema()).get("items", {})
	for list_key in ["conditions", "actions"]:
		var step: Dictionary = ((rule.get("properties", {}) as Dictionary).get(list_key, {}) as Dictionary).get("items", {})
		assert_true((step.get("required", []) as Array).has("type"), "every %s entry names its type" % list_key)
		assert_eq(step.get("additionalProperties", false), true, "%s: without this a constraining server drops op, value, id and target" % list_key)
	var actions: Dictionary = (rule.get("properties", {}) as Dictionary).get("actions", {})
	assert_gt(int(actions.get("minItems", 0)), 0, "a rule that does nothing is not a rule")


func test_every_key_the_validator_reads_is_on_the_wire() -> void:
	var schema: Dictionary = DP.rule_composition_wire_schema()
	for key in DP.SCHEMA_RULE_COMPOSITION.keys():
		assert_true((schema.get("properties", {}) as Dictionary).has(key), "'%s' is in the guard, so it is in the wire schema" % key)
		assert_true((schema.get("required", []) as Array).has(key))
	assert_eq(DP.SCHEMA_RULE_COMPOSITION.size(), 3, "CONTROL: three keys judged")
