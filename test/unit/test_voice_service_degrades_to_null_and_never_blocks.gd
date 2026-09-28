extends GutTest

## Every failure path returns null in bounded time; the web gate is a PROPERTY (no server URL), so piece 5's browser backend keeps it.

const Replay := preload("res://tools/replay_tts_backend.gd")
const DIR := "user://test_voice_service_cache"

var _saved_cast: Dictionary
var _saved_cache
var _saved_web: bool
var _saved_gs: Dictionary = {}
var _replay


var _planted: bool = false


func before_each() -> void:
	_saved_cast = VoiceService._cast.duplicate(true)
	_saved_cache = VoiceService.cache
	_saved_web = VoiceService.is_web
	for f in ["tts_live_enabled", "tts_server_url", "tts_model"]:
		_saved_gs[f] = GameState.get(f)
	VoiceService.cache = VoiceCache.new(DIR, 10_000_000)
	VoiceService._cast = {"bard": {"voice": "bard.wav", "rev": 3}}
	_replay = Replay.new()
	_replay.next_wav = WavFixture.tone(0.25, 20000)
	VoiceService.install_backend(_replay)


func after_each() -> void:
	if _planted:
		SoundManager._voice_decode_test_block_msec = 0
		SoundManager._voice_decode_bound_override_msec = 0
		SoundManager._voice_decode_test_ignore_abandon = false
		if SoundManager._voice_decode_still_running():
			SoundManager._voice_decode_abandoned = true
			var until := Time.get_ticks_msec() + 2000
			while Time.get_ticks_msec() < until and SoundManager._voice_decode_still_running():
				OS.delay_msec(10)
		SoundManager._reap_voice_decode_threads()
		SoundManager._voice_decode_abandoned = false
		## Only a latch this arm planted is cleared; a real stall must stay latched (issue #224).
		SoundManager._audio_mixer_wedged = false
		SoundManager._mixer_watch_pos = -1.0
		SoundManager._mixer_watch_msec = 0
		_planted = false
	VoiceService.test_backend = null
	VoiceService.is_web = _saved_web
	for f in _saved_gs:
		GameState.set(f, _saved_gs[f])
	VoiceService._cast = _saved_cast
	VoiceService.apply_config()
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(DIR + "/" + f)
		DirAccess.remove_absolute(DIR)
	VoiceService.cache = _saved_cache


## A decode refused by design (issue #224) fails LOUD and names which refusal, never as a bare null.
func _wedged_refusal(stream: AudioStream) -> bool:
	var why := WavFixture.decode_refusal_reason(stream)
	if why == "":
		return false
	fail_test(WavFixture.refusal_note(why))
	return true


func test_an_uncast_speaker_never_asks_the_server() -> void:
	assert_null(await VoiceService.synthesize("goblin", "Hi.", 2.0))
	assert_eq(_replay.requests.size(), 0)


func test_a_fresh_line_is_synthesized_cached_and_then_served_from_cache() -> void:
	var s: AudioStream = await VoiceService.synthesize("bard", "A song.", 2.0)
	if _wedged_refusal(s):
		return
	assert_not_null(s)
	assert_eq(_replay.requests.size(), 1)
	assert_eq(_replay.requests[0]["voice"], "bard.wav", "the cast's server voice name is what is sent")
	assert_not_null(VoiceService.get_cached("bard", "A song."), "synchronously available for the bubble")
	await VoiceService.synthesize("bard", "A song.", 2.0)
	assert_eq(_replay.requests.size(), 1, "a cached line never reaches the server again")


func test_a_recast_misses_the_old_audio() -> void:
	var first: AudioStream = await VoiceService.synthesize("bard", "A song.", 2.0)
	if _wedged_refusal(first):
		return
	assert_not_null(first, "VOID unless the line was synthesized, or the miss below proves nothing")
	assert_not_null(VoiceService.get_cached("bard", "A song."), "served from cache at the old rev")
	VoiceService._cast["bard"]["rev"] = 4
	assert_null(VoiceService.get_cached("bard", "A song."), "rev is in the key")


func test_a_cached_blob_that_fails_to_decode_is_deleted_not_served() -> void:
	var key := VoiceCache.key_for("bard.wav", 3, "Rotten.")
	VoiceService.cache.write(key, "not a wav".to_utf8_buffer())
	assert_null(VoiceService.get_cached("bard", "Rotten."))
	assert_false(VoiceService.cache.has(key), "spec 1.4: a blob that fails to decode is deleted, never served")


