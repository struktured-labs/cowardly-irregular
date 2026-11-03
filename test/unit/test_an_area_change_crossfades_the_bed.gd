extends GutTest
## An area change crossfades (2026-11-02, lane/music-area-crossfade).
##
## play_area_music used to call stop_music() and start the next bed cold a frame later: every
## village <-> overworld walk, interior door, and return-to-field after a battle was a hard cut.
## It now hands the outgoing bed to _music_player_b (fading over CROSSFADE_DURATION) while
## _try_play_from_manifest ramps the incoming bed up from FADE_IN_FLOOR_DB to _music_base_db.

const AREA_A := "harmonia_village"
const AREA_B := "overworld"

var _saved_base_db: float


func before_each() -> void:
	_saved_base_db = SoundManager._music_base_db
	SoundManager.stop_music()
	SoundManager.set_music_volume(0.5)  # -16 dB: well above the -40 floor


func after_each() -> void:
	SoundManager.stop_music()
	SoundManager._music_base_db = _saved_base_db
	if SoundManager._music_player:
		SoundManager._music_player.volume_db = _saved_base_db


func _settle_on(area: String) -> void:
	SoundManager.play_area_music(area)
	await wait_frames(2)
	await wait_seconds(SoundManager.FADE_IN_DURATION + 0.2)


func _a() -> AudioStreamPlayer:
	return SoundManager._music_player


func _b() -> AudioStreamPlayer:
	return SoundManager._music_player_b


func test_PREMISE_both_beds_are_real_files() -> void:
	await _settle_on(AREA_A)
	assert_true(_a().playing, "PREMISE: %s did not start a bed" % AREA_A)
	assert_almost_eq(_a().volume_db, SoundManager._music_base_db, 0.5, "PREMISE: the settled bed sits at the slider level")


func test_an_area_change_does_not_hard_stop_the_old_bed() -> void:
	await _settle_on(AREA_A)
	var old_stream: AudioStream = _a().stream
	var base: float = SoundManager._music_base_db
	SoundManager.play_area_music(AREA_B)
	assert_true(_b().playing, "the outgoing bed must keep sounding on player B, not be stopped")
	assert_eq(_b().stream, old_stream, "player B carries the OUTGOING bed")
	assert_almost_eq(_b().volume_db, base, 0.5, "the hand-off itself is seamless: B starts at the old level")
	await wait_seconds(SoundManager.CROSSFADE_DURATION * 0.5)
	assert_true(_b().playing, "halfway through the window the old bed is still fading, not gone")
	assert_lt(_b().volume_db, base - 3.0, "and it is actually fading")
	await wait_seconds(SoundManager.CROSSFADE_DURATION * 0.5 + 0.2)
	assert_false(_b().playing, "after the window player B is stopped -- no leftover bed")


func test_the_new_bed_starts_low_and_reaches_its_level() -> void:
	await _settle_on(AREA_A)
	var base: float = SoundManager._music_base_db
	SoundManager.play_area_music(AREA_B)
	await wait_frames(2)  # the area start is deferred one frame
	assert_true(_a().playing, "the new bed started")
	assert_ne(_a().stream, _b().stream, "player A now holds the INCOMING bed")
	assert_lt(_a().volume_db, base - 6.0, "the new bed enters low, not at full level")
	await wait_seconds(SoundManager.FADE_IN_DURATION + 0.2)
	assert_almost_eq(_a().volume_db, base, 0.5, "and ramps to the slider level")


func test_never_two_full_volume_beds_at_once() -> void:
	await _settle_on(AREA_A)
	var base: float = SoundManager._music_base_db
	SoundManager.play_area_music(AREA_B)
	var frames := 0
	var overlap_frames := 0
	var t_end: int = Time.get_ticks_msec() + int((SoundManager.CROSSFADE_DURATION + 0.3) * 1000.0)
	while Time.get_ticks_msec() < t_end:
		await wait_frames(1)
		frames += 1
		if _a().playing and _b().playing:
			overlap_frames += 1
			assert_false(_a().volume_db > base - 3.0 and _b().volume_db > base - 3.0,
				"frame %d: A %.1f dB and B %.1f dB are both near full level" % [frames, _a().volume_db, _b().volume_db])
	assert_gt(overlap_frames, 0, "PREMISE: the two beds did overlap (a crossfade), or this arm checked nothing")


