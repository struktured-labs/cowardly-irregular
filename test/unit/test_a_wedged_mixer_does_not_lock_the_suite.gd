extends GutTest

## Issue #224: a dead mix thread holds the audio-driver mutex inside an unbounded mix.
## AudioStreamWAV.set_data waits on that mutex, so the next procedural commit (the tavern piano)
## never returns and the suite does not finish. The latch refuses the commit. This file plants
## the latch — it must not take the lock — and, on a live mixer, proves a healthy commit still
## assigns the bytes. The live arm is first so it runs before any plant.
## Live voice uses load_from_buffer and stop(), the same lock, and the watch has to see that player.
## The first decode runs off the main thread. A stall inside load_from_buffer used to pin the suite before this latch could arm.


var _planted: bool = false


func after_each() -> void:
	if SoundManager == null:
		return
	SoundManager._voice_decode_test_block_msec = 0
	SoundManager._voice_decode_bound_override_msec = 0
	if SoundManager._voice_decode_still_running():
		SoundManager._voice_decode_abandoned = true
		var until := Time.get_ticks_msec() + 500
		while Time.get_ticks_msec() < until and SoundManager._voice_decode_still_running():
			OS.delay_msec(10)
	SoundManager._reap_voice_decode_threads()
	SoundManager._voice_decode_abandoned = false
	SoundManager._mixer_stall_watch_force = -1
	SoundManager._mixer_pos_override = -1.0
	## Only clear a latch this file planted. A real stall must stay latched: clearing it and
	## then assigning wav.data waits forever on the driver mutex (issue #224).
	if _planted:
		SoundManager._audio_mixer_wedged = false
		SoundManager._mixer_watch_pos = -1.0
		SoundManager._mixer_watch_msec = 0
		_planted = false
	if SoundManager._voice_player != null:
		SoundManager._voice_player.pitch_scale = 1.0
	if not SoundManager._audio_mixer_wedged:
		SoundManager.stop_music()
		SoundManager.stop_ambient()
		SoundManager.stop_voice()
	if SoundManager._ability_player != null:
		SoundManager._ability_player.pitch_scale = 1.0
		SoundManager._ability_player.stop()


func test_a_live_mixer_still_accepts_a_pcm_commit() -> void:
	if SoundManager == null:
		assert_true(false, "SoundManager unavailable")
		return
	if SoundManager.mixer_is_wedged():
		# A stall is already latched. Taking the lock here is how the suite hangs, so this
		# arm cannot show a healthy assign. Pending, not a failure: playback may still resume.
		pending("mixer already wedged — skipped the PCM commit that would hang on AudioServer.lock")
		assert_true(SoundManager.mixer_is_wedged(), "the latch that blocked the commit is set")
		return
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var data := PackedByteArray([0, 128, 255, 128])
	assert_true(SoundManager._commit_wav_pcm(wav, data),
		"a live mixer must still accept PCM — skipping it would silence generated music")
	assert_eq(wav.data.size(), data.size(),
		"the commit must assign the bytes")


func test_a_planted_wedge_returns_before_the_piano_commit() -> void:
	if SoundManager == null or SoundManager._ability_player == null:
		assert_true(false, "SoundManager/_ability_player unavailable — this arm would prove nothing")
		return
	SoundManager._ability_player.stop()
	SoundManager._ability_player.pitch_scale = 1.0 + SoundManager.SFX_PITCH_JITTER
	var planted_pitch: float = SoundManager._ability_player.pitch_scale
	assert_ne(planted_pitch, 1.0, "SCOPE control: the plant did not take, so a skipped reset is invisible")
	## A real stall may already be latched. Planting over it is fine; clearing it afterwards is not.
	if not SoundManager.mixer_is_wedged():
		SoundManager._audio_mixer_wedged = true
		_planted = true
	var started: int = Time.get_ticks_msec()
	SoundManager.play_piano_melody()
	var elapsed: int = Time.get_ticks_msec() - started
	assert_lt(elapsed, 500,
		"play_piano_melody took %d ms with the mixer latched — it synthesized the melody or waited on AudioServer.lock" % elapsed)
	assert_eq(SoundManager._ability_player.pitch_scale, planted_pitch,
		"the piano reset pitch_scale, which happens only after the PCM commit — the latch did not bail first")
	assert_false(SoundManager._ability_player.playing,
		"the piano started playback, which happens only after the PCM commit")


