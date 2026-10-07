extends GutTest

## The ready pool writes, checks, synthesizes and stores one line at a time, only when the GPU is free, and never one that names anybody.

const Replay := preload("res://tools/replay_tts_backend.gd")
const DIR := "user://test_voice_pool_cache"

class JsonModel extends LLMBackend:
	var reply: String = "{\"line\": \"Steady hands, loud heart.\", \"mood\": \"neutral\"}"
	var submitted: int = 0
	var last_prompt: String = ""
	func backend_id() -> String: return "json_model"
	func is_ready() -> bool: return true
	func supports_json() -> bool: return true
	func submit(id: String, p: String, _o: Dictionary = {}) -> void:
		submitted += 1
		last_prompt = p
		var r := reply
		(func(): request_finished.emit(id, true, r, "")).call_deferred()

var _model: JsonModel
var _replay
var _saved := {}


func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


func before_each() -> void:
	_wipe()
	_saved = {
		"cast": VoiceService._cast.duplicate(true), "cache": VoiceService.cache, "web": VoiceService.is_web,
		"store": VoicePool.store, "tts": GameState.tts_live_enabled, "pld": GameState.party_llm_dialogue_enabled,
		"party": GameState.player_party.duplicate(true), "backends": LLMService._backends.duplicate(),
		"active": LLMService._active_backend, "llm_on": LLMService.llm_enabled,
		"bard_persona": (PartyPersonas._data.get("bard", {}) as Dictionary).duplicate(true),
	}
	var persona: Dictionary = (_saved["bard_persona"] as Dictionary).duplicate(true)
	persona["signature_phrases"] = ["Hold for applause. No? Tough room.", "Verse two, with feeling!"]
	PartyPersonas._data["bard"] = persona
	VoiceService.cache = VoiceCache.new(DIR, 10_000_000)
	VoiceService._cast = {"bard": {"voice": "bard.wav", "rev": 1}}
	_replay = Replay.new()
	_replay.next_wav = WavFixture.tone(0.3, 8000)
	VoiceService.install_backend(_replay)
	VoicePool.store = VoicePoolStore.new(DIR + "/pool.json")
	VoicePool.discarded = 0
	VoicePool.repeated = 0
	VoicePool._retry_after_msec = 0
	VoicePool._recent = {}
	VoicePool.set_process(false)
	GameState.tts_live_enabled = true
	GameState.party_llm_dialogue_enabled = true
	GameState.player_party.assign([{"name": "Brom", "job_id": "fighter"}, {"name": "Lyra", "job_id": "bard"}])
	_model = JsonModel.new()
	LLMService.add_child(_model)
	LLMService._backends.clear()
	LLMService._backends.append(_model)
	_model.request_finished.connect(LLMService._on_backend_finished)
	LLMService._active_backend = _model
	LLMService.llm_enabled = true


func after_each() -> void:
	LLMService.cancel_all("voice pool test teardown")
	_model.request_finished.disconnect(LLMService._on_backend_finished)
	LLMService.remove_child(_model)
	_model.free()
	LLMService._backends.assign(_saved["backends"])
	LLMService._active_backend = _saved["active"]
	LLMService.llm_enabled = _saved["llm_on"]
	VoiceService._cast = _saved["cast"]
	VoiceService.cache = _saved["cache"]
	VoiceService.is_web = _saved["web"]
	VoiceService.apply_config()
	VoicePool.store = _saved["store"]
	VoicePool._retry_after_msec = 0
	VoicePool.set_process(true)
	GameState.tts_live_enabled = _saved["tts"]
	GameState.party_llm_dialogue_enabled = _saved["pld"]
	GameState.player_party.assign(_saved["party"])
	PartyPersonas._data["bard"] = _saved["bard_persona"]
	_wipe()


func test_the_most_frequent_trigger_fills_first_for_a_cast_party_member() -> void:
	assert_eq(VoicePool.next_empty_slot(), ["bard", "turn_start"],
		"the pool must fill the bard's turn_start first: the fighter is not cast and victory fires once a battle")


func test_every_speaker_gets_the_common_trigger_before_anyone_gets_a_rare_one() -> void:
	VoiceService._cast["mage"] = {"voice": "mage.wav", "rev": 1}
	GameState.player_party.append({"name": "Quill", "job_id": "mage"})
	VoicePool.store.put("bard", "turn_start", "Tempo up.", "bard.wav", 1)
	assert_eq(VoicePool.next_empty_slot(), ["mage", "turn_start"],
		"the bard got a rarer line while the mage had nothing for the trigger every battle fires")


func test_a_slot_fills_and_is_redeemed_once() -> void:
	if SoundManager.wav_commit_refused():
		pending("mixer latched: a synthesized line cannot decode")
		return
	assert_true(await VoicePool.fill_slot("bard", "turn_start"), "CONTROL: the fill succeeded")
	assert_true(VoicePool.store.has_line("bard", "turn_start"), "the filled line was not stored")
	var got := VoicePool.take_line("bard", "turn_start")
	assert_eq(got.get("line", ""), "Steady hands, loud heart.")
	var stream := VoicePool.claim_stream(str(got.get("token", "")))
	assert_not_null(stream, "the token did not redeem the synthesized audio")
	assert_null(VoicePool.claim_stream(str(got.get("token", ""))), "a token redeemed twice")
	assert_false(VoicePool.store.has_line("bard", "turn_start"), "a used line stayed ready, so it would play again")


