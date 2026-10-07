extends GutTest

## Picker step 3: a ready pooled line speaks with its own synthesized audio, after any line written for this exact moment.

const DIR := "user://test_party_line_pool"
const POOLED := "From the pool."
const SETTLE_FRAMES := 5

class ChoiceModel extends LLMBackend:
	var submitted: int = 0
	func backend_id() -> String: return "choice_model"
	func is_ready() -> bool: return true
	func supports_json() -> bool: return true
	func submit(id: String, _p: String, _o: Dictionary = {}) -> void:
		submitted += 1
		(func(): request_finished.emit(id, true, "1", "")).call_deferred()

class ProbeScene extends "res://src/battle/BattleScene.gd":
	var audio_key: String = "unset"
	var voice_stream: AudioStream = null
	var _bubble_sprite_for_test: Node2D = null
	func _get_combatant_sprite(_combatant: Combatant) -> Node2D:
		return _bubble_sprite_for_test
	func _spawn_quip_bubble(_sprite: Node2D, _speaker_name: String, _line: String, _border_color: Color = Color(1.0, 0.85, 0.2), _hold_time: float = 1.5, p_audio_key: String = "", p_voice_stream: AudioStream = null) -> void:
		audio_key = p_audio_key
		voice_stream = p_voice_stream

var _model: ChoiceModel
var _saved := {}
var _heard: Array = []
var _keys: Array = []


func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


func before_each() -> void:
	_wipe()
	_saved = {
		"cast": VoiceService._cast.duplicate(true), "cache": VoiceService.cache, "store": VoicePool.store,
		"tts": GameState.tts_live_enabled, "pld": GameState.party_llm_dialogue_enabled,
		"vel": GameState.game_constants.get("dev_voice_every_line", null),
		"bard": (PartyPersonas._data.get("bard", {}) as Dictionary).duplicate(true),
		"party": BattleManager.player_party.duplicate(), "state": BattleManager.current_state,
		"backends": LLMService._backends.duplicate(), "active": LLMService._active_backend, "llm_on": LLMService.llm_enabled,
	}
	VoicePool.set_process(false)
	VoiceService.cache = VoiceCache.new(DIR, 10_000_000)
	VoiceService._cast = {"bard": {"voice": "bard.wav", "rev": 1}}
	VoicePool.store = VoicePoolStore.new(DIR + "/pool.json")
	VoicePool.store.put("bard", "turn_start", POOLED, "bard.wav", 1)
	VoiceService.cache.write(VoiceCache.key_for("bard.wav", 1, POOLED), WavFixture.tone(0.3, 8000))
	GameState.tts_live_enabled = true
	GameState.party_llm_dialogue_enabled = true
	GameState.game_constants.erase("dev_voice_every_line")
	_set_bard_turn_start(["Scripted bard line."])
	_model = ChoiceModel.new()
	LLMService.cancel_all("pool picker fixture isolation")
	LLMService.add_child(_model)
	LLMService._backends.clear()
	LLMService._backends.append(_model)
	_model.request_finished.connect(LLMService._on_backend_finished)
	LLMService._active_backend = _model
	LLMService.llm_enabled = true
	_heard.clear()
	_keys.clear()
	BattleManager.party_combat_line.connect(_on_line)


func after_each() -> void:
	BattleManager.party_combat_line.disconnect(_on_line)
	LLMService.cancel_all("pool picker fixture teardown")
	_model.request_finished.disconnect(LLMService._on_backend_finished)
	LLMService.remove_child(_model)
	_model.free()
	LLMService._backends.assign(_saved["backends"])
	LLMService._active_backend = _saved["active"]
	LLMService.llm_enabled = _saved["llm_on"]
	BattleManager.current_state = _saved["state"]
	BattleManager.player_party.assign((_saved["party"] as Array).filter(func(c): return is_instance_valid(c)))
	PartyPersonas._data["bard"] = _saved["bard"]
	if _saved["vel"] != null:
		GameState.game_constants["dev_voice_every_line"] = _saved["vel"]
	GameState.tts_live_enabled = _saved["tts"]
	GameState.party_llm_dialogue_enabled = _saved["pld"]
	VoiceService._cast = _saved["cast"]
	VoiceService.cache = _saved["cache"]
	VoicePool.store = _saved["store"]
	VoicePool.set_process(true)
	_wipe()