func test_a_planted_wedge_refuses_the_voice_wav_lock() -> void:
	if SoundManager == null or SoundManager._voice_player == null:
		assert_true(false, "SoundManager/_voice_player unavailable — this arm would prove nothing")
		return
	if SoundManager.mixer_is_wedged():
		var already := Time.get_ticks_msec()
		var refused_now := VoiceAudio.decode(WavFixture.tone(0.05, 1000))
		assert_lt(Time.get_ticks_msec() - already, 500,
			"VoiceAudio.decode took %d ms on an already-wedged mixer — load_from_buffer waited on AudioServer.lock" % (Time.get_ticks_msec() - already))
		assert_null(refused_now, "a wedged mixer still decoded a voice WAV")
		return
	SoundManager.stop_music()
	SoundManager.stop_ambient()
	SoundManager.stop_voice()
	SoundManager._voice_player.pitch_scale = 0.5
	var before_stream: AudioStream = SoundManager._voice_player.stream
	SoundManager._audio_mixer_wedged = true
	_planted = true
	var started := Time.get_ticks_msec()
	var refused := VoiceAudio.decode(WavFixture.tone(0.05, 1000))
	var elapsed := Time.get_ticks_msec() - started
	assert_lt(elapsed, 500,
		"VoiceAudio.decode took %d ms with the mixer latched — load_from_buffer waited on AudioServer.lock" % elapsed)
	assert_null(refused, "a latched mixer still decoded a voice WAV — the live voice panel would hang the suite")
	started = Time.get_ticks_msec()
	var got := SoundManager.play_voice_stream(AudioStreamWAV.new())
	elapsed = Time.get_ticks_msec() - started
	assert_lt(elapsed, 500, "play_voice_stream took %d ms with the mixer latched" % elapsed)
	assert_eq(got, 0.0, "a latched mixer still returned a voice length")
	assert_eq(SoundManager._voice_player.pitch_scale, 0.5,
		"play_voice_stream reset pitch, which happens only after it takes the player")
	assert_eq(SoundManager._voice_player.stream, before_stream, "play_voice_stream assigned a stream after the latch")
	assert_false(SoundManager._voice_player.playing, "the voice player started after the latch")


func test_a_frozen_voice_preroll_refuses_stop_and_decode() -> void:
	if SoundManager.mixer_is_wedged():
		pending("mixer already wedged — not starting a voice line on a dead mix")
		assert_true(SoundManager.mixer_is_wedged(), "the latch that blocked the voice line is set")
		return
	assert_true(SoundManager._mixer_stall_watch_active(),
		"CONTROL: this headless suite must arm the watch, or a frozen voice line never latches")
	SoundManager.stop_music()
	SoundManager.stop_ambient()
	var clip := VoiceAudio.decode(WavFixture.tone(0.4, 8000))
	assert_not_null(clip, "CONTROL: a live mixer still decodes a voice clip")
	var length := SoundManager.play_voice_stream(clip)
	assert_gt(length, 0.3, "CONTROL: the line has length, so a later refusal is not an empty stream")
	await get_tree().process_frame
	assert_true(SoundManager._voice_player.playing, "CONTROL: the voice line is playing")
	assert_eq(SoundManager._live_bed(), SoundManager._voice_player,
		"the watch does not sample the voice player — a frozen line never arms the latch")
	SoundManager._mixer_pos_override = 0.0026666666
	SoundManager._mixer_watch_pos = 0.0026666666
	SoundManager._mixer_watch_msec = Time.get_ticks_msec() - 5000
	SoundManager._audio_mixer_wedged = false
	_planted = true
	SoundManager.note_mixer_progress()
	assert_true(SoundManager.mixer_is_wedged(),
		"a voice line frozen at the 0.00267 dummy preroll for 5s did not latch")
	var started := Time.get_ticks_msec()
	SoundManager.stop_voice()
	var elapsed := Time.get_ticks_msec() - started
	assert_lt(elapsed, 500,
		"stop_voice took %d ms with the mixer latched — it waited on AudioServer.lock" % elapsed)
	assert_true(SoundManager._voice_player.playing,
		"stop_voice stopped the line, which happens only after AudioServer.lock")
	started = Time.get_ticks_msec()
	var refused := VoiceAudio.decode(WavFixture.tone(0.05, 1000))
	elapsed = Time.get_ticks_msec() - started
	assert_lt(elapsed, 500, "VoiceAudio.decode took %d ms after the voice preroll latched" % elapsed)
	assert_null(refused, "live voice decode still called load_from_buffer after the voice preroll latched")


