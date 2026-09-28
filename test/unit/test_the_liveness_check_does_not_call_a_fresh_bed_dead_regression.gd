extends GutTest

## Regression 2026-09-28: every battle after a one-round battle logged "game audio mixer is dead" when both beds entered at the same point.
## Both samples were play()'s seek on the calling thread; the mixer never ran between them. 16 of 16 battles in a real log fit that rule.

const ENTRY_A := "battle_imp"
const ENTRY_B := "battle_medieval"


func before_each() -> void:
	_reset()


func after_each() -> void:
	_reset()
	SoundManager.stop_music()


func _reset() -> void:
	SoundManager._liveness_pos_override = -1.0
	SoundManager._liveness_last_pos = -1.0
	SoundManager._liveness_playback_id = 0
	SoundManager._liveness_last_msec = 0


func _entry(track: String) -> float:
	return float((SoundManager._music_manifest[track] as Dictionary).get("loop_blend_seconds", 0.0))


## Past the time rule with no sample between, as between two battles, so only the playback identity can pass these arms.
func _wait_past_the_time_rule() -> void:
	var until := Time.get_ticks_msec() + SoundManager._LIVENESS_MIN_MSEC + 100
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _start(track: String) -> float:
	SoundManager.stop_music()
	SoundManager.play_music(track, true)
	assert_true(SoundManager._music_player.playing, "CONTROL: %s did not start, so any verdict is about nothing" % track)
	return SoundManager._music_player.get_playback_position()


func test_a_new_bed_at_the_same_entry_is_not_a_dead_mixer() -> void:
	assert_almost_eq(_entry(ENTRY_A), _entry(ENTRY_B), 0.0001, "CONTROL: both beds must share an entry, or this is not the logged case")
	var a := _start(ENTRY_A)
	SoundManager.audio_liveness_check()
	SoundManager.stop_music()
	await _wait_past_the_time_rule()
	var b := _start(ENTRY_B)
	assert_lt(absf(a - b), 0.001, "CONTROL: the two samples must read equal (%.5f vs %.5f), or the old check would not have fired" % [a, b])
	assert_false(SoundManager.audio_liveness_check(),
		"a new battle's bed at its %.1fs entry was called a dead mixer — both positions were play()'s seek, not the mix" % b)


func test_a_restart_of_the_same_bed_is_a_new_baseline() -> void:
	_start(ENTRY_A)
	SoundManager.audio_liveness_check()
	SoundManager.stop_music()
	await _wait_past_the_time_rule()
	_start(ENTRY_A)
	assert_false(SoundManager.audio_liveness_check(),
		"restarting the same bed at its entry was called a dead mixer — a new play() is a new baseline")


func test_two_quick_samples_of_one_playback_are_not_a_verdict() -> void:
	_start(ENTRY_A)
	SoundManager._liveness_pos_override = 4.0
	SoundManager.audio_liveness_check()
	assert_false(SoundManager.audio_liveness_check(),
		"two samples 0ms apart were judged — no driver has mixed in that time, so equal positions prove nothing")


func test_control_a_playback_that_really_sits_still_is_still_called_dead() -> void:
	_start(ENTRY_A)
	SoundManager._liveness_pos_override = 4.0
	SoundManager.audio_liveness_check()
	await _wait_past_the_time_rule()
	assert_true(SoundManager.audio_liveness_check(),
		"CONTROL: the same playback frozen across %dms+ was not called dead — the fix silenced the detector it exists for" % SoundManager._LIVENESS_MIN_MSEC)
