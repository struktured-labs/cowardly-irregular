extends GutTest

## The danger system raises the music +3 dB and the pitch to 1.15 when the party is critical.
## `set_music_volume` latches the new base and writes it straight onto the player — flattening that
## boost while leaving the PITCH elevated, so the cue ends up half-applied.
##
## ⛔ AND NOTHING PUTS IT BACK. set_danger_intensity has a 0.05 deadband, so a party that STAYS
## critical never re-enters the setter and the envelope is not rewritten until the band moves.
## The boost is gone for the rest of the danger period.
##
## 🔑 THE TRIGGER IS THE CUE ITSELF, which is what makes this more than arithmetic: danger is
## AUDIBLY LOUDER, so "the music got loud, turn it down" is exactly when a player reaches for the
## slider — and reaching for it is what silently removes the loudness they were responding to.
##
## Third site of a root cause this file already documents twice. `reset_danger`'s own comment:
## "CLEAN IS NOT THE BASELINE WHEN THE GRIND IS CORRUPTED ... the clean slate above erased a
## settled detune and nothing put it back until corruption moved again." Same clean slate, same
## nothing-puts-it-back, a different writer.
##
## ⚠️ CORRUPTION IS DELIBERATELY NOT THE SUBJECT HERE. Its volume term is a per-call
## `randf_range` flicker above 0.6 and its pitch survives untouched, so erasing one sample of it is
## not audible. The arms below pin that pitch survival so the repair cannot become "reset
## everything", and the both-active ordering follows `reset_danger`'s existing precedence rather
## than inventing a new one.

const CEIL := -10.0


func before_each() -> void:
	SoundManager.reset_danger()
	SoundManager.reset_corruption()
	SoundManager.set_music_volume(1.0)


func after_each() -> void:
	SoundManager.reset_danger()
	SoundManager.reset_corruption()
	SoundManager.set_music_volume(1.0)
	SoundManager.stop_music()


func test_control_the_slider_moves_the_base_at_all() -> void:
	## Without this every arm below could pass on a setter that does nothing.
	assert_not_null(SoundManager._music_player, "CONTROL: a music player must exist")
	SoundManager.set_music_volume(1.0)
	var at_full: float = SoundManager._music_base_db
	SoundManager.set_music_volume(0.5)
	assert_almost_eq(at_full, CEIL, 0.01, "CONTROL: slider 1.0 must sit at the ceiling")
	assert_lt(SoundManager._music_base_db, at_full - 3.0,
		"CONTROL: slider 0.5 must be meaningfully quieter than 1.0 (%.2f vs %.2f)" % [SoundManager._music_base_db, at_full])


func test_the_slider_keeps_the_danger_boost() -> void:
	SoundManager._apply_danger_intensity(1.0)
	var boosted: float = SoundManager._music_player.volume_db
	assert_almost_eq(boosted, SoundManager._music_base_db + 3.0, 0.01,
		"CONTROL: danger at full must sit +3 dB over the base before the slider moves")

	SoundManager.set_music_volume(0.5)
	var base_now: float = SoundManager._music_base_db
	assert_almost_eq(SoundManager._music_player.volume_db, base_now + 3.0, 0.01,
		"the slider flattened the danger boost: player is at %.2f, base is %.2f, so the +3 dB critical-HP cue is gone and the 0.05 deadband means nothing re-applies it" % [SoundManager._music_player.volume_db, base_now])


func test_control_the_pitch_proves_danger_was_still_active() -> void:
	## Without this the arm above could pass because danger had ENDED, which is a different
	## and correct-looking state — the boost would be absent for a legitimate reason.
	SoundManager._apply_danger_intensity(1.0)
	SoundManager.set_music_volume(0.5)
	assert_almost_eq(SoundManager._music_player.pitch_scale, 1.15, 0.01,
		"CONTROL: the pitch must still be elevated, or the volume arm is measuring a cleared envelope")
	assert_gt(SoundManager._danger_intensity, 0.9, "CONTROL: and the intensity field still says danger")


func test_no_danger_means_no_boost() -> void:
	## The other direction, so the repair cannot be "always add 3 dB".
	SoundManager.set_music_volume(0.5)
	assert_almost_eq(SoundManager._music_player.volume_db, SoundManager._music_base_db, 0.01,
		"with no danger the player must sit exactly at the base, not above it")


func test_corruption_pitch_survives_a_slider_move() -> void:
	## Pinned as the direction that already works. The slider writes volume only, so a settled
	## detune must come through untouched — a repair that reset the whole envelope would red here.
	SoundManager._apply_corruption_intensity(0.8)
	var detuned: float = SoundManager._music_player.pitch_scale
	assert_lt(detuned, 0.995,
		"CONTROL: corruption at 0.8 must actually detune (%.4f) or this arm is vacuous" % detuned)
	SoundManager.set_music_volume(0.5)
	assert_almost_eq(SoundManager._music_player.pitch_scale, detuned, 0.0001,
		"a volume change must not touch the corruption detune")