func test_a_line_naming_a_party_member_is_never_synthesized() -> void:
	_model.reply = "{\"line\": \"Brom, hold the line!\", \"mood\": \"neutral\"}"
	assert_false(await VoicePool.fill_slot("bard", "turn_start"), "a line naming an ally was pooled")
	assert_eq(VoicePool.discarded, 1)
	assert_eq(_replay.requests.size(), 0, "the discarded line was sent to the TTS server anyway")


func test_nothing_fills_while_the_llm_is_busy() -> void:
	VoicePool._retry_after_msec = 0
	assert_true(VoicePool.can_fill(), "CONTROL: an idle LLM and a ready server must allow a fill")
	LLMService._inflight_id = "someone_else"
	var can := VoicePool.can_fill()
	LLMService._inflight_id = ""
	assert_false(can, "the pool would fill while the LLM is busy, a burst on a shared GPU")


func test_the_pool_is_off_on_web_and_when_either_toggle_is_off() -> void:
	assert_true(VoicePool.is_enabled(), "CONTROL: both toggles on, desktop")
	GameState.party_llm_dialogue_enabled = false
	assert_false(VoicePool.is_enabled(), "LLM party dialogue off, yet the pool would play LLM-written lines")
	GameState.party_llm_dialogue_enabled = true
	VoiceService.is_web = true
	assert_false(VoicePool.is_enabled(), "the web build would use the pool")


func test_an_idle_pool_fills_on_its_own() -> void:
	if SoundManager.wav_commit_refused():
		pending("mixer latched: a synthesized line cannot decode")
		return
	VoicePool.set_process(true)
	var t0 := Time.get_ticks_msec()
	while not VoicePool.store.has_line("bard", "turn_start") and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	VoicePool.set_process(false)
	while VoicePool._filling and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
	assert_true(VoicePool.store.has_line("bard", "turn_start"), "an idle pool with a ready server never filled its first slot")


## cowir-story 2026-10-06: a line may never be heard twice from one speaker, whatever slot it came from.
func test_a_line_already_pooled_in_another_slot_is_never_synthesized_again() -> void:
	VoicePool.store.put("bard", "big_hit_taken", "Tempo up.", "bard.wav", 1)
	_model.reply = "{\"line\": \"TEMPO up!\", \"mood\": \"neutral\"}"
	assert_false(await VoicePool.fill_slot("bard", "turn_start"), "the same line, punctuated differently, was pooled twice for one speaker")
	assert_eq(VoicePool.repeated, 1)
	assert_eq(_replay.requests.size(), 0, "the repeat was sent to the TTS server anyway")


func test_a_spoken_line_is_not_pooled_again_this_session() -> void:
	VoicePool._recent = {"bard|victory": ["Encore, encore."]}
	_model.reply = "{\"line\": \"Encore, encore.\", \"mood\": \"neutral\"}"
	assert_false(await VoicePool.fill_slot("bard", "turn_start"), "a line the bard already said this session came back")


func test_only_one_pooled_line_per_speaker_quotes_a_signature_phrase() -> void:
	if SoundManager.wav_commit_refused():
		pending("mixer latched: a synthesized line cannot decode")
		return
	_model.reply = "{\"line\": \"Verse two, with feeling!\", \"mood\": \"neutral\"}"
	assert_true(await VoicePool.fill_slot("bard", "turn_start"), "CONTROL: the first signature line fills")
	VoicePool._retry_after_msec = 0
	_model.reply = "{\"line\": \"Hold for applause!\", \"mood\": \"neutral\"}"
	assert_false(await VoicePool.fill_slot("bard", "big_hit_taken"), "a second line quoting a whole sentence of a signature phrase joined the pool")
	assert_false(VoicePool.store.has_line("bard", "big_hit_taken"))


func test_the_prompt_avoids_the_speakers_other_slots() -> void:
	VoicePool.store.put("bard", "victory", "Bow and curtain.", "bard.wav", 1)
	await VoicePool.fill_slot("bard", "turn_start")
	assert_string_contains(_model.last_prompt, "Bow and curtain.", "the model was not told what this speaker already has ready")


## cowir-story 2026-10-06: a quote is a whole SENTENCE of the phrase; shared vocabulary ("the Loop") is the persona, not a repeat.
func test_control_shared_vocabulary_is_not_a_quote() -> void:
	var cleric := ["The Loop provides. Hold still."]
	assert_true(VoicePool.quotes_phrase("The Loop provides.", cleric), "CONTROL: one whole sentence of the phrase is a quote")
	assert_false(VoicePool.quotes_phrase("The Loop turns. So do I.", cleric), "the Cleric's own vocabulary counted as quoting her phrase")
	assert_false(VoicePool.quotes_phrase("No.", ["Hold for applause. No? Tough room."]), "a one-word sentence of a phrase counted as a quote")
	assert_true(VoicePool.quotes_phrase("Stitched. Logged. Forgiven.", ["Stitched. Logged. Forgiven."]), "the whole phrase, made of one-word sentences, escaped the cap")
