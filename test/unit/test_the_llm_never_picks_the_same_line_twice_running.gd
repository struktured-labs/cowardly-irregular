extends GutTest

## Measured on llama3: with the LLM choosing, every party trigger said ONE line 50/50 times (choose() cached the prompt; the model favours option 1).

var _svc: Node = null
var _be = null
var _orig_backends: Array = []
var _orig_active = null
var _orig_enabled: bool = true
var _saved_rogue: Dictionary = {}
var _saved_last: Dictionary = {}
var _saved_recent: Dictionary = {}
var _saved_party: Array = []
var _saved_llm_dialogue: bool = false


## Both biases measured on llama3: always option "1", or (uncached, shuffled) one favourite line whenever it is offered.
class StubModel extends LLMBackend:
	var submitted: int = 0
	var favourite: String = ""
	func backend_id() -> String: return "stub_model"
	func is_ready() -> bool: return true
	func submit(id: String, p: String, _o: Dictionary = {}) -> void:
		submitted += 1
		var answer := "1"
		for row in p.split("\n"):
			if not favourite.is_empty() and row.ends_with(". " + favourite):
				answer = row.get_slice(".", 0)
		_emit.call_deferred(id, answer)
	func _emit(id: String, answer: String) -> void:
		request_finished.emit(id, true, answer, "")


func before_each() -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	assert_not_null(_svc, "CONTROL: LLMService autoload must exist")
	_orig_enabled = _svc.llm_enabled
	_orig_backends = _svc._backends.duplicate()
	_orig_active = _svc._active_backend
	_svc.llm_enabled = true
	_svc.cancel_all("choice-variety fixture isolation")
	_be = StubModel.new()
	_be.name = "StubModelBE"
	_svc.add_child(_be)
	_svc._backends.clear()
	_svc._backends.append(_be)
	_be.request_finished.connect(_svc._on_backend_finished)
	_svc._active_backend = _be
	_saved_rogue = (PartyPersonas._data.get("rogue", {}) as Dictionary).duplicate(true)
	_saved_last = PartyPersonas._last_variant.duplicate()
	_saved_recent = PartyPersonas._recent_spoken.duplicate(true)
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
	PartyPersonas._recent_spoken = _saved_recent
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


func _pool_indices(n: int, recent: Array) -> Array:
	var idx: Array = VoiceLines.choice_pool(_entries(n), recent).map(func(e): return int(e["index"]))
	idx.sort()
	return idx


func test_the_pool_drops_the_line_spoken_last_while_two_remain() -> void:
	var src: Array = _entries(4)
	VoiceLines.choice_pool(src, [2])
	assert_eq(src.size(), 4, "the caller's list is not modified")
	assert_eq(_pool_indices(4, [2]), [0, 1, 3], "the line spoken last time must not be offered again")
	assert_eq(_pool_indices(2, [0]), [1], "two lines alternate")
	assert_eq(_pool_indices(1, [0]), [0], "a sole line is still offered")


func test_the_pool_drops_the_most_recent_half() -> void:
	assert_eq(_pool_indices(10, [9, 8, 7, 6, 5, 4]), [0, 1, 2, 3, 9],
		"of ten lines, the five spoken most recently sit out; older history does not")


func test_the_pool_order_changes_between_calls() -> void:
	var firsts := {}
	for i in 40:
		firsts[int(VoiceLines.choice_pool(_entries(6), [])[0]["index"])] = true
	assert_gt(firsts.size(), 1, "a fixed order hands a model that favours option 1 the same line every call")


func _turns(n: int) -> Array:
	var entry: Dictionary = _saved_rogue.duplicate(true)
	var tv: Dictionary = entry.get("trigger_voices", {})
	tv["turn_start"] = ["L0.", "L1.", "L2.", "L3.", "L4.", "L5."]
	entry["trigger_voices"] = tv
	PartyPersonas._data["rogue"] = entry
	PartyPersonas._last_variant.clear()
	PartyPersonas._recent_spoken.clear()
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
	for i in n:
		await BattleManager._run_party_line_async(c, "turn_start", {})
	BattleManager.party_combat_line.disconnect(cb)
	assert_eq(_be.submitted, n, "VOID unless every line went through the model: %d of %d did" % [_be.submitted, n])
	return heard


func test_a_model_that_always_answers_1_still_varies_the_line() -> void:
	var heard: Array = await _turns(60)
	var repeats := 0
	for i in range(1, heard.size()):
		if heard[i] == heard[i - 1]:
			repeats += 1
	var distinct := {}
	for h in heard:
		distinct[h] = true
	assert_eq(heard.size(), 60)
	assert_eq(repeats, 0, "the same line twice running: %s" % [heard])
	assert_eq(distinct.size(), 6, "every line must be heard; unshuffled, option 1 cycles through the first four: %s" % [heard])


func test_a_favourite_line_comes_back_at_most_once_in_four_turns() -> void:
	## Measured after the first fix: the Fighter's favourite line played 25 of 50 turns, every other turn.
	_be.favourite = "L2."
	var heard: Array = await _turns(40)
	var fav: int = heard.count("turn_start_2")
	assert_eq(heard[0], "turn_start_2", "VOID unless the stub's favourite is actually favoured: turn 1 offers all six")
	assert_true(fav <= 10, "six lines, three sit out: the favourite can play once in four turns at most, heard %d of 40" % fav)


func test_the_party_line_asks_uncached_and_records_what_was_spoken() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var at: int = src.find("func _run_party_line_async")
	var body: String = src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_true(body.contains('llm.choose(choice_prompt, labels, fb_label, {"cache": false})'),
		"a cached choice replays one line for five minutes whenever the prompt repeats")
	var emit_at: int = body.find("_emit_party_line(combatant, str(chosen[\"line\"])")
	assert_gt(emit_at, -1)
	assert_true(body.contains("VoiceLines.choice_pool(pp.eligible_trigger_entries(job_id, event_kind, ctx), pp.recent_spoken(job_id, event_kind))"),
		"the LLM must be offered the pool minus what was spoken recently")
	assert_gt(body.find("pp.mark_spoken(job_id, event_kind, int(chosen[\"index\"]))"), -1,
		"no-repeat memory must record the LLM's pick, not the random fallback it replaced")
