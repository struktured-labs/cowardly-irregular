extends GutTest

## The autogrind corruption detune vanished at the next track change and did not come back.
##
## Corruption audio degradation is listed as fully wired, and it is — until the music changes.
## `_apply_corruption_intensity` is written ONLY by the corruption tween, and that tween fires on
## a change of >= 0.04. A track change calls `reset_danger()`, which wrote pitch back to a clean
## 1.0. Nothing re-applied the settled level. Measured before the fix, corruption held at 0.8:
##
##     settled            pitch 0.9767   corruption 0.800
##     play_music         pitch 1.0000   corruption 0.800   <- detune gone, state unchanged
##     play_area_music    pitch 1.0000   corruption 0.800
##     corruption +0.02   pitch 1.0000                      <- and it does NOT return: the
##                                                             threshold swallows the change
##
## 🔑 SO THE STATE AND THE SOUND DISAGREED SILENTLY. Every battle start, every victory and every
## area transition cleaned the music while the grind's corruption meter kept climbing; the player
## heard a clean bed at corruption 0.8, which is the one thing the feature exists to prevent.
## `reset_danger` now restores the CORRUPTION BASELINE rather than a hardcoded clean slate.
##
## 📌 WHICH FILE OWNS WHICH MUTATION, measured, so a joint green is not read as one verdict:
##     the reset erases the settled detune   -> THIS file, 3 arms   (the danger guards stay green:
##                                              at corruption 0 their verdict does not move)
##     play_area_music stops resetting at all -> test_an_area_bed_is_not_pitched_by_the_last_fight,
##                                              2 arms. THIS file stays green, because "never reset"
##                                              and "reset then restore" leave the same pitch.
## Neither file is redundant and neither alone covers the pair.
##
## ⚠️ THE WAIT DECIDES WHAT YOU MEASURE, and my first probe measured nothing. Read a frame or two
## after set_corruption_intensity and the tween is still running — it writes pitch every step, so
## it overwrites the very reset under test and the bug is invisible. These arms wait for
## `_corruption_intensity` to REACH `_corruption_target` and for the tween to stop.

const CORRUPT := 0.8


func before_each() -> void:
	SoundManager.reset_corruption()
	SoundManager.reset_danger()


func after_each() -> void:
	SoundManager.reset_corruption()
	SoundManager.reset_danger()
	SoundManager.stop_music()


func _settle_corruption(level: float) -> void:
	SoundManager.set_corruption_intensity(level)
	for i in range(1200):
		await get_tree().process_frame
		var done: bool = SoundManager._corruption_tween == null or not SoundManager._corruption_tween.is_running()
		if done and absf(SoundManager._corruption_intensity - SoundManager._corruption_target) < 0.001:
			return


func _frames(n: int = 4) -> void:
	for i in range(n):
		await get_tree().process_frame


func _pitch() -> float:
	return SoundManager._music_player.pitch_scale if SoundManager._music_player else -1.0


func test_a_new_track_keeps_the_corruption_detune() -> void:
	SoundManager.play_music("battle_medieval")
	await _frames()
	await _settle_corruption(CORRUPT)
	var settled: float = _pitch()
	assert_lt(settled, 0.99, "CONTROL: corruption %.2f must audibly detune the bed; pitch is %.4f" % [CORRUPT, settled])

	SoundManager.play_music("victory")
	await _frames()
	assert_almost_eq(_pitch(), settled, 0.004,
		"a track change must keep the grind's detune — pitch went to %.4f while corruption still reads %.3f" % [_pitch(), SoundManager._corruption_intensity])


func test_an_area_bed_keeps_it_too() -> void:
	## play_area_music reaches the same reset by a different road, and it is the road a player
	## takes most: every overworld/village/dungeon transition during a grind.
	SoundManager.play_music("battle_medieval")
	await _frames()
	await _settle_corruption(CORRUPT)
	var settled: float = _pitch()
	assert_lt(settled, 0.99, "CONTROL: the detune is in place before the transition (pitch %.4f)" % settled)

	SoundManager.play_area_music("cave")
	await _frames(8)
	assert_almost_eq(_pitch(), settled, 0.004,
		"walking into an area must keep the detune — pitch %.4f, corruption %.3f" % [_pitch(), SoundManager._corruption_intensity])


func test_the_fix_does_not_wait_for_the_next_corruption_step() -> void:
	## Why the erasure was invisible: the tween only fires on a change of >= 0.04, so a guard that
	## merely checked "corruption returns eventually" would pass on a grind that keeps climbing.
	## After the change, a sub-threshold nudge must find the bed ALREADY detuned.
	SoundManager.play_music("battle_medieval")
	await _frames()
	await _settle_corruption(CORRUPT)
	var settled: float = _pitch()
	SoundManager.play_music("victory")
	await _frames()
	SoundManager.set_corruption_intensity(CORRUPT + 0.02)
	await _frames(6)
	assert_almost_eq(_pitch(), settled, 0.004,
		"a sub-threshold nudge changes nothing, so the detune had to survive the track change on its own (pitch %.4f)" % _pitch())
	assert_almost_eq(SoundManager._corruption_intensity, CORRUPT, 0.001,
		"CONTROL: the nudge really was swallowed — corruption is still %.3f, so nothing re-applied it for us" % SoundManager._corruption_intensity)


func test_a_clean_grind_still_plays_clean() -> void:
	## The restore must be conditional. At corruption 0 a new track is untouched, which is also
	## what the danger guards pin from the other side.
	SoundManager.play_music("battle_medieval")
	await _frames()
	assert_almost_eq(_pitch(), 1.0, 0.001, "CONTROL: a clean grind starts at 1.0")
	SoundManager.set_danger_intensity(1.0)
	await _frames(60)
	SoundManager.play_music("victory")
	await _frames()
	assert_almost_eq(_pitch(), 1.0, 0.001,
		"with no corruption the clean slate is still the right baseline — pitch %.4f" % _pitch())
