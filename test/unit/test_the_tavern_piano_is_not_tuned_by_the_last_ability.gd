extends GutTest

## The tavern piano is a MELODY — its pitch is content, not flavour. It plays on `_ability_player`,
## which is shared, and `_try_play_sfx_from_manifest` writes a jittered `pitch_scale` on every file
## cue it plays there (`pitch_jitter` defaults true, SFX_PITCH_JITTER 0.05).
##
## `_play_sound` resets `pitch_scale = 1.0` and says why. `play_piano_melody` was a THIRD writer of
## the same player and reset nothing, so the piano inherited whatever detune the last ability left:
## up to 5% — roughly 85 cents, nearly a semitone — held across scenes, because the autoload
## outlives the battle. Fight, walk into the tavern, play the piano, hear it out of tune.

const ABILITY_KEY := "ability_fire"


func after_each() -> void:
	if SoundManager != null and SoundManager._ability_player != null:
		SoundManager._ability_player.pitch_scale = 1.0
		SoundManager._ability_player.stop()


func test_the_piano_plays_at_its_own_pitch_whatever_ran_before() -> void:
	if SoundManager == null or SoundManager._ability_player == null:
		assert_true(false, "SoundManager/_ability_player unavailable — this arm would prove nothing")
		return
	## Planted by hand, not by the jitter: the defect is the ABSENCE of a reset, and a deterministic
	## stale value states it without depending on a random draw landing off 1.0.
	SoundManager._ability_player.pitch_scale = 1.0 + SoundManager.SFX_PITCH_JITTER
	assert_ne(SoundManager._ability_player.pitch_scale, 1.0,
		"SCOPE control: the plant did not take, so the assert below cannot fail")
	SoundManager.play_piano_melody()
	if SoundManager.mixer_is_wedged():
		assert_false(SoundManager.mixer_is_wedged(),
			"mixer wedged before the piano could commit its PCM — playback never advanced, so this arm did not reach the pitch reset. The WAV commit was refused so AudioServer.lock cannot hang the suite.")
		return
	assert_eq(SoundManager._ability_player.pitch_scale, 1.0,
		"the piano inherited the pitch the previous ability cue left on the shared player — it is a melody, so a stale pitch_scale detunes the tune itself, not just its colour")


## ⛔ THE ARM ABOVE PLANTS ITS OWN STALE VALUE, SO IT CANNOT SAY THE STALENESS IS REACHABLE. This
## one drives the real writer: a manifest ability cue must actually leave a non-1.0 pitch behind,
## or the defect above is a hypothetical about a state nothing produces.
func test_an_ability_file_cue_really_does_leave_a_detune_behind() -> void:
	if SoundManager == null or SoundManager._ability_player == null:
		assert_true(false, "SoundManager/_ability_player unavailable")
		return
	var played: int = 0
	var detuned: int = 0
	for i in 24:
		SoundManager._ability_player.pitch_scale = 1.0
		SoundManager._sfx_cooldowns.erase(ABILITY_KEY)
		if not SoundManager._try_play_sfx_from_manifest(
				SoundManager._ability_player, ABILITY_KEY, SoundManager.SFX_ABILITY_BASE_DB):
			continue
		played += 1
		var p: float = SoundManager._ability_player.pitch_scale
		assert_between(p, 1.0 - SoundManager.SFX_PITCH_JITTER, 1.0 + SoundManager.SFX_PITCH_JITTER,
			"a file cue wrote a pitch outside the jitter band (%f)" % p)
		if p != 1.0:
			detuned += 1
	assert_gt(played, 0,
		"SCOPE control: %s never played from the sfx manifest, so this arm drove nothing" % ABILITY_KEY)
	assert_gt(detuned, 0,
		"24 ability cues all left pitch_scale at exactly 1.0 — either the jitter stopped being applied or this arm stopped reaching the writer, and the guard above is then about a state nothing produces")
