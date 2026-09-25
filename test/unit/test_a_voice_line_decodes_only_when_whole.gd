extends GutTest

## A server that dies mid-line returns a WAV that load_from_buffer plays SHORT; only a whole file may reach the player.

func _clip_runs(runs: int) -> PackedByteArray:
	var s := PackedInt32Array()
	s.resize(24000)
	for i in s.size():
		s[i] = int(sin(i * 0.05) * 20000)
	for r in runs:
		for k in 5:
			s[1000 + r * 3000 + k] = 32767
	return WavFixture.pcm16(s)


func test_a_whole_wav_decodes_at_its_own_rate_and_length() -> void:
	var w := VoiceAudio.decode(WavFixture.tone(0.5, 20000))
	assert_not_null(w)
	assert_eq(w.mix_rate, 24000, "24 kHz plays at 24 kHz, no resampling")
	assert_eq(w.stereo, false)
	assert_almost_eq(w.get_length(), 0.5, 0.001)


func test_a_truncated_wav_is_refused_not_played_short() -> void:
	var whole := WavFixture.tone(0.5, 20000)
	assert_null(VoiceAudio.decode(whole.slice(0, 1000)), "cut mid-data: the engine would play 0.02s of it")
	assert_null(VoiceAudio.decode(whole.slice(0, 30)), "cut mid-header")


func test_garbage_and_empty_are_refused() -> void:
	var junk := PackedByteArray()
	junk.resize(500)
	junk.fill(7)
	assert_null(VoiceAudio.decode(junk))
	assert_null(VoiceAudio.decode(PackedByteArray()))


func test_two_pinned_runs_are_clipping_and_one_is_a_peak() -> void:
	assert_eq(VoiceAudio.pinned_runs(VoiceAudio.decode(_clip_runs(2))), 2)
	assert_true(VoiceAudio.is_clipped(VoiceAudio.decode(_clip_runs(2))), "2 runs at the rail: clipped")
	assert_false(VoiceAudio.is_clipped(VoiceAudio.decode(_clip_runs(1))), "1 pinned run can be a clean peak")


func test_the_supported_servers_minus_1_dbfs_output_is_not_clipping() -> void:
	var w := VoiceAudio.decode(WavFixture.tone(1.0, 29196))
	assert_eq(VoiceAudio.pinned_runs(w), 0, "peak-normalised to -1 dBFS never reaches the rail")
