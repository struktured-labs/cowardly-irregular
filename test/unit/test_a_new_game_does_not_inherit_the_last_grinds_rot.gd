extends GutTest

## ⛔ `reset_corruption()` ZEROES WHAT IS RENDERED AND NOT WHAT FEEDS IT, SO NEW GAME PLAYS THE LAST
## GRIND'S DETUNE. Two source meters exist — `_grind_corruption` (autogrind's meta-corruption) and
## `_save_corruption` (GameState.corruption_level) — and `_apply_corruption_max` renders their max.
## reset_corruption clears `_corruption_intensity` alone, so the grind meter survives as a latch with
## nothing on screen holding it.
##
## 🔑 NEW GAME IS THE TRIGGER, WHICH IS WHY NOBODY WOULD LOOK THERE. `GameState.reset_game_state`
## sets `corruption_level = 0.0` and EMITS `corruption_changed(0.0)`; SoundManager is connected to it,
## so the emit that says "this save is clean" runs `max(stale_grind, 0.0)` and starts a 1.5 s tween
## UP to the old value. A player who grinds to collapse, quits to the title and starts a fresh game
## hears the prologue bed detuned by the run they abandoned.
##
## ⛔ AND CLEARING BOTH METERS WOULD BE THE OTHER BUG. `reset_danger`'s own comment already records
## it: "the clean slate above erased a settled detune and nothing put it back until corruption moved
## again". A rotting save is meant to stay audible outside the grind loop, so the repair drops the
## GRIND meter and re-derives from the save one — it does not force silence.

const ROT := 0.8


func before_each() -> void:
	SoundManager.reset_danger()
	SoundManager._grind_corruption = 0.0
	SoundManager._save_corruption = 0.0
	SoundManager.reset_corruption()


func after_each() -> void:
	SoundManager.reset_danger()
	SoundManager._grind_corruption = 0.0
	SoundManager._save_corruption = 0.0
	SoundManager.reset_corruption()
	SoundManager.stop_music()


## Every symbol this file reaches on SoundManager, in one frame of its own, so a rename reds HERE
## with the name in the message rather than aborting an arm that has already asserted something.
func test_floor_the_corruption_surface_still_exists() -> void:
	for name in ["reset_corruption", "set_corruption_intensity", "set_save_corruption", "reset_danger", "set_danger_intensity"]:
		assert_true(SoundManager.has_method(name), "SoundManager must still expose %s()" % name)
	for field in ["_grind_corruption", "_save_corruption", "_corruption_intensity", "_corruption_target", "_danger_intensity"]:
		assert_true(field in SoundManager, "SoundManager must still carry %s" % field)


func test_a_reset_drops_the_grind_meter_not_only_its_render() -> void:
	SoundManager.set_corruption_intensity(ROT)
	assert_almost_eq(SoundManager._grind_corruption, ROT, 0.0001,
		"CONTROL: the grind meter must be loaded, or there is no latch to clear")
	SoundManager.reset_corruption()
	assert_almost_eq(SoundManager._grind_corruption, 0.0, 0.0001,
		"reset_corruption left the grind meter at %.3f — it cleared only what was rendered, so the next corruption event anywhere re-raises it" % SoundManager._grind_corruption)


func test_a_new_game_does_not_inherit_the_last_grinds_rot() -> void:
	## The shipped sequence: grind to ROT, the session ends (GameLoop calls reset_corruption before
	## play_area_music), the player starts a NEW GAME and GameState emits its clean level.
	SoundManager.set_corruption_intensity(ROT)
	SoundManager.reset_corruption()
	SoundManager.set_save_corruption(0.0)
	assert_almost_eq(SoundManager._corruption_target, 0.0, 0.0001,
		"a fresh game is aiming at %.3f corruption, inherited from a grind that already ended and was reset" % SoundManager._corruption_target)


func test_a_rotting_save_is_still_audible_after_a_grind_ends() -> void:
	## ⛔ THE OTHER DIRECTION, because "clear both meters" passes the arm above and reintroduces the
	## defect reset_danger already carries a comment about. A corrupt save must survive the reset.
	SoundManager.set_save_corruption(0.5)
	SoundManager.set_corruption_intensity(ROT)
	SoundManager.reset_corruption()
	assert_almost_eq(SoundManager._save_corruption, 0.5, 0.0001,
		"CONTROL: the save meter is not the grind meter and must be untouched (%.3f)" % SoundManager._save_corruption)
	assert_almost_eq(SoundManager._corruption_intensity, 0.5, 0.0001,
		"the save is rotting at 0.5 and the music renders %.3f — resetting the GRIND silenced the SAVE, which is the erased-settled-detune bug one meter over" % SoundManager._corruption_intensity)


func test_a_reset_does_not_flatten_a_live_danger_cue() -> void:
	## reset_corruption wrote pitch 1.0 and base dB ABSOLUTELY, so it erased danger exactly as the
	## two absolute writers did before the single renderer landed. Same family, third site.
	SoundManager._apply_danger_intensity(1.0)
	var lift: float = SoundManager._music_player.pitch_scale - 1.0
	assert_gt(lift, 0.01, "CONTROL: danger must lift the pitch (%.4f) or there is nothing to flatten" % lift)
	SoundManager.reset_corruption()
	assert_almost_eq(SoundManager._music_player.pitch_scale, 1.0 + lift, 0.0001,
		"clearing corruption dropped the critical-HP detune from %.4f to %.4f — danger is still at %.2f" % [1.0 + lift, SoundManager._music_player.pitch_scale, SoundManager._danger_intensity])
