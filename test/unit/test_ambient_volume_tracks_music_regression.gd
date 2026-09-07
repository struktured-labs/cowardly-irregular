extends GutTest

## cowir-sfx audit msg 2218: _ambient_player.volume_db was a static
## -20.0 literal that no slider ever updated — so interior room tones
## (forge/chapel/library) and weather loops ignored the music slider.
## Lower music to explore quietly and the ambient could end up LOUDER
## than the music it's meant to sit under, and un-muteable. Same
## hardcoded-dB class as the danger-music fix. Ambient now tracks the
## music slider a fixed AMBIENT_OFFSET_DB below it, ducking to silence
## when music is muted.

const SM := preload("res://src/audio/SoundManager.gd")


func _fresh_sm():
	var sm = SM.new()
	add_child_autofree(sm)
	return sm


func test_ambient_sits_below_music_at_every_slider_point() -> void:
	var sm = _fresh_sm()
	if sm._ambient_player == null:
		pass_test("no ambient player in this env")
		return
	# Three slider points: full, half, low.
	for norm in [1.0, 0.5, 0.1]:
		sm.set_music_volume(norm)
		var music_db: float = sm._music_player.volume_db
		var amb_db: float = sm._ambient_player.volume_db
		assert_almost_eq(amb_db, music_db + SM.AMBIENT_OFFSET_DB, 0.01,
			"at slider %.2f ambient must be exactly AMBIENT_OFFSET_DB below music" % norm)
		assert_lt(amb_db, music_db,
			"ambient must stay BELOW music at slider %.2f (the whole point of 'background layer')" % norm)


func test_muting_music_ducks_ambient_toward_silence() -> void:
	var sm = _fresh_sm()
	if sm._ambient_player == null:
		pass_test("no ambient player in this env")
		return
	sm.set_music_volume(0.0)
	assert_lt(sm._ambient_player.volume_db, -60.0,
		"muting music must duck ambient near silence, not leave it droning at -20")


func test_offset_is_negative() -> void:
	assert_lt(SM.AMBIENT_OFFSET_DB, 0.0,
		"the offset must be negative — ambient sits BELOW music, not above")


func test_no_hardcoded_minus_twenty_on_ambient_init() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	assert_false(src.contains("_ambient_player.volume_db = -20.0"),
		"ambient init must derive from _music_base_db, not the -20.0 literal")