func test_the_same_area_again_is_a_no_op() -> void:
	await _settle_on(AREA_A)
	var stream: AudioStream = _a().stream
	var pos: float = _a().get_playback_position()
	var vol: float = _a().volume_db
	SoundManager.play_area_music(AREA_A)
	await wait_frames(2)
	assert_eq(_a().stream, stream, "same stream")
	assert_false(_b().playing, "nothing was handed off")
	assert_gte(_a().get_playback_position(), pos, "the bed was not restarted")
	assert_almost_eq(_a().volume_db, vol, 0.5, "and its level did not dip")


func test_a_muted_player_never_swells_on_an_area_change() -> void:
	SoundManager.set_music_volume(0.0)  # -80
	await _settle_on(AREA_A)
	SoundManager.play_area_music(AREA_B)
	var t_end: int = Time.get_ticks_msec() + int((SoundManager.FADE_IN_DURATION + 0.3) * 1000.0)
	while Time.get_ticks_msec() < t_end:
		await wait_frames(1)
		assert_lte(_a().volume_db, -79.0, "incoming bed rose to %.1f dB while muted" % _a().volume_db)
		if _b().playing:
			assert_lte(_b().volume_db, -79.0, "outgoing bed rose to %.1f dB while muted" % _b().volume_db)


func test_a_stinger_still_hits_at_full_level() -> void:
	await _settle_on(AREA_A)
	SoundManager.play_music("stinger_item_found")
	assert_almost_eq(_a().volume_db, SoundManager._music_base_db, 0.5, "a stinger is not faded in")


## .764 interaction: the quest-accept jingle ducks the MusicDuck BUS (slot 3) while the area change
## crossfades the PLAYERS. They are independent layers; neither may strand the other.
func test_a_jingle_during_an_area_change_ducks_and_both_settle() -> void:
	await _settle_on(AREA_A)
	var base: float = SoundManager._music_base_db
	SoundManager.play_area_music(AREA_B)
	assert_true(SoundManager.play_jingle("quest_accept"), "PREMISE: the quest_accept jingle is a real file on JinglePlayer")
	var jingle_len: float = 1.0
	if SoundManager._jingle_player.stream:
		jingle_len = SoundManager._jingle_player.stream.get_length()
	var deepest: float = 0.0
	var t_end: int = Time.get_ticks_msec() + int((SoundManager.CROSSFADE_DURATION + 0.3) * 1000.0)
	while Time.get_ticks_msec() < t_end:
		await wait_process_frames(1)
		deepest = minf(deepest, SoundManager.get_jingle_duck_db())
		assert_lte(_a().volume_db, base + 0.01, "incoming bed overshot its level under a jingle")
		if _b().playing:
			assert_lte(_b().volume_db, base + 0.01, "outgoing bed rose under a jingle")
	assert_lt(deepest, -4.0, "the jingle ducked the music bus during the crossfade (deepest %.1f dB)" % deepest)
	assert_false(_b().playing, "the crossfade still finished: player B stopped")
	assert_true(_a().playing, "the new bed is playing")
	await wait_seconds(maxf(jingle_len + SoundManager.JINGLE_DUCK_RELEASE_TIME + 0.4 - (SoundManager.CROSSFADE_DURATION + 0.3), 0.3))
	assert_almost_eq(SoundManager.get_jingle_duck_db(), 0.0, 0.05, "the jingle duck released after the area change")
	assert_almost_eq(_a().volume_db, base, 0.5, "and the new bed sits at the user's level")


## A jingle that is already ducking when the area changes keeps its release; the stop_music(true) disarm does not touch the duck bus.
func test_an_area_change_mid_jingle_does_not_strand_the_duck() -> void:
	await _settle_on(AREA_A)
	assert_true(SoundManager.play_jingle("quest_accept"), "PREMISE: jingle played")
	var jingle_len: float = SoundManager._jingle_player.stream.get_length() if SoundManager._jingle_player.stream else 1.0
	await wait_seconds(0.15)
	assert_lt(SoundManager.get_jingle_duck_db(), -4.0, "PREMISE: the duck is engaged")
	SoundManager.play_area_music(AREA_B)
	await wait_seconds(jingle_len + SoundManager.JINGLE_DUCK_RELEASE_TIME + 0.4)
	assert_almost_eq(SoundManager.get_jingle_duck_db(), 0.0, 0.05, "the duck released despite the area change")
	assert_false(_b().playing, "the crossfade finished")
	assert_almost_eq(_a().volume_db, SoundManager._music_base_db, 0.5, "new bed at the user's level")