## The mix dies inside the first load_from_buffer, before any playhead exists for the position watch.
## The worker stands in for that call not returning. The main thread must come back and arm the latch.
func test_a_first_decode_stall_returns_and_arms_the_latch() -> void:
	if SoundManager.mixer_is_wedged():
		pending("mixer already wedged — not starting another decode on a dead mix")
		assert_true(SoundManager.mixer_is_wedged(), "the latch that blocked the decode is set")
		return
	assert_true(SoundManager._mixer_stall_watch_active(),
		"CONTROL: this headless suite must arm the watch, or the first-decode bound never runs")
	assert_eq(SoundManager._orphaned_voice_decodes.size(), 0, "CONTROL: no decode thread left over from an earlier arm")
	SoundManager._voice_decode_bound_override_msec = 200
	SoundManager._voice_decode_test_block_msec = 30000
	_planted = true
	var started := Time.get_ticks_msec()
	var refused := VoiceAudio.decode(WavFixture.tone(0.05, 1000))
	var elapsed := Time.get_ticks_msec() - started
	assert_null(refused, "a decode that did not return still produced a stream")
	assert_true(SoundManager.mixer_is_wedged(),
		"the first decode never came back and the latch stayed clear — the suite would still be inside load_from_buffer")
	assert_gt(elapsed, 150, "decode returned in %d ms, before the bound — the stall was not simulated" % elapsed)
	assert_lt(elapsed, 2000,
		"decode took %d ms — the main thread waited out the 30s stand-in instead of giving up" % elapsed)
	assert_eq(SoundManager._orphaned_voice_decodes.size(), 0,
		"the simulated stall leaked a decode thread")
	started = Time.get_ticks_msec()
	var refused_again := VoiceAudio.decode(WavFixture.tone(0.05, 1000))
	elapsed = Time.get_ticks_msec() - started
	assert_null(refused_again, "a latched mixer still decoded a voice WAV")
	assert_lt(elapsed, 100,
		"the latched decode took %d ms — it entered the bound again instead of returning before the lock" % elapsed)


