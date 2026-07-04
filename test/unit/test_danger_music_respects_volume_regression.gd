extends GutTest

## Bug 2026-07-04: _apply_danger_intensity hardcoded volume_db = -12.0
## (+ boost) instead of _music_base_db, which is the user's music-volume
## slider value. So the moment a party member's HP dropped enough to
## raise danger intensity, the music JUMPED to the -12 default, ignoring
## the slider — a player at 25% music volume got blasted to near-full
## during tense moments. Now the urgency boost is relative to the user's
## base (matching the corruption path at ~1360). reset_danger restores
## the base too, not the -12 default.

const SM := preload("res://src/audio/SoundManager.gd")


func _fresh_sm():
	var sm = SM.new()
	add_child_autofree(sm)  # _ready → _setup_audio_players creates _music_player
	return sm


func test_intensity_zero_equals_user_base_volume() -> void:
	var sm = _fresh_sm()
	if sm._music_player == null:
		pass_test("no music player in this env")
		return
	sm._music_base_db = -30.0  # simulate a low music-volume slider
	sm._apply_danger_intensity(0.0)
	assert_almost_eq(sm._music_player.volume_db, -30.0, 0.01,
		"at intensity 0 the volume must equal the user's base (-30), not the hardcoded -12")


func test_max_intensity_boosts_relative_to_base() -> void:
	var sm = _fresh_sm()
	if sm._music_player == null:
		pass_test("no music player in this env")
		return
	sm._music_base_db = -30.0
	sm._apply_danger_intensity(1.0)
	assert_almost_eq(sm._music_player.volume_db, -27.0, 0.01,
		"max danger = base + 3dB boost (-30 + 3), not -12 + 3")


func test_reset_danger_restores_user_base() -> void:
	var sm = _fresh_sm()
	if sm._music_player == null:
		pass_test("no music player in this env")
		return
	sm._music_base_db = -25.0
	sm._apply_danger_intensity(1.0)
	sm.reset_danger()
	assert_almost_eq(sm._music_player.volume_db, -25.0, 0.01,
		"reset_danger must return to the user's base volume, not -12")


func test_no_hardcoded_minus_twelve_in_danger_volume_path() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	var fn: int = src.find("func _apply_danger_intensity")
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_false(body.contains("= -12.0 + volume_boost"),
		"the danger volume must derive from _music_base_db, not the -12.0 literal")
	assert_true(body.contains("_music_base_db + volume_boost"),
		"danger boost must be relative to the user's music volume")