func test_a_reply_that_is_not_a_whole_wav_is_null_and_not_cached() -> void:
	_replay.next_wav = WavFixture.tone(0.25, 20000).slice(0, 500)
	assert_null(await VoiceService.synthesize("bard", "Cut off.", 2.0))
	assert_null(VoiceService.get_cached("bard", "Cut off."))
	assert_ne(VoiceService.status()["last_error"], "")


func test_a_silent_server_times_out_within_budget_and_is_cancelled() -> void:
	_replay.silent = true
	var t0 := Time.get_ticks_msec()
	assert_null(await VoiceService.synthesize("bard", "Anyone?", 0.3))
	var took := Time.get_ticks_msec() - t0
	assert_true(took < 1000, "took %d ms against a 300 ms budget" % took)
	assert_eq(_replay.cancelled.size(), 1, "the abandoned request is cancelled")
	assert_string_contains(VoiceService.status()["last_error"], "timed out")


func test_clipping_is_flagged_in_status() -> void:
	var s := PackedInt32Array()
	s.resize(12000)
	for i in s.size():
		s[i] = 32767 if (i % 1000) < 5 else 1000
	_replay.next_wav = WavFixture.pcm16(s)
	var loud: AudioStream = await VoiceService.synthesize("bard", "Loud.", 2.0)
	if _wedged_refusal(loud):
		return
	assert_not_null(loud, "VOID unless the clipped line was decoded")
	assert_true(VoiceService.status()["clipping_detected"])


func test_status_has_the_spec_shape_and_names_missing_voices() -> void:
	VoiceService._cast["mage"] = {"voice": "mage.wav", "rev": 1}
	_replay.voices = ["bard.wav"] as Array[String]
	var st: Dictionary = VoiceService.status()
	for k in ["enabled", "ready", "backend", "url", "last_latency_ms", "last_error", "clipping_detected", "missing_voices"]:
		assert_true(st.has(k), "status needs %s" % k)
	assert_eq(st["missing_voices"], ["mage.wav"] as Array[String])
	_replay.voices = [] as Array[String]
	assert_eq(VoiceService.status()["missing_voices"], [] as Array[String], "an unknown server list flags nothing")


func test_on_web_no_backend_contacts_a_server_url() -> void:
	GameState.tts_live_enabled = true
	GameState.tts_server_url = "http://127.0.0.1:8004"
	VoiceService.is_web = true
	VoiceService.apply_config()
	assert_eq(VoiceService.status()["url"], "", "on web nothing may point at a server")
	assert_null(await VoiceService.synthesize("bard", "Anything.", 0.5))
	assert_eq(VoiceService.find_children("*", "HTTPRequest", true, false).size(), 0, "no HTTPRequest was ever made")


func test_control_on_desktop_the_same_config_does_point_at_the_server() -> void:
	GameState.tts_live_enabled = true
	GameState.tts_server_url = "http://127.0.0.1:1"
	VoiceService.is_web = false
	VoiceService.apply_config()
	assert_eq(VoiceService.status()["url"], "http://127.0.0.1:1", "CONTROL: without the web gate this is where requests go")


func test_live_off_selects_a_backend_that_contacts_nothing() -> void:
	GameState.tts_live_enabled = false
	VoiceService.is_web = false
	VoiceService.apply_config()
	assert_eq(VoiceService.status()["url"], "")
	assert_false(VoiceService.is_live_ready())


## .538: the latch had cleared while an abandoned decode worker was still alive; three arms failed as a bare null.
func test_a_refusal_by_a_stuck_decode_names_that_cause() -> void:
	if SoundManager.mixer_is_wedged():
		pending("the mixer is already wedged, so no stand-in decode is started on a dead mix")
		return
	assert_eq(SoundManager._orphaned_voice_decodes.size(), 0, "CONTROL: no decode thread left over from an earlier arm")
	SoundManager._voice_decode_bound_override_msec = 200
	SoundManager._voice_decode_test_block_msec = 1500
	SoundManager._voice_decode_test_ignore_abandon = true
	_planted = true
	VoiceAudio.decode(WavFixture.tone(0.05, 1000))
	assert_eq(SoundManager._orphaned_voice_decodes.size(), 1, "CONTROL: the stand-in must stay running as an orphan")
	SoundManager._audio_mixer_wedged = false
	var refused := VoiceAudio.decode(WavFixture.tone(0.05, 1000))
	assert_null(refused, "CONTROL: a decode beside a live orphan is refused")
	assert_false(SoundManager.mixer_is_wedged(), "CONTROL: the latch is clear, exactly the .538 state")
	assert_string_contains(WavFixture.decode_refusal_reason(refused), "still stuck",
		"a refusal by the stuck worker must name that cause, not read as a bare null")
