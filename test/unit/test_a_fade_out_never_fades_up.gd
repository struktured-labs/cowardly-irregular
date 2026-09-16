extends GutTest

## Two defects in one six-line function, both audible, both measured 2026-09-16.
##
## ⛔ IT FADED UP. `fade_out_music` tweened `volume_db` to a hardcoded -40, which is "silent enough"
## only from above. The slider maps to -80 at mute, so muted music SWELLED for the whole duration
## and then cut. Measured, muted, at the battle site's 1.2 s:
##
##     -79.8 → -74.7 → -69.7 → -64.6 → -59.5 → -54.5 → -49.4 → -44.4 → -40.0
##
## That is the crossfade's own inversion (`a90ae379`) a second time, at five call sites — every
## cutscene start (0.3 s), the credits (0.6 s), closing the Jukebox (0.4 s) and TWICE in battle at
## 1.2 s, one of them Mordaine's unmasking. The battle sites travel the full 40 dB.
##
## ⛔ AND IT ORPHANED THE OUTGOING BED. The function kills `_crossfade_tween` to take it over — and
## that tween carries the callback that STOPS the B player. Fade within CROSSFADE_DURATION of a
## track change and B played on forever: measured -10.8 dB, full level, with `_music_playing`
## already false and nothing left to stop it but a later `play_music`/`stop_music`. The reachable
## shape is the Jukebox: pick a track, close the menu inside half a second, and the track you left
## follows you back to the overworld under the bed that replaces it.
##
## 🔑 The two fixes compose: B is faded on the SAME tween with the SAME minf, so the bed that must
## stop also cannot rise on its way out.

const BED := "battle_medieval"
const NEXT := "victory"


func before_each() -> void:
	SoundManager.stop_music()
	SoundManager.set_music_volume(1.0)


func after_each() -> void:
	SoundManager.set_music_volume(1.0)
	SoundManager.stop_music()


func _frames(n: int = 4) -> void:
	for i in range(n):
		await get_tree().process_frame


## Wall-clock, never frame-counted: these tweens set_ignore_time_scale, and a headless frame is far
## shorter than a rendered one, so "60 frames" is not "1.2 seconds".
func _wait_ms(ms: int) -> void:
	var deadline: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


## Highest level the main player reaches while a fade runs.
func _peak_during_fade(duration: float) -> float:
	SoundManager.fade_out_music(duration)
	var peak: float = -1000.0
	var deadline: int = Time.get_ticks_msec() + int(duration * 1000.0) + 200
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		peak = maxf(peak, SoundManager._music_player.volume_db)
	return peak


func test_a_muted_player_hears_nothing_when_the_music_fades_out() -> void:
	SoundManager.set_music_volume(0.0)
	assert_almost_eq(SoundManager._music_base_db, -80.0, 0.01, "CONTROL: mute puts the base at -80 dB")
	SoundManager.play_music(BED)
	await _frames()
	assert_almost_eq(SoundManager._music_player.volume_db, -80.0, 0.01, "CONTROL: the bed is muted before the fade")

	var peak: float = await _peak_during_fade(1.2)
	assert_lte(peak, -80.0 + 0.01,
		"the muted bed rose to %.1f dB on its way out — a fade out must never fade UP" % peak)


func test_a_very_quiet_player_is_left_where_they_are() -> void:
	## Everything under ~3.2%% maps below -40, which is the whole band the old constant inverted.
	SoundManager.set_music_volume(0.02)
	var base: float = SoundManager._music_base_db
	assert_lt(base, -40.0, "CONTROL: 2%% maps to %.1f dB, below the old -40 target" % base)
	SoundManager.play_music(BED)
	await _frames()

	var peak: float = await _peak_during_fade(0.4)
	assert_lte(peak, base + 0.01,
		"the bed rose from %.1f to %.1f dB — quieter than -40 must stay quieter" % [base, peak])


func test_a_normal_player_still_gets_the_same_fade() -> void:
	## The fix must not flatten the fade anyone already hears: from a normal level the target is the
	## -40 it has always been, the tween is still what moves it, and the callback still stops.
	SoundManager.set_music_volume(1.0)
	var base: float = SoundManager._music_base_db
	assert_gt(base, -40.0, "CONTROL: a normal level (%.1f dB) sits above the fade target" % base)
	SoundManager.play_music(BED)
	await _frames()

	SoundManager.fade_out_music(1.0)
	## ⛔ FALLING IS NOT FADING, and "still below where it started" is also true of a fade that never
	## moves — which is exactly what a target of the player's own level would produce. Require real
	## travel at the midpoint AND that the bed is still sounding, so a callback firing at t=0
	## (parallel mode without the chain) cannot pass this as a fade.
	await _wait_ms(500)
	assert_true(SoundManager._music_player.playing,
		"halfway through a 1.0 s fade the bed must still be playing — it stopped instead of fading")
	assert_lte(SoundManager._music_player.volume_db, base - 5.0,
		"halfway through, the bed is at %.1f dB against a base of %.1f — it is not fading" % [SoundManager._music_player.volume_db, base])

	await _wait_ms(900)
	assert_false(SoundManager._music_player.playing, "the fade still ends by stopping the player")
	assert_false(SoundManager._music_playing, "and still clears _music_playing")
	assert_eq(SoundManager._current_music, "", "and still clears _current_music")


