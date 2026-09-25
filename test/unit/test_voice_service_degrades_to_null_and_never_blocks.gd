extends GutTest

## Every failure path returns null in bounded time; the web gate is a PROPERTY (no server URL), so piece 5's browser backend keeps it.

const Replay := preload("res://tools/replay_tts_backend.gd")
const DIR := "user://test_voice_service_cache"

var _saved_cast: Dictionary
var _saved_cache
var _saved_web: bool
var _saved_gs: Dictionary = {}
var _replay


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


func test_an_uncast_speaker_never_asks_the_server() -> void:
	assert_null(await VoiceService.synthesize("goblin", "Hi.", 2.0))
	assert_eq(_replay.requests.size(), 0)


func test_a_fresh_line_is_synthesized_cached_and_then_served_from_cache() -> void:
	var s: AudioStream = await VoiceService.synthesize("bard", "A song.", 2.0)
	assert_not_null(s)
	assert_eq(_replay.requests.size(), 1)
	assert_eq(_replay.requests[0]["voice"], "bard.wav", "the cast's server voice name is what is sent")
	assert_not_null(VoiceService.get_cached("bard", "A song."), "synchronously available for the bubble")
	await VoiceService.synthesize("bard", "A song.", 2.0)
	assert_eq(_replay.requests.size(), 1, "a cached line never reaches the server again")


func test_a_recast_misses_the_old_audio() -> void:
	await VoiceService.synthesize("bard", "A song.", 2.0)
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
	await VoiceService.synthesize("bard", "Loud.", 2.0)
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
