extends GutTest

const SfxState := preload("res://test/unit/helpers/sfx_state.gd")

## _try_play_sfx_from_manifest detunes EVERY cue by +/-5% — authored for short repeated impacts,
## where it stops the ear fatiguing on an identical sample. play_voice inherited it when party
## lines moved onto their own player (2026-09-11) and nothing in that move said no: recorded human
## speech is the one population the trick is wrong for, at up to 0.84 of a semitone, redrawn per
## line, so one character's voice wanders pitch from line to line.
##
## The second half is a contract, not a taste call: play_voice RETURNS the clip length and
## BattleSpeechBubble sizes the bubble from it, but a stream of natural length L at pitch p is
## audible for L/p seconds. At p=0.95 the 10.90s line runs 11.47s under an 11.20s bubble.

const VOICE_KEY := "voice_mage_low_hp"   # the longest line on disk, 10.90s
const JITTERED_KEY := "attack_hit"       # a short repeated impact: the trick's real population
const DRAWS := 40


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _c(sm: Node, n: String) -> float:
	return float(sm.get_script().get_script_constant_map()[n])


func before_each() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_cooldowns.clear()


func after_each() -> void:
	SfxState.release_streams()


func test_a_spoken_line_plays_at_the_pitch_it_was_recorded_at() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has(VOICE_KEY), "CONTROL: %s must be in the manifest" % VOICE_KEY)
	var worst: float = 0.0
	for i in DRAWS:
		sm._sfx_cooldowns.clear()
		assert_gt(sm.play_voice(VOICE_KEY), 0.0, "CONTROL: %s must resolve, or nothing was pitched" % VOICE_KEY)
		worst = maxf(worst, absf(sm._voice_player.pitch_scale - 1.0))
	## Cents, because that is the unit the wander is audible in: 1200*log2(1.05) = 84.5.
	assert_eq(worst, 0.0,
		"a party voice line was detuned by up to %.1f cents across %d plays — the same character's voice changes pitch line to line" % [
			1200.0 * log(1.0 + worst) / log(2.0), DRAWS])


func test_the_length_the_bubble_is_told_is_the_length_it_will_hear() -> void:
	## BattleSpeechBubble._play_voice sets _hold_time = clip_len + VOICE_TAIL_S off this return.
	var sm: Node = _sm()
	if sm == null:
		return
	sm._sfx_cooldowns.clear()
	var reported: float = sm.play_voice(VOICE_KEY)
	assert_gt(reported, 0.0, "CONTROL: %s must resolve, or there is no length to check" % VOICE_KEY)
	var stream: AudioStream = sm._voice_player.stream
	assert_not_null(stream, "CONTROL: the voice player must be holding the clip")
	if stream == null:
		return
	## Two independently-sourced facts: the number the caller was handed, and the rate the player
	## was actually set to. Not a delta against something this code computed the same way.
	var audible: float = stream.get_length() / sm._voice_player.pitch_scale
	assert_almost_eq(reported, audible, 0.01,
		"play_voice reported %.2fs for a line that is audible for %.2fs at pitch %.4f — the bubble is sized %.2fs wrong" % [
			reported, audible, sm._voice_player.pitch_scale, audible - reported])


func test_a_short_repeated_cue_still_gets_its_variation() -> void:
	## Anti-overcorrection: deleting the jitter outright would pass the two arms above and take the
	## ear-fatigue guard with it on every sword swing in the game.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has(JITTERED_KEY), "CONTROL: %s must be in the manifest" % JITTERED_KEY)
	var seen: Dictionary = {}
	var band: float = _c(sm, "SFX_PITCH_JITTER")
	for i in DRAWS:
		sm._sfx_cooldowns.clear()
		sm.reset_hit_chain()
		sm.play_battle(JITTERED_KEY)
		seen[snappedf(sm._battle_player.pitch_scale, 0.0001)] = true
		assert_between(sm._battle_player.pitch_scale, 1.0 - band, 1.0 + band,
			"a battle cue was pitched to %.4f, outside the authored +/-%.2f band" % [sm._battle_player.pitch_scale, band])
	assert_gt(seen.size(), 1,
		"%d plays of %s all landed on one pitch — the anti-fatigue variation is gone from the cues it was written for" % [DRAWS, JITTERED_KEY])


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## ⚠️ A SNAPSHOT of this file's own sm. reaches, not a live derivation.
	for m in ["play_voice", "play_battle", "reset_hit_chain"]:
		assert_true(sm.has_method(m), "SoundManager has no method %s — this file CALLS it" % m)
	for n in ["_voice_player", "_battle_player", "_sfx_cooldowns", "_sfx_manifest"]:
		assert_true(sm.get(n) != null, "SoundManager has no %s — this file reaches for it directly" % n)
	assert_true((sm.get_script().get_script_constant_map() as Dictionary).has("SFX_PITCH_JITTER"),
		"SFX_PITCH_JITTER is gone — this file derives the authored band from it")
