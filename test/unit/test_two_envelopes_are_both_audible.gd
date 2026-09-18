extends GutTest

## Danger and corruption are two meters sharing ONE pair of properties, and each wrote absolute
## values to both. Last writer wins — and it is ALWAYS corruption, because danger's tween is 0.5 s
## against corruption's 1.5 s, so danger's contribution vanishes the instant its own tween ends and
## corruption keeps writing for another second.
##
## ⛔ MEASURED 2026-09-18, both tweens live: `_danger_intensity` reported 1.00 while the player sat
## at pitch 0.9855 and -12.26 dB — corruption's numbers. Danger's own 1.15 and base+3.0 were not
## merely diluted, they were ABSENT. The critical-HP cue does not play at all for the duration of a
## corrupted grind, and the system believes it is at maximum.
##
## 🔑 REACHABLE IN THE PILLAR: corruption is an autogrind meter and danger fires on low party HP, so
## "the risky grind going badly" — the one moment the audio exists to sell — is exactly where both
## are on.
##
## The repair is ONE renderer for both meters: pitch composes multiplicatively (two independent
## detunes, not two opinions), volume adds both offsets to the user's base. Each envelope alone is
## bit-identical to before, which the two solo arms below pin.

const BED := "overworld_medieval"


func before_each() -> void:
	SoundManager.reset_danger()
	SoundManager.reset_corruption()
	SoundManager.set_music_volume(1.0)


func after_each() -> void:
	SoundManager.reset_danger()
	SoundManager.reset_corruption()
	SoundManager.set_music_volume(1.0)
	SoundManager.stop_music()


func test_control_danger_alone_is_unchanged() -> void:
	## The margin this repair must not move.
	SoundManager._apply_danger_intensity(1.0)
	assert_almost_eq(SoundManager._music_player.pitch_scale, 1.15, 0.0001,
		"danger alone must still reach exactly 1.15")
	assert_almost_eq(SoundManager._music_player.volume_db, SoundManager._music_base_db + 3.0, 0.0001,
		"danger alone must still reach exactly base + 3 dB")


func test_control_corruption_alone_is_unchanged() -> void:
	SoundManager._apply_corruption_intensity(0.5)
	## flat offset only at 0.5 — the wobble term is time-dependent, so bound it rather than pin it.
	assert_lt(SoundManager._music_player.pitch_scale, 0.9901,
		"corruption alone at 0.5 must still detune to about -1.5%% (got %.4f)" % SoundManager._music_player.pitch_scale)
	assert_gt(SoundManager._music_player.pitch_scale, 0.9799,
		"and not further than its own wobble allows (got %.4f)" % SoundManager._music_player.pitch_scale)
	assert_almost_eq(SoundManager._music_player.volume_db, SoundManager._music_base_db, 0.0001,
		"corruption below 0.6 must not touch the level")


func test_danger_survives_a_corrupted_grind() -> void:
	## ⛔ MUST GO THROUGH THE SETTERS AND WAIT. My first version of this arm called
	## `_apply_danger_intensity` directly after `_apply_corruption_intensity` and PASSED on the bug —
	## a direct call writes both properties, so whichever is called last wins and danger looked fine.
	## The defect is TEMPORAL: danger's tween is 0.5 s, corruption's is 1.5 s, so danger stops
	## writing a second before corruption does and the final state is corruption's alone.
	SoundManager.set_corruption_intensity(0.8)
	await get_tree().process_frame
	SoundManager.set_danger_intensity(1.0)
	## Past danger's 0.5 s tween, still inside corruption's 1.5 s one — the window a player spends
	## most of a corrupted critical-HP fight in.
	await get_tree().create_timer(0.8).timeout
	assert_almost_eq(SoundManager._danger_intensity, 1.0, 0.01,
		"CONTROL: danger must have reached full, or this arm is about a cue that never armed")
	assert_gt(SoundManager._corruption_intensity, 0.0,
		"CONTROL: corruption must still be live, or there is no conflict to measure")
	assert_gt(SoundManager._music_player.pitch_scale, 1.10,
		"danger is at %.2f and the pitch is %.4f — the +15%% critical-HP detune is absent, not diluted, because corruption's longer tween outlived it" % [SoundManager._danger_intensity, SoundManager._music_player.pitch_scale])


func test_the_danger_boost_survives_a_corrupted_grind() -> void:
	## The volume half, same temporal window.
	SoundManager.set_corruption_intensity(0.8)
	await get_tree().process_frame
	SoundManager.set_danger_intensity(1.0)
	await get_tree().create_timer(0.8).timeout
	assert_almost_eq(SoundManager._danger_intensity, 1.0, 0.01, "CONTROL: danger at full")
	assert_gt(SoundManager._music_player.volume_db, SoundManager._music_base_db + 2.0,
		"the +3 dB danger boost is gone: player at %.2f against base %.2f" % [SoundManager._music_player.volume_db, SoundManager._music_base_db])


func test_corruption_still_reaches_the_pitch_under_danger() -> void:
	## The other direction, so the repair cannot be "danger simply wins". Both settled.
	SoundManager.set_danger_intensity(1.0)
	await get_tree().create_timer(0.7).timeout
	var danger_only: float = SoundManager._music_player.pitch_scale
	assert_gt(danger_only, 1.10, "CONTROL: danger alone reached %.4f" % danger_only)
	SoundManager.set_corruption_intensity(0.8)
	await get_tree().create_timer(1.8).timeout
	assert_lt(SoundManager._music_player.pitch_scale, danger_only - 0.01,
		"corruption must still pull the pitch down under danger — %.4f vs danger-only %.4f" % [SoundManager._music_player.pitch_scale, danger_only])
	assert_gt(SoundManager._music_player.pitch_scale, 1.05,
		"and danger must still be the dominant term: %.4f" % SoundManager._music_player.pitch_scale)