## Measured failure: a voice line sat at the 44.1 kHz preroll (128/44100 = 0.00290s) for 312ms and then played.
## That slow start must not arm the latch. A playhead that is still there past the stall window must.
func test_a_brief_preroll_slow_start_does_not_latch() -> void:
	if SoundManager.mixer_is_wedged():
		pending("mixer already wedged — not sampling a slow start on a dead mix")
		assert_true(SoundManager.mixer_is_wedged(), "the latch that blocked the slow-start sample is set")
		return
	assert_true(SoundManager._mixer_stall_watch_active(),
		"CONTROL: this headless suite must arm the watch, or 'not latched' is true because the watch is off")
	assert_gt(SoundManager._MIXER_STALL_MSEC, 312,
		"the stall window must outlast the 312ms preroll that still resumed")
	SoundManager.stop_music()
	SoundManager.stop_ambient()
	var clip := VoiceAudio.decode(WavFixture.tone(0.4, 8000))
	assert_not_null(clip, "CONTROL: a live mixer still decodes a voice clip")
	var length := SoundManager.play_voice_stream(clip)
	assert_gt(length, 0.3, "CONTROL: the line has length, so the watch has a voice bed to sample")
	await get_tree().process_frame
	assert_eq(SoundManager._live_bed(), SoundManager._voice_player,
		"CONTROL: the voice line is the bed the watch samples")
	var preroll := 128.0 / 44100.0
	assert_almost_eq(preroll, 0.00290, 0.00001, "128 samples at 44.1 kHz is the 0.00290s preroll")
	_planted = true
	SoundManager._mixer_pos_override = preroll
	SoundManager._mixer_watch_pos = preroll
	SoundManager._mixer_watch_msec = Time.get_ticks_msec() - 312
	SoundManager._audio_mixer_wedged = false
	SoundManager.note_mixer_progress()
	assert_false(SoundManager.mixer_is_wedged(),
		"a voice line at the 0.00290s preroll for 312ms armed the latch — that slow start resumed")
	SoundManager._mixer_pos_override = preroll + 0.05
	SoundManager.note_mixer_progress()
	assert_false(SoundManager.mixer_is_wedged(),
		"the playhead left the preroll and the latch stayed set")
	SoundManager._mixer_pos_override = preroll
	SoundManager._mixer_watch_pos = preroll
	SoundManager._mixer_watch_msec = Time.get_ticks_msec() - (SoundManager._MIXER_STALL_MSEC + 50)
	SoundManager._audio_mixer_wedged = false
	SoundManager.note_mixer_progress()
	assert_true(SoundManager.mixer_is_wedged(),
		"a preroll still frozen after the stall window did not latch")


## force 0 is the windowed game. The decode bound must not run there, or a test stand-in would refuse a healthy line.
func test_a_disarmed_watch_decodes_on_the_caller() -> void:
	if SoundManager.mixer_is_wedged():
		pending("mixer already wedged — a disarmed watch would take AudioServer.lock")
		assert_true(SoundManager.mixer_is_wedged(), "the latch that blocked the caller decode is set")
		return
	SoundManager._mixer_stall_watch_force = 0
	assert_false(SoundManager._mixer_stall_watch_active(), "force 0 must disarm the watch")
	_planted = true
	SoundManager._voice_decode_bound_override_msec = 200
	SoundManager._voice_decode_test_block_msec = 30000
	var started := Time.get_ticks_msec()
	var stream := VoiceAudio.decode(WavFixture.tone(0.05, 1000))
	var elapsed := Time.get_ticks_msec() - started
	assert_not_null(stream, "a disarmed watch refused the decode — player builds would lose voice lines")
	assert_gt(stream.get_length(), 0.0, "the caller decode did not return the WAV")
	assert_lt(elapsed, 500,
		"decode took %d ms with the watch disarmed — it honored the stall stand-in" % elapsed)
	assert_false(SoundManager.mixer_is_wedged(), "a disarmed watch armed the latch")
	assert_eq(SoundManager._orphaned_voice_decodes.size(), 0, "a disarmed watch started a decode thread")


func _wait_ms(ms: int) -> void:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		SoundManager.note_mixer_progress()
		await get_tree().process_frame


func _require_bed(track: String) -> void:
	SoundManager.play_music(track, true)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(SoundManager._music_player != null and SoundManager._music_player.playing,
		"CONTROL: %s did not start — a later 'not latched' would be true because nothing is playing" % track)


func test_a_jump_to_the_four_second_entry_counts_as_motion() -> void:
	if SoundManager.mixer_is_wedged():
		pending("mixer already wedged — not clearing it to sample a 4s entry")
		return
	await _require_bed("battle_medieval")
	var blend: float = float((SoundManager._music_manifest["battle_medieval"] as Dictionary).get("loop_blend_seconds", 0.0))
	assert_gte(blend, 4.0, "CONTROL: this bed's fold entry is the 4s offset from the loop rebuild")
	SoundManager._mixer_watch_pos = 0.0026666666
	SoundManager._mixer_watch_msec = Time.get_ticks_msec() - 5000
	SoundManager._audio_mixer_wedged = true
	_planted = true
	SoundManager._mixer_pos_override = blend
	SoundManager.note_mixer_progress()
	assert_false(SoundManager.mixer_is_wedged(),
		"a bed sitting at its %.1f s fold was still latched — that entry has to count as the mix moving, not as the preroll stall" % blend)
	_planted = false


