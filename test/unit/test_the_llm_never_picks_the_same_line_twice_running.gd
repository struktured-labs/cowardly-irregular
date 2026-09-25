extends GutTest

## Measured on llama3: with the LLM choosing, every party trigger said ONE line 50/50 times (choose() cached the prompt; the model favours option 1).

var _svc: Node = null
var _be = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true
var _saved_rogue: Dictionary = {}
var _saved_last: Dictionary = {}
var _saved_party: Array = []
var _saved_llm_dialogue: bool = false


## The worst case measured: a model that always answers "1".
class AlwaysOne extends LLMBackend:
	var submitted: int = 0
	func backend_id() -> String: return "always_one"
	func is_ready() -> bool: return true
	func submit(id: String, _p: String, _o: Dictionary = {}) -> void:
		submitted += 1
		_emit.call_deferred(id)
	func _emit(id: String) -> void:
		request_finished.emit(id, true, "1", "")


func before_each() -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist")
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_svc.cancel_all("choice-variety fixture isolation")
	_be = AlwaysOne.new()
	_be.name = "AlwaysOneBE"
	_svc.add_child(_be)
	_svc._backends.clear()
	_svc._backends.append(_be)
	_be.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _be
	_saved_rogue = (PartyPersonas._data.get("rogue", {}) as Dictionary).duplicate(true)
	_saved_last = PartyPersonas._last_variant.duplicate()
	_saved_party = BattleManager.player_party.duplicate()
	_saved_llm_dialogue = GameState.party_llm_dialogue_enabled


func after_each() -> void:
	_be.request_finished.disconnect(_svc._on_backend_finished)
	_svc.remove_child(_be)
	_be.free()
	_svc._backends.clear()
	for b in _orig_backends:
		_svc._backends.append(b)
	_svc._active_backend = _orig_active
	_svc.llm_enabled = _orig_enabled
	_svc.clear_cache()
	PartyPersonas._data["rogue"] = _saved_rogue
	PartyPersonas._last_variant = _saved_last
	BattleManager.player_party.assign(_saved_party.filter(func(c): return is_instance_valid(c)))
	GameState.party_llm_dialogue_enabled = _saved_llm_dialogue


func _entries(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"index": i, "line": "L%d" % i, "tags": []})
	return out


func test_choose_without_cache_asks_the_model_every_time() -> void:
	await _svc.choose("same prompt", ["1", "2"] as Array[String], "2", {"cache": false})
	await _svc.choose("same prompt", ["1", "2"] as Array[String], "2", {"cache": false})
	assert_eq(_be.submitted, 2, "an uncached choice must reach the model on every call")


func test_control_choose_still_caches_by_default() -> void:
	await _svc.choose("same prompt", ["1", "2"] as Array[String], "2")
	await _svc.choose("same prompt", ["1", "2"] as Array[String], "2")
	assert_eq(_be.submitted, 1, "CONTROL: the default is unchanged, so the opt-out is what the party line relies on")


func test_the_pool_drops_the_line_spoken_last_while_two_remain() -> void:
	var src: Array = _entries(4)
	var pool: Array = VoiceLines.choice_pool(src, 2)
	var idx: Array = pool.map(func(e): return int(e["index"]))
	idx.sort()
	assert_eq(idx, [0, 1, 3], "the line spoken last time must not be offered again")
	assert_eq(src.size(), 4, "the caller's list is not modified")
	assert_eq(VoiceLines.choice_pool(_entries(1), 0).size(), 1, "a sole line is still offered")


func test_the_pool_order_changes_between_calls() -> void:
	var firsts := {}
	for i in 40:
		firsts[int(VoiceLines.choice_pool(_entries(6), -1)[0]["index"])] = true
	assert_gt(firsts.size(), 1, "a fixed order hands a model that favours option 1 the same line every call")


func test_a_model_that_always_answers_1_still_varies_the_line() -> void:
	var entry: Dictionary = _saved_rogue.duplicate(true)
	var tv: Dictionary = entry.get("trigger_voices", {})
	tv["turn_start"] = ["L0.", "L1.", "L2.", "L3.", "L4.", "L5."]
	entry["trigger_voices"] = tv
	PartyPersonas._data["rogue"] = entry
	PartyPersonas._last_variant.clear()
	GameState.party_llm_dialogue_enabled = true
	GameState.game_constants.erase("dev_voice_every_line")
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "VarietyRogue"
	c.job = {"id": "rogue"}
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	BattleManager.player_party.assign([c] as Array[Combatant])
	var heard: Array = []
	var cb := func(_who, _line, key): heard.append(str(key))
	BattleManager.party_combat_line.connect(cb)
	for i in 40:
		await BattleManager._run_party_line_async(c, "turn_start", {})
	BattleManager.party_combat_line.disconnect(cb)
	assert_eq(_be.submitted, 40, "VOID unless every line went through the model: %d of 40 did" % _be.submitted)
	var repeats := 0
	for i in range(1, heard.size()):
		if heard[i] == heard[i - 1]:
			repeats += 1
	var distinct := {}
	for h in heard:
		distinct[h] = true
	assert_eq(heard.size(), 40)
	assert_eq(repeats, 0, "the same line twice running: %s" % [heard])
	assert_gt(distinct.size(), 2, "only %d distinct lines in 40 turns: %s" % [distinct.size(), heard])


func test_the_party_line_asks_uncached_and_records_what_was_spoken() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var at: int = src.find("func _run_party_line_async")
	var body: String = src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_true(body.contains('llm.choose(choice_prompt, labels, fb_label, {"cache": false})'),
		"a cached choice replays one line for five minutes whenever the prompt repeats")
	var emit_at: int = body.find("_emit_party_line(combatant, str(chosen[\"line\"])")
	assert_gt(emit_at, -1)
	assert_gt(body.find("pp.mark_spoken(job_id, event_kind, int(chosen[\"index\"]))"), -1,
		"no-repeat memory must record the LLM's pick, not the random fallback it replaced")
