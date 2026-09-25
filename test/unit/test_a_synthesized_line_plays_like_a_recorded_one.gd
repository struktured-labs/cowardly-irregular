extends GutTest

## A live line must use play_voice's player, level and unity pitch, and return its length: the bubble's hold is set from it.

func test_it_plays_on_the_voice_player_at_unity_pitch_and_returns_its_length() -> void:
	var s := VoiceAudio.decode(WavFixture.tone(0.5, 20000))
	SoundManager._voice_player.pitch_scale = 0.9
	SoundManager._voice_player.volume_db = -30.0
	var got: float = SoundManager.play_voice_stream(s)
	assert_almost_eq(got, 0.5, 0.001, "the bubble holds for exactly this long")
	assert_eq(SoundManager._voice_player.stream, s)
	assert_eq(SoundManager._voice_player.pitch_scale, 1.0, "a stale pitch would detune the voice and lie about its length")
	assert_eq(SoundManager._voice_player.volume_db, SoundManager.VOICE_PLAYER_BASE_DB)
	SoundManager.stop_voice()


func test_null_plays_nothing_and_holds_for_nothing() -> void:
	assert_eq(SoundManager.play_voice_stream(null), 0.0)