## Put a bed on the B player: a track change moves the outgoing one there for CROSSFADE_DURATION.
func _start_a_crossfade() -> void:
	SoundManager.play_music(BED)
	await _frames(6)
	SoundManager.play_music(NEXT)
	await _frames(2)


func test_the_outgoing_bed_does_not_survive_the_fade() -> void:
	SoundManager.set_music_volume(1.0)
	await _start_a_crossfade()
	assert_true(SoundManager._music_player_b.playing,
		"CONTROL: the outgoing bed is on the B player — without it this arm has no subject")

	SoundManager.fade_out_music(0.3)
	await _wait_ms(1200)
	assert_false(SoundManager._music_player_b.playing,
		"the outgoing bed is still playing at %.1f dB after the music faded out — killing the crossfade also killed the callback that stopped it" % SoundManager._music_player_b.volume_db)
	assert_false(SoundManager._music_player.playing, "CONTROL: and the main player stopped too")


func test_the_outgoing_bed_does_not_rise_on_its_way_out_either() -> void:
	## B gets the same minf as A, so the orphan fix cannot reintroduce the swell on the other player.
	SoundManager.set_music_volume(0.0)
	await _start_a_crossfade()
	assert_true(SoundManager._music_player_b.playing, "CONTROL: the outgoing bed is on the B player")
	assert_almost_eq(SoundManager._music_player_b.volume_db, -80.0, 0.01, "CONTROL: it is muted, like everything else")

	SoundManager.fade_out_music(0.6)
	var peak: float = -1000.0
	var deadline: int = Time.get_ticks_msec() + 700
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		peak = maxf(peak, SoundManager._music_player_b.volume_db)
	assert_lte(peak, -80.0 + 0.01,
		"the outgoing bed rose to %.1f dB while fading out of a muted mix" % peak)


func test_the_outgoing_bed_fades_rather_than_being_cut() -> void:
	## Stopping B in the callback alone would fix the orphan and leave a hard cut: the outgoing bed
	## holding its level for the whole fade and vanishing at the end. It must travel like A does.
	SoundManager.set_music_volume(1.0)
	await _start_a_crossfade()
	var base: float = SoundManager._music_player_b.volume_db
	assert_gt(base, -40.0, "CONTROL: the outgoing bed is at %.1f dB, above the fade target" % base)

	SoundManager.fade_out_music(1.0)
	await _wait_ms(500)
	assert_true(SoundManager._music_player_b.playing, "CONTROL: it is still sounding at the midpoint")
	assert_lte(SoundManager._music_player_b.volume_db, base - 5.0,
		"halfway through, the outgoing bed is still at %.1f dB against %.1f — it is being cut, not faded" % [SoundManager._music_player_b.volume_db, base])


func test_the_members_this_file_reaches_still_exist() -> void:
	## ⛔ WITHOUT THIS ARM A RENAME IS A CLEAN EXIT. Measured 2026-09-16: rename `_music_player_b`
	## — the subject of the orphan half of this fix — and the three arms defending it abort before
	## their first assert, so GUT scores them RISKY rather than FAILED:
	##
	##     Passing 26 -> 23 · Risky 0 -> 3 · Asserts 66 -> 51 · Failing 0 · EC 0
	##
	## 🔑 EC=0 IS THE PART THAT MATTERS. "Capture the exit code before you shape the output" is this
	## project's gate discipline and it does not catch this — the run succeeds while the guard has
	## stopped guarding. Only the Risky column and the assert collapse show it, and a gate that
	## reads `Failing N` ships it. (@cowir-autogrind's silent-pass sweep, @cowir-sfx's abort ladder:
	## this is the rung that is VISIBLE in Risky and still exits zero.)
	##
	## `get()` returns null for an absent property instead of raising, so a rename fails HERE, by
	## name, before the arms whose subject it is go quiet.
	for member in ["_music_player", "_music_player_b", "_crossfade_tween", "_music_base_db"]:
		assert_true(SoundManager.get(member) != null or member == "_crossfade_tween",
			"SoundManager has no %s — the arms in this file reach it directly and would go Risky rather than red, on a run that exits 0" % member)