func test_a_fold_entry_that_advances_is_not_a_stall() -> void:
	if SoundManager.mixer_is_wedged():
		pending("mixer already wedged")
		return
	SoundManager._audio_mixer_wedged = false
	SoundManager._mixer_watch_pos = -1.0
	SoundManager._mixer_watch_msec = 0
	await _require_bed("battle_medieval")
	var blend: float = float((SoundManager._music_manifest["battle_medieval"] as Dictionary).get("loop_blend_seconds", 0.0))
	assert_gte(blend, 4.0, "CONTROL: battle_medieval enters after its four-second fold")
	var entry := -1.0
	var last := -1.0
	var deadline := Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < deadline:
		SoundManager.note_mixer_progress()
		var pos := SoundManager._music_player.get_playback_position()
		last = pos
		if entry < 0.0 and pos >= blend - 0.05:
			entry = pos
		assert_false(SoundManager.mixer_is_wedged(),
			"latch fired at %.5f s (fold entry sample %.5f) — a bed that opened at %.1f s was treated as a stalled mix" % [pos, entry, blend])
		await get_tree().process_frame
	assert_gte(entry, blend - 0.05,
		"never reached the %.1f s fold (last %.5f). 0.00267 is the wedged dummy preroll, not a fold start" % [blend, last])
	assert_gte(last - entry, 0.01,
		"position sat at %.5f for 600ms after the %.1f s entry" % [last, blend])


func test_a_paused_bed_does_not_latch() -> void:
	if SoundManager.mixer_is_wedged():
		pending("mixer already wedged")
		return
	await _require_bed("battle_medieval")
	SoundManager._music_player.stream_paused = true
	assert_true(SoundManager._music_player.stream_paused, "CONTROL: the pause took")
	# Godot 4.4 reports playing=false while stream_paused is set, so the bed leaves the live set.
	assert_null(SoundManager._live_bed(), "a paused bed must leave the live set")
	SoundManager._audio_mixer_wedged = false
	SoundManager._mixer_watch_msec = Time.get_ticks_msec() - 1000
	await _wait_ms(400)
	assert_false(SoundManager.mixer_is_wedged(), "pausing the bed froze playback and armed the latch")
	SoundManager._music_player.stream_paused = false


func test_a_stopped_bed_does_not_latch() -> void:
	if SoundManager.mixer_is_wedged():
		pending("mixer already wedged")
		return
	await _require_bed("battle_medieval")
	SoundManager.stop_music()
	SoundManager._mixer_watch_pos = 4.0
	SoundManager._mixer_watch_msec = Time.get_ticks_msec() - 1000
	SoundManager._audio_mixer_wedged = false
	await _wait_ms(400)
	assert_false(SoundManager._music_player.playing, "CONTROL: the bed is stopped")
	assert_false(SoundManager.mixer_is_wedged(), "a stopped bed armed the latch")
	assert_eq(SoundManager._mixer_watch_pos, -1.0, "the gap must reset the watch so the next 4s entry is a baseline")


func test_no_bed_does_not_latch() -> void:
	if SoundManager.mixer_is_wedged():
		pending("mixer already wedged — not clearing it")
		return
	SoundManager.stop_music()
	SoundManager.stop_ambient()
	SoundManager._mixer_watch_pos = 4.0
	SoundManager._mixer_watch_msec = Time.get_ticks_msec() - 1000
	SoundManager._audio_mixer_wedged = false
	SoundManager.note_mixer_progress()
	assert_null(SoundManager._live_bed(), "CONTROL: nothing is live")
	assert_false(SoundManager.mixer_is_wedged(), "no bed armed the latch")


