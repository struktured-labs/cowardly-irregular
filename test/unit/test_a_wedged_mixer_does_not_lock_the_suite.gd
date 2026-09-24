extends GutTest

## Issue #224: a dead mix thread holds the audio-driver mutex inside an unbounded mix.
## AudioStreamWAV.set_data waits on that mutex, so the next procedural commit (the tavern piano)
## never returns and the suite does not finish. The latch refuses the commit. This file plants
## the latch — it must not take the lock — and, on a live mixer, proves a healthy commit still
## assigns the bytes. The live arm is first so it runs before any plant.


var _planted: bool = false


func after_each() -> void:
	if SoundManager == null:
		return
	## Only clear a latch this file planted. A real stall must stay latched: clearing it and
	## then assigning wav.data waits forever on the driver mutex (issue #224).
	if _planted:
		SoundManager._audio_mixer_wedged = false
		SoundManager._mixer_watch_pos = -1.0
		SoundManager._mixer_watch_msec = 0
		_planted = false
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
