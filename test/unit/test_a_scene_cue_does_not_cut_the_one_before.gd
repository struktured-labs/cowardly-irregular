extends GutTest

## 29 boss cards gained the 2.0 s stinger in .810; a scene that draws a sword three steps later cut it mid-ring, because
## every scene cue shared ONE player. Two voices now: the newest cue is always on _cutscene_player, the one before on the tail.

const LONG := "boss_intro_stinger"
const NEXT := "sword_draw_heavy"
const THIRD := "door_open"


func before_each() -> void:
	SoundManager.stop_cutscene_sfx()
	for key in [LONG, NEXT, THIRD]:
		SoundManager._sfx_cooldowns.erase(key)  # the per-key cooldown would swallow a cue an earlier arm played


func after_each() -> void:
	SoundManager.stop_cutscene_sfx()


func _stream_of(p: AudioStreamPlayer) -> String:
	return "" if p == null or p.stream == null else str(p.stream.resource_path)


func _sounding() -> int:
	var n := 0
	for voice in [SoundManager._cutscene_player, SoundManager._cutscene_tail_player]:
		n += 1 if voice != null and voice.playing else 0
	return n


func test_the_next_cue_leaves_the_one_before_sounding() -> void:
	assert_not_null(SoundManager._cutscene_tail_player, "PREMISE: the tail voice exists")
	assert_ne(SoundManager._cutscene_tail_player, SoundManager._cutscene_player, "PREMISE: the two voices are two nodes")
	SoundManager.play_cutscene_sfx(LONG)
	var first: AudioStreamPlayer = SoundManager._cutscene_player
	assert_true(first.playing and _stream_of(first).contains(LONG), "PREMISE: the stinger started on the cutscene voice")
	assert_eq(_sounding(), 1, "CONTROL: one cue so far, one voice sounding")
	SoundManager.play_cutscene_sfx(NEXT)
	assert_true(first.playing and _stream_of(first).contains(LONG), "the stinger is still ringing after the sword is drawn: its voice holds %s, playing=%s" % [_stream_of(first), first.playing])
	assert_ne(SoundManager._cutscene_player, first, "the newest cue took the other voice")
	assert_true(SoundManager._cutscene_player.playing and _stream_of(SoundManager._cutscene_player).contains(NEXT), "_cutscene_player names the NEWEST cue: %s" % _stream_of(SoundManager._cutscene_player))
	assert_almost_eq(SoundManager._cutscene_player.pitch_scale, 1.0, 0.0001, "the newest cue plays as made on either voice")


func test_a_skip_takes_both_cues_with_it() -> void:
	SoundManager.play_cutscene_sfx(LONG)
	SoundManager.play_cutscene_sfx(NEXT)
	assert_eq(_sounding(), 2, "CONTROL: two cues are sounding before the skip")
	SoundManager.stop_cutscene_sfx()
	assert_eq(_sounding(), 0, "a skipped scene leaves neither the newest cue nor the tail under it")


## A repeat inside the cooldown starts nothing. The role must not move to the silent voice, or readers of _cutscene_player see silence.
func test_a_swallowed_repeat_does_not_move_the_role() -> void:
	SoundManager.play_cutscene_sfx(LONG)
	var first: AudioStreamPlayer = SoundManager._cutscene_player
	SoundManager.play_cutscene_sfx(LONG)
	assert_eq(_sounding(), 1, "PREMISE: the cooldown swallowed the repeat, so one voice sounds")
	assert_eq(SoundManager._cutscene_player, first, "the role stays on the voice that is sounding")
	assert_true(SoundManager._cutscene_player.playing, "_cutscene_player still names a sounding cue")


## Two voices, not three: the third cue replaces the OLDEST, and the one before it lives on.
func test_a_third_cue_replaces_the_oldest() -> void:
	SoundManager.play_cutscene_sfx(LONG)
	var oldest: AudioStreamPlayer = SoundManager._cutscene_player
	SoundManager.play_cutscene_sfx(NEXT)
	var middle: AudioStreamPlayer = SoundManager._cutscene_player
	SoundManager.play_cutscene_sfx(THIRD)
	assert_eq(SoundManager._cutscene_player, oldest, "CONTROL: the third cue reuses the oldest cue's voice")
	assert_true(_stream_of(oldest).contains(THIRD), "the oldest cue gave way to the third: %s" % _stream_of(oldest))
	assert_true(middle.playing and _stream_of(middle).contains(NEXT), "the cue before the newest is still sounding")
