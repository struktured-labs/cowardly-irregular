extends GutTest

## 2b.1: a pooled line carries its own audio. The bubble must play it, and hold for it, exactly as it does a shipped clip.

func _bubble(stream: AudioStream, key: String = ""):
	var parent := Node2D.new()
	add_child_autofree(parent)
	return BattleSpeechBubble.spawn(parent, Vector2(400, 300), "Bard", "A line.", Color.WHITE, 1.5, key,
		true, 0.0, BattleSpeechBubble.TOP_MARGIN, Callable(), stream)


func after_each() -> void:
	if SoundManager._voice_player != null and SoundManager._voice_player.playing and not SoundManager.wav_commit_refused():
		SoundManager.stop_voice()


func test_a_stream_plays_and_sets_the_hold() -> void:
	var stream := VoiceAudio.decode(WavFixture.tone(0.6, 8000))
	if stream == null:
		fail_test(WavFixture.refusal_note(WavFixture.decode_refusal_reason(stream)))
		return
	var b = _bubble(stream)
	assert_not_null(b, "CONTROL: the bubble spawned")
	if SoundManager.wav_commit_refused():
		pending("mixer latched: play_voice_stream refuses by design")
		return
	assert_eq(SoundManager._voice_player.stream, stream, "the synthesized stream is not the one on the voice player")
	assert_gte(b._hold_time, stream.get_length() + BattleSpeechBubble.VOICE_TAIL_S - 0.01,
		"the bubble fades before its line is spoken")


func test_a_stream_wins_over_a_clip_key() -> void:
	var stream := VoiceAudio.decode(WavFixture.tone(0.4, 8000))
	if stream == null or SoundManager.wav_commit_refused():
		pending("decode refused or mixer latched")
		return
	_bubble(stream, "voice_bard_turn_start")
	assert_eq(SoundManager._voice_player.stream, stream, "a shipped clip played over the synthesized line it was given")


func test_control_no_stream_keeps_todays_behaviour() -> void:
	var b = _bubble(null, "")
	assert_not_null(b, "CONTROL: the bubble spawned")
	assert_eq(b._hold_time, 1.5, "CONTROL: with neither a stream nor a key, the hold is the caller's")
	assert_false(b._voiced, "CONTROL: nothing was voiced")
