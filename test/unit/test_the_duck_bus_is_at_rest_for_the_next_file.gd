extends GutTest

## ⛔ THE THIRD FIXTURE SURFACE, AND `sound_state.restore()` DOES NOT CLEAR IT. The corruption detector
## asks about the rendered detune and the night detector about `_current_ambient_key`; neither can see
## the MusicDuck bus, where TWO independent Amplify effects live — slot 0 for dialogue, slot 1 for the
## kill punctuation.
##
## 🔑 MEASURED 2026-09-18: duck for dialogue, call SoundState.restore(), read the bus back — `-6.00 dB`
## still there, `_duck_active` still true, the holder still in the set. A kill duck caught mid-taper
## survives as a LIVE TWEEN, still writing.
##
## ⛔ THE CONSEQUENCE IS A QUIET WRONG NUMBER, NOT A FAILURE. Every music player routes
## `_music_player -> MusicNight -> MusicDuck -> Master`, so a later file measuring a level reads it up
## to 6 dB low and its own assertion is what looks broken.

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const KILL_SLOT := 1


func _amp(slot: int) -> float:
	var idx: int = AudioServer.get_bus_index(SoundManager.MUSIC_DUCK_BUS)
	if idx == -1 or AudioServer.get_bus_effect_count(idx) <= slot:
		return 999.0
	var a = AudioServer.get_bus_effect(idx, slot)
	return a.volume_db if a else 999.0


func test_the_duck_bus_is_at_rest_for_the_next_file() -> void:
	## ⛔ FLOOR FIRST: a missing bus or a missing slot returns the sentinel, and without this the two
	## level asserts below would be about a surface that is not there.
	var idx: int = AudioServer.get_bus_index(SoundManager.MUSIC_DUCK_BUS)
	assert_gt(idx, -1, "FLOOR: the %s bus must exist, or this arm reports rest about nothing" % SoundManager.MUSIC_DUCK_BUS)
	assert_gt(AudioServer.get_bus_effect_count(idx), KILL_SLOT,
		"FLOOR: the duck bus must carry both Amplify slots (dialogue 0, kill %d)" % KILL_SLOT)

	assert_almost_eq(_amp(0), 0.0, 0.01,
		"a fixture left the DIALOGUE duck at %.2f dB — every later file hears its music through that attenuation and its own level assertion is what looks broken" % _amp(0))
	assert_almost_eq(_amp(KILL_SLOT), 0.0, 0.01,
		"a fixture left the KILL duck at %.2f dB, which means its taper was still running when the file ended" % _amp(KILL_SLOT))
	assert_false(bool(SoundManager.is_music_ducked_for_dialogue()),
		"the duck LATCH is still set even if the bus happens to read 0 — the next duck_music_for_dialogue(true) is then a no-op and that file's duck never arrives")
	assert_eq(SoundManager._duck_holders.size(), 0,
		"a holder is still in the duck set (%d) — a released dialogue from a previous file keeps this one ducked" % SoundManager._duck_holders.size())


## ⛔ THE HELPER'S CONTRACT, DRIVEN DIRECTLY — because the hygiene arm above can only see the ONE
## clause our fixtures happen to exercise. Measured: mutating the helper's amplify-zeroing reds the
## arm above; removing the latch clear, the holder clear or the tween kills leaves it GREEN, since
## every duck-driving file in the corpus RELEASES (which flips the latch synchronously) and only the
## taper is asynchronous. Three clauses with no witness is not three covered clauses.
##
## 🔑 The leak this arm builds is the one a real abort produces: a duck ON, mid-taper toward -6, with
## nothing having released it. That is the state `_exit_tree` exists to prevent and the one a helper
## has to be able to clear.
func test_the_barrier_brings_a_live_duck_to_rest() -> void:
	var holder := Node.new()
	add_child_autofree(holder)
	SoundManager.duck_music_for_dialogue(true, holder)
	## ⛔ WAIT FOR THE TWEEN, NOT THE CLOCK. This was a fixed 0.35 s wall-clock sleep for a 0.25 s
	## tween: it passed for this file alone and read -3.60 dB — 60% of the way — when the file ran
	## inside a ten-file batch. ⚠️ I DID NOT ESTABLISH THE MECHANISM: a leaked `Engine.time_scale`, a
	## leaked `get_tree().paused` and a double-run of the script were each measured and each ruled out
	## (1.0, false, and Scripts==10). The wait was the wrong instrument regardless — a wall-clock sleep
	## cannot be the right way to observe an engine-time tween — so it is gone rather than retuned.
	## Bounded, because a hung test is killed rather than failed.
	var spins: int = 0
	while SoundManager._duck_tween != null and SoundManager._duck_tween.is_valid() \
			and SoundManager._duck_tween.is_running() and spins < 300:
		await get_tree().process_frame
		spins += 1
	assert_lt(spins, 300, "CONTROL: the duck taper was still running after %d frames" % spins)
	assert_almost_eq(_amp(0), SoundManager.DUCK_TARGET_DB, 0.01,
		"CONTROL: the duck must actually have engaged (%.2f dB), or this arm restores nothing" % _amp(0))
	assert_true(bool(SoundManager.is_music_ducked_for_dialogue()), "CONTROL: and the latch must be set")
	assert_eq(SoundManager._duck_holders.size(), 1, "CONTROL: and the holder must be in the set")

	SoundState.restore()
	await get_tree().process_frame

	assert_almost_eq(_amp(0), 0.0, 0.01,
		"the barrier left the dialogue duck at %.2f dB — a file that aborts mid-line hands every later file that attenuation" % _amp(0))
	assert_false(bool(SoundManager.is_music_ducked_for_dialogue()),
		"the barrier left the duck LATCH set, so the next file's own duck_music_for_dialogue(true) is a no-op")
	assert_eq(SoundManager._duck_holders.size(), 0,
		"the barrier left %d holder(s) in the set, so the next file stays ducked until that object is freed" % SoundManager._duck_holders.size())


## ⛔ THE LAST CLAUSE, AND IT NEEDED A TAPER STILL IN FLIGHT TO BE VISIBLE AT ALL. Zeroing the amplify
## is not enough on its own: a LIVE tween writes over the zero on its next frame. Every other arm
## waits for the taper to settle first, so removing the tween kills left all of them green — the
## clause had no witness until this arm caught the duck mid-move.
func test_the_barrier_kills_a_taper_still_in_flight() -> void:
	var holder := Node.new()
	add_child_autofree(holder)
	SoundManager.duck_music_for_dialogue(true, holder)
	## Deliberately SHORTER than DUCK_TAPER_TIME — the tween must still be running.
	await get_tree().create_timer(0.08, true, false, true).timeout
	assert_true(SoundManager._duck_tween != null and SoundManager._duck_tween.is_valid() and SoundManager._duck_tween.is_running(),
		"CONTROL: the taper must still be in flight, or this arm is the settled case the others already cover")
	var mid: float = _amp(0)
	assert_lt(mid, -0.05, "CONTROL: it must have started moving (%.3f dB)" % mid)
	assert_gt(mid, SoundManager.DUCK_TARGET_DB + 0.05, "CONTROL: and not yet arrived (%.3f dB)" % mid)

	SoundState.restore()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(_amp(0), 0.0, 0.01,
		"the barrier zeroed the bus and left the taper ALIVE — it wrote %.2f dB back over the zero on the next frame, so the reset lasted exactly one frame" % _amp(0))
