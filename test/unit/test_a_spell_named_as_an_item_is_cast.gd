extends GutTest

## Engine path, llama3, real kits (2026-11-23): a Cleric's rule came back as {"type": "item", "id": "cure"} and a Mage's
## as {"type": "item", "id": "channel"}. Neither is an item, the deep check said "unknown item", and the rule was lost.
## An item action naming a spell of THIS character's kit, and no item, is now read as that spell.

var _llm: Node
var _rc: Node
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
	_rc = get_tree().root.get_node("RuleComposer")
	_orig_enabled = _llm.llm_enabled
	_orig_backends = _llm._backends.duplicate()
	_orig_active = _llm._active_backend
	_llm.llm_enabled = true
	_llm.cancel_all("spell as item fixture isolation")
	_llm.clear_cache()
	_be = ReplyModel.new()
	_llm.add_child(_be)
	_llm._backends.clear()
	_llm._backends.append(_be)
	_be.request_finished.connect(_llm._on_backend_finished)
	_llm._active_backend = _be


func after_each() -> void:
	_llm.cancel_all("spell as item fixture teardown")
	_be.request_finished.disconnect(_llm._on_backend_finished)
	_llm.remove_child(_be)
	_be.free()
	_llm._backends.clear()
	for b in _orig_backends:
		_llm._backends.append(b)
	_llm._active_backend = _orig_active
	_llm.llm_enabled = _orig_enabled
	_llm.clear_cache()


## Composes for `who` with a reply whose first rule's one action is `action`, followed by a plain attack rule.
func _compose(who: String, action: Dictionary) -> Dictionary:
	var first := {"conditions": [{"type": "ally_hp_percent", "op": "<", "value": 50}], "actions": [action], "enabled": true}
	var second := {"conditions": [{"type": "always"}], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}
	_be.reply = JSON.stringify({"name": "n", "description": "d", "rules_json": [first, second]})
	_llm.clear_cache()
	return await _rc.compose_async(_rc.DOMAIN_AUTOBATTLE, "heal, otherwise attack", who, [])


func _actions(out: Dictionary) -> Array:
	var acts: Array = []
	for r in (out.get("rules", []) as Array):
		for a in ((r as Dictionary).get("actions", []) as Array):
			acts.append(a)
	return acts


func _has_action(out: Dictionary, type: String, id: String) -> bool:
	for a in _actions(out):
		if str((a as Dictionary).get("type", "")) == type and str((a as Dictionary).get("id", "")) == id:
			return true
	return false


func _noted(out: Dictionary, needle: String) -> bool:
	for n in (out.get("notes", []) as Array):
		if str(n).contains(needle):
			return true
	return false


func test_a_clerics_item_cure_is_the_cure_spell() -> void:
	var out: Dictionary = await _compose("cleric", {"type": "item", "id": "cure", "target": "lowest_hp_ally"})
	assert_eq(str(out.get("source", "")), "llm", "the composition is read, not refused: %s" % str(out.get("errors", [])))
	assert_eq((out.get("rules", []) as Array).size(), 2, "both rules survive")
	assert_true(_has_action(out, "ability", "cure"), "the heal is cast as cure")
	assert_false(_has_action(out, "item", "cure"), "and no item action named cure is left")
	assert_true(_noted(out, "Read item 'cure'"), "the player is told what was changed")


func test_a_mages_item_channel_is_the_free_move() -> void:
	var out: Dictionary = await _compose("mage", {"type": "item", "id": "channel", "target": "self"})
	assert_eq(str(out.get("source", "")), "llm", "the composition is read: %s" % str(out.get("errors", [])))
	assert_true(_has_action(out, "ability", "channel"), "channel, the mage's free move, is cast")


func test_control_a_real_item_stays_an_item() -> void:
	var out: Dictionary = await _compose("cleric", {"type": "item", "id": "potion", "target": "lowest_hp_ally"})
	assert_eq(str(out.get("source", "")), "llm", "CONTROL: a potion rule is read: %s" % str(out.get("errors", [])))
	assert_true(_has_action(out, "item", "potion"), "CONTROL: a potion is still used as an item")
	assert_false(_noted(out, "Read item 'potion'"), "CONTROL: and nothing claims to have changed it")


func test_control_a_spell_outside_this_kit_is_not_rewritten() -> void:
	var out: Dictionary = await _compose("cleric", {"type": "item", "id": "fire", "target": "lowest_hp_enemy"})
	assert_false(_noted(out, "Read item 'fire'"), "CONTROL: fire is not the cleric's, so it is not read as her spell")
	assert_false(_has_action(out, "ability", "fire"), "CONTROL: and no cleric rule casts fire")
	var refused_as_item := false
	for e in (out.get("errors", []) as Array):
		refused_as_item = refused_as_item or str(e).contains("unknown item 'fire'")
	assert_true(refused_as_item, "CONTROL: it is still refused as the unknown item it is: %s" % str(out.get("errors", [])))
