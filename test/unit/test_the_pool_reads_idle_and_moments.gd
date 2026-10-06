extends GutTest

## The pool fills only when nothing else is talking to the GPU, and yields to a line written for this exact moment.

var _saved_rogue: Dictionary = {}


func before_each() -> void:
	_saved_rogue = (PartyPersonas._data.get("rogue", {}) as Dictionary).duplicate(true)


func after_each() -> void:
	PartyPersonas._data["rogue"] = _saved_rogue


func _rogue_low_hp(lines: Array) -> void:
	var entry: Dictionary = _saved_rogue.duplicate(true)
	var tv: Dictionary = entry.get("trigger_voices", {})
	tv["low_hp"] = lines
	entry["trigger_voices"] = tv
	PartyPersonas._data["rogue"] = entry


func _ctx(party: Array) -> PartyCombatLineContext:
	var c := PartyCombatLineContext.new()
	c.speaker_name = "Vex"
	c.party = party
	c.enemies = [{"name": "Slime", "hp_pct": 100.0}]
	return c


func test_llm_idle_reads_the_inflight_request() -> void:
	var saved_id: String = LLMService._inflight_id
	var saved_queue: Array[Dictionary] = LLMService._queue.duplicate()
	LLMService._queue.clear()
	LLMService._inflight_id = ""
	var idle := LLMService.is_idle()
	LLMService._inflight_id = "busy"
	var busy := not LLMService.is_idle()
	LLMService._inflight_id = ""
	LLMService._queue.append({"id": "queued"})
	var queued := not LLMService.is_idle()
	LLMService._inflight_id = saved_id
	LLMService._queue.assign(saved_queue)
	assert_true(idle, "nothing in flight and nothing queued must read idle")
	assert_true(busy, "an in-flight request read as idle")
	assert_true(queued, "a queued request read as idle")


func test_voice_busy_reads_pending_synthesis() -> void:
	var saved: Dictionary = VoiceService._pending.duplicate()
	VoiceService._pending = {}
	var idle := not VoiceService.is_busy()
	VoiceService._pending = {"tts_1": {}}
	var busy := VoiceService.is_busy()
	VoiceService._pending = saved
	assert_true(idle, "no synthesis pending read as busy")
	assert_true(busy, "a synthesis in flight read as idle")


func test_a_moment_line_is_seen_only_when_its_moment_holds() -> void:
	_rogue_low_hp(["Generic.", {"line": "Get up!", "when": "ally_down"}])
	var down := _ctx([{"name": "Vex", "job_id": "rogue", "hp_pct": 20.0, "is_alive": true},
		{"name": "Mira", "job_id": "cleric", "hp_pct": 0.0, "is_alive": false}])
	var standing := _ctx([{"name": "Vex", "job_id": "rogue", "hp_pct": 20.0, "is_alive": true},
		{"name": "Mira", "job_id": "cleric", "hp_pct": 80.0, "is_alive": true}])
	assert_true(PartyPersonas.has_moment_line("rogue", "low_hp", down), "an ally is down and a line for that moment exists")
	assert_false(PartyPersonas.has_moment_line("rogue", "low_hp", standing), "no ally is down, so the moment line must not outrank the pool")


func test_a_precondition_is_not_a_moment() -> void:
	_rogue_low_hp(["Generic.", {"line": "Cleric, now.", "when": "ally_alive:cleric"}])
	var ctx := _ctx([{"name": "Vex", "job_id": "rogue", "hp_pct": 20.0, "is_alive": true},
		{"name": "Mira", "job_id": "cleric", "hp_pct": 80.0, "is_alive": true}])
	assert_false(PartyPersonas.has_moment_line("rogue", "low_hp", ctx),
		"a precondition line (true in most fights) outranked the pool, which would keep the pool silent")


func test_the_pooled_prompt_forbids_names_and_states() -> void:
	var p := DialoguePrompts.build_pooled_party_line("A wry bard.", ["Encore!"], "bard", "turn_start", ["Tempo up."])
	for must in ["turn_start", "Do NOT name anyone", "Tempo up.", "A wry bard."]:
		assert_string_contains(p, must)
