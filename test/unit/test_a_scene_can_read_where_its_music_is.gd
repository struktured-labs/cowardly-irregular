extends GutTest

## The inn night kept its own clock beside a 5.7 s ditty and ran ~1.9x its length in a capture (cowir-cutscenes 24558).
## A scene timed to a cue reads the cue: SoundManager.music_position_of(track) is the position of what is HEARD,
## and -1.0 whenever that track is not the stream sounding, so a caller falls back instead of dividing a stale number.

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const BED := "battle_medieval"
const DITTY := "inn_rest_ditty"
const HELD_AT := 40.0


func before_each() -> void:
	SoundManager.stop_music()


func after_each() -> void:
	SoundManager.stop_music()
	SoundState.restore()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func test_floor_the_accessor_and_the_ditty_exist() -> void:
	assert_true(SoundManager.has_method("music_position_of"), "SoundManager.music_position_of is gone; every arm below would abort")
	assert_true(SoundManager.has_music_track(DITTY), "the inn ditty is not in the manifest; the night would have no cue to read")


func test_nothing_sounding_reads_minus_one() -> void:
	assert_eq(SoundManager.music_position_of(BED), -1.0, "a bed that is not playing must read -1, not a position")
	assert_eq(SoundManager.music_position_of(""), -1.0, "the empty id must never match silence")


func test_a_bed_reads_where_it_is_and_only_under_its_own_name() -> void:
	SoundManager.play_music(BED, false, HELD_AT)
	await _frames(20)
	assert_eq(SoundManager.playing_track_stem(), BED, "CONTROL: the bed must really be what is sounding")
	var at: float = SoundManager.music_position_of(BED)
	assert_gt(at, HELD_AT - 1.0, "the bed was started at %.0f s and reads %.2f: a caller timing a scene to it would start over" % [HELD_AT, at])
	assert_eq(SoundManager.music_position_of(DITTY), -1.0, "another track's name must not read this bed's position")
	SoundManager.stop_music()
	assert_eq(SoundManager.music_position_of(BED), -1.0, "a stopped bed still reads %.2f" % SoundManager.music_position_of(BED))


func test_the_inn_ditty_reads_inside_its_own_length() -> void:
	SoundManager.play_music(BED)
	await _frames(5)
	SoundManager.play_music(DITTY, true)
	await _frames(20)
	var at: float = SoundManager.music_position_of(DITTY)
	var length: float = SoundManager._music_player.stream.get_length()
	assert_between(length, 5.0, 6.5, "CONTROL: the stream sounding must be the 5.7 s ditty, not %.2f s of something else" % length)
	assert_between(at, 0.0, length, "the ditty reads %.2f, outside its own %.2f s" % [at, length])
	assert_eq(SoundManager.music_position_of(BED), -1.0, "the bed the ditty interrupted must read -1 while the ditty sounds")