func test_a_crossfade_does_not_latch() -> void:
	if SoundManager.mixer_is_wedged():
		pending("mixer already wedged")
		return
	await _require_bed("overworld_medieval")
	await _wait_ms(200)
	SoundManager.play_music("battle_medieval", true)
	var saw_outgoing := false
	var deadline := Time.get_ticks_msec() + 400
	while Time.get_ticks_msec() < deadline:
		SoundManager.note_mixer_progress()
		if SoundManager._music_player_b and SoundManager._music_player_b.playing:
			saw_outgoing = true
		assert_false(SoundManager.mixer_is_wedged(), "the crossfade armed the latch")
		await get_tree().process_frame
	assert_true(saw_outgoing, "CONTROL: the outgoing bed was playing on the crossfade player")
	assert_true(SoundManager._music_player.playing, "CONTROL: the incoming bed is playing")


func test_a_silent_bed_that_keeps_moving_does_not_latch() -> void:
	if SoundManager.mixer_is_wedged():
		pending("mixer already wedged")
		return
	await _require_bed("battle_medieval")
	SoundManager._music_player.volume_db = -80.0
	var first := SoundManager._music_player.get_playback_position()
	await _wait_ms(400)
	var last := SoundManager._music_player.get_playback_position()
	assert_gte(absf(last - first), 0.01,
		"CONTROL: silent bed did not advance (%.5f -> %.5f) — a wedged driver, not a mute" % [first, last])
	assert_false(SoundManager.mixer_is_wedged(), "a muted bed that was still advancing armed the latch")


func test_a_real_device_does_not_arm_or_honor_the_latch() -> void:
	## force 0 is the windowed game: focus loss, a pause that freezes the clock, and a 4s
	## entry must not skip procedural music. This process is headless, so the flag is the seam.
	var already := SoundManager.mixer_is_wedged()
	SoundManager._mixer_stall_watch_force = 0
	assert_false(SoundManager._mixer_stall_watch_active(), "force 0 must disarm the watch")
	await _require_bed("battle_medieval")
	SoundManager._mixer_pos_override = 0.0026666666
	SoundManager._mixer_watch_pos = 0.0026666666
	SoundManager._mixer_watch_msec = Time.get_ticks_msec() - 5000
	if not already:
		SoundManager._audio_mixer_wedged = false
	SoundManager.note_mixer_progress()
	if not already:
		assert_false(SoundManager.mixer_is_wedged(),
			"a frozen preroll armed the latch while the watch was disarmed")
	if already:
		assert_false(SoundManager._pcm_commit_blocked(),
			"a disarmed watch must not refuse PCM")
		pending("real stall already latched — did not take AudioServer.lock")
		return
	SoundManager._audio_mixer_wedged = true
	_planted = true
	assert_false(SoundManager._pcm_commit_blocked(), "a planted latch still blocks commits when the watch is off")
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var data := PackedByteArray([0, 128, 255, 128])
	assert_true(SoundManager._commit_wav_pcm(wav, data),
		"a disarmed watch skipped the PCM commit — procedural music would be silent in the real game")
	assert_eq(wav.data.size(), data.size(), "the commit must assign the bytes")


func test_a_frozen_preroll_still_latches_under_the_dummy_watch() -> void:
	if SoundManager.mixer_is_wedged():
		pending("mixer already wedged")
		return
	assert_true(SoundManager._mixer_stall_watch_active(),
		"CONTROL: this headless suite must arm the watch, or the hang fix is off in the run that needs it")
	await _require_bed("battle_medieval")
	SoundManager._mixer_pos_override = 0.0026666666
	SoundManager._mixer_watch_pos = 0.0026666666
	SoundManager._mixer_watch_msec = Time.get_ticks_msec() - 5000
	SoundManager._audio_mixer_wedged = false
	SoundManager.note_mixer_progress()
	assert_true(SoundManager.mixer_is_wedged(),
		"a preroll frozen for 5s under the dummy watch did not latch")
	_planted = true
	var wav := AudioStreamWAV.new()
	assert_false(SoundManager._commit_wav_pcm(wav, PackedByteArray([0, 1])),
		"the latched watch still accepted a PCM commit")
