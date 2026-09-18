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
	## ⚠️ DELIBERATELY LITERAL, unlike the conflict arms below. Its whole job is "the composition
	## refactor did not move the solo value", so the authored numbers ARE the claim. That makes it
	## fixture-dependent BY DESIGN: authoring a new danger curve reds it, and updating the literal is
	## the deliberate act this arm exists to force. Say which you did in the commit.
	SoundManager._apply_danger_intensity(1.0)
	assert_almost_eq(SoundManager._music_player.pitch_scale, 1.15, 0.0001,
		"danger alone must still reach exactly 1.15")
	assert_almost_eq(SoundManager._music_player.volume_db, SoundManager._music_base_db + 3.0, 0.0001,
		"danger alone must still reach exactly base + 3 dB")


func test_control_corruption_alone_is_unchanged() -> void:
	SoundManager._apply_corruption_intensity(0.5)
	## Bounded rather than pinned because the wobble term is time-dependent — but the bounds are
	## still today's authored constants, on purpose, for the same reason as the danger arm above.
	assert_lt(SoundManager._music_player.pitch_scale, 0.9901,
		"corruption alone at 0.5 must still detune to about -1.5%% (got %.4f). If you AUTHORED a new detune, update this bound and the one below — this arm is a deliberate value pin on the solo envelope, and a correct mix change is meant to land here" % SoundManager._music_player.pitch_scale)
	assert_gt(SoundManager._music_player.pitch_scale, 0.9799,
		"and not further than its own wobble allows (got %.4f). Same note: an authored detune change updates this bound; a COMPOSITION change must not reach it at all" % SoundManager._music_player.pitch_scale)
	assert_almost_eq(SoundManager._music_player.volume_db, SoundManager._music_base_db, 0.0001,
		"corruption below 0.6 must not touch the level")


## Reset both meters and prove the player is clean before an arm leans on a reference value.
func _clean_slate() -> void:
	SoundManager.reset_danger()
	SoundManager.reset_corruption()
	assert_almost_eq(SoundManager._music_player.pitch_scale, 1.0, 0.0001,
		"PRECONDITION: the player must start this measurement at pitch 1.0, not %.4f" % SoundManager._music_player.pitch_scale)


func test_danger_survives_a_corrupted_grind() -> void:
	## ⛔ MUST GO THROUGH THE SETTERS AND WAIT. My first version of this arm called
	## `_apply_danger_intensity` directly after `_apply_corruption_intensity` and PASSED on the bug —
	## a direct call writes both properties, so whichever is called last wins and danger looked fine.
	## The defect is TEMPORAL: danger's tween is 0.5 s, corruption's is 1.5 s, so danger stops
	## writing a second before corruption does and the final state is corruption's alone.
	##
	## ⛔ AND THE THRESHOLD IS MEASURED, NOT LITERAL. This arm first asserted `pitch > 1.10`, which
	## encoded today's constants with a margin of 0.0092 against a wobble term of ±0.0115 — and
	## authoring corruption's flat offset at -0.08 instead of -0.03 would have red it on a CORRECT
	## change. What the arm actually claims is a RELATIONSHIP: danger contributes most of its own
	## lift on top of whatever corruption is doing. So both solo values are measured first and the
	## composed one is judged against them (@cowir-sfx's coincidental-fixture shape, on my own arm).
	_clean_slate()
	SoundManager._apply_corruption_intensity(0.8)
	var corr_only: float = SoundManager._music_player.pitch_scale

	_clean_slate()
	SoundManager._apply_danger_intensity(1.0)
	var danger_lift: float = SoundManager._music_player.pitch_scale - 1.0
	assert_gt(danger_lift, 0.01,
		"CONTROL: danger must lift the pitch at all (%.4f) or there is nothing for corruption to erase" % danger_lift)
	assert_lt(corr_only, 1.0,
		"CONTROL: corruption must lower the pitch (%.4f), so the two pull opposite ways" % corr_only)

	_clean_slate()
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
	var gained: float = SoundManager._music_player.pitch_scale - corr_only
	assert_gt(gained, danger_lift * 0.5,
		"danger is at %.2f and contributed only %.4f of its own %.4f lift over corruption's %.4f — the critical-HP detune is absent, not diluted, because corruption's longer tween outlived it" % [SoundManager._danger_intensity, gained, danger_lift, corr_only])


func test_the_danger_boost_survives_a_corrupted_grind() -> void:
	## The volume half, same temporal window and the same measured-reference discipline. The old
	## literal here was `> base + 2.0` against a worst case of base + 2.20 — a 0.2 dB margin on a
	## `randf_range` flicker.
	_clean_slate()
	SoundManager._apply_danger_intensity(1.0)
	var danger_lift_db: float = SoundManager._music_player.volume_db - SoundManager._music_base_db
	assert_gt(danger_lift_db, 0.5,
		"CONTROL: danger must raise the level at all (+%.2f dB)" % danger_lift_db)

	_clean_slate()
	SoundManager.set_corruption_intensity(0.8)
	await get_tree().process_frame
	SoundManager.set_danger_intensity(1.0)
	await get_tree().create_timer(0.8).timeout
	assert_almost_eq(SoundManager._danger_intensity, 1.0, 0.01, "CONTROL: danger at full")
	var lift_now: float = SoundManager._music_player.volume_db - SoundManager._music_base_db
	assert_gt(lift_now, danger_lift_db * 0.5,
		"the danger boost is +%.2f dB of its own +%.2f — the cue is gone under corruption (player %.2f, base %.2f)" % [lift_now, danger_lift_db, SoundManager._music_player.volume_db, SoundManager._music_base_db])


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