func _on_line(_who, line, key) -> void:
	_heard.append(str(line))
	_keys.append(str(key))


func _set_bard_turn_start(lines: Array) -> void:
	var entry: Dictionary = (_saved["bard"] as Dictionary).duplicate(true)
	var tv: Dictionary = entry.get("trigger_voices", {})
	tv["turn_start"] = lines
	entry["trigger_voices"] = tv
	PartyPersonas._data["bard"] = entry


func _member(who: String, job: String, alive: bool) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = who
	c.job = {"id": job}
	c.is_alive = alive
	c.max_hp = 100
	c.current_hp = 100 if alive else 0
	return c


func _ask(event_kind: String, fallen_ally: bool = false) -> void:
	var bard := _member("Lyra", "bard", true)
	var party: Array[Combatant] = [bard]
	if fallen_ally:
		party.append(_member("Brom", "fighter", false))
	BattleManager.player_party.assign(party)
	BattleManager.current_state = BattleManager.BattleState.PLAYER_SELECTING
	BattleManager._run_party_line_async(bard, event_kind, {})
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame


func test_a_ready_pooled_line_is_spoken_with_its_token() -> void:
	if SoundManager.wav_commit_refused():
		pending("mixer latched: the pooled audio cannot decode")
		return
	await _ask("turn_start")
	assert_eq(_heard, [POOLED], "the ready pooled line was not the one spoken")
	assert_true(_keys.size() == 1 and str(_keys[0]).begins_with("pool:"), "the pooled line lost its audio token on the way to the bubble: %s" % [_keys])
	assert_false(VoicePool.store.has_line("bard", "turn_start"), "the spoken line stayed in the pool")
	assert_eq(_model.submitted, 0, "a ready pooled line still waited on the model")


func test_a_moment_line_outranks_the_pool() -> void:
	_set_bard_turn_start(["Scripted bard line.", {"line": "Get UP!", "when": "ally_down"}])
	await _ask("turn_start", true)
	assert_eq(_heard, ["Get UP!"], "the pool spoke over a line written for this moment")
	assert_true(VoicePool.store.has_line("bard", "turn_start"), "CONTROL: the pooled line was left for later")


func test_with_party_llm_dialogue_off_the_pool_is_silent() -> void:
	GameState.party_llm_dialogue_enabled = false
	await _ask("turn_start")
	assert_eq(_heard, ["Scripted bard line."], "an LLM-written pooled line played with LLM party dialogue off")
	assert_true(VoicePool.store.has_line("bard", "turn_start"), "the pool spent a line it was not allowed to play")


func test_the_scene_hands_the_bubble_the_pooled_audio() -> void:
	if SoundManager.wav_commit_refused():
		pending("mixer latched: the pooled audio cannot decode")
		return
	var got := VoicePool.take_line("bard", "turn_start")
	assert_false(got.is_empty(), "CONTROL: the planted line must be takeable")
	var scene = ProbeScene.new()
	var sprite := AnimatedSprite2D.new()
	autofree(sprite)
	scene._bubble_sprite_for_test = sprite
	scene._on_party_combat_line(_member("Lyra", "bard", true), str(got.get("line", "")), str(got.get("token", "")))
	assert_not_null(scene.voice_stream, "the bubble got no stream for a pooled line")
	assert_eq(scene.audio_key, "", "a pooled line also asked for a shipped clip key that does not exist")
	scene.free()


func test_control_a_scripted_trigger_still_names_its_clip() -> void:
	var scene = ProbeScene.new()
	var sprite := AnimatedSprite2D.new()
	autofree(sprite)
	scene._bubble_sprite_for_test = sprite
	scene._on_party_combat_line(_member("Lyra", "bard", true), "Scripted bard line.", "turn_start")
	assert_eq(scene.audio_key, "voice_bard_turn_start", "CONTROL: a shipped line's clip key is unchanged")
	assert_null(scene.voice_stream, "CONTROL: a shipped line carries no synthesized stream")
	scene.free()
