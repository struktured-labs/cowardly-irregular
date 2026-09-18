extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

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
	## ⛔ RE-POINTED 2026-09-18, and the reason is worth keeping: the danger volume moved out of
	## _apply_danger_intensity into _render_music_envelope, because danger and corruption each wrote
	## pitch_scale and volume_db outright and the last writer won. The CLAIM here never changed — the
	## boost derives from the user's base, never from the -12.0 default. What broke was a pin on a
	## LOCAL VARIABLE'S NAME (`volume_boost`), which a correct refactor is free to rename.
	## 🔑 The three arms above are the real cover: at base -30 they read -30 / -27 / -30, so a
	## hardcoded -12 reds them immediately. This is belt-and-braces over the owner's identity.
	## ⛔ COMMENT-STRIPPED, and the absence assert below is why: my own renderer's comment says
	## "a hardcoded -12.0 clobbered the slider", so a raw read makes this arm red on correct code.
	## An absence assert takes prose as a hit — the one direction where a comment fails LOUD.
	var src: String = GdSource.code_of("res://src/audio/SoundManager.gd")
	var fn: int = src.find("func _render_music_envelope")
	assert_gt(fn, -1,
		"CONTROL: _render_music_envelope must exist — it owns the danger volume since the composition fix")
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_false(body.contains("-12.0"),
		"the danger volume must derive from _music_base_db, not the -12.0 literal")
	assert_true(body.contains("_music_base_db + _danger_intensity * 3.0"),
		"danger boost must be relative to the user's music volume")


func test_the_applier_moves_the_meter_and_nothing_else() -> void:
	## The structural half the old spelling pin could not make. A second absolute writer of these two
	## properties is exactly how danger and corruption came to overwrite each other — whichever ran
	## last won, and which one that was depended on call order and the tweens' differing lifetimes.
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	for fname in ["_apply_danger_intensity", "_apply_corruption_intensity"]:
		var i: int = src.find("func " + fname)
		assert_gt(i, -1, "CONTROL: %s must exist" % fname)
		var body: String = src.substr(i, src.find("\nfunc ", i + 1) - i)
		assert_false(body.contains("volume_db"),
			"%s writes volume_db directly — it must move its own meter and defer to _render_music_envelope, or the two envelopes overwrite each other again" % fname)
		assert_false(body.contains("pitch_scale"),
			"%s writes pitch_scale directly — same reason" % fname)
		assert_true(body.contains("_render_music_envelope()"),
			"%s must hand off to the single renderer" % fname)
