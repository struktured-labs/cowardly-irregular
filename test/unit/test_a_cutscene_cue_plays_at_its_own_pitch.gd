extends GutTest

## His .808 log: boss_intro_stinger at pitch 1.04, the spotlight victory fanfares anywhere from 0.95 to 1.04. The ±5% jitter
## exists so a REPEATED battle hit does not tire the ear; a scene's cue plays once and is often music, so it plays as made.

const CUES: Array[String] = ["boss_intro_stinger", "spotlight_cleric_victory", "sword_draw_heavy"]
const PLAYS := 12


func before_each() -> void:
	SoundManager.stop_cutscene_sfx()


func after_each() -> void:
	SoundManager.stop_cutscene_sfx()
	SoundManager._ui_player.stop()


func _pitches(cue: String, on_cutscene_voice: bool) -> Array:
	var out: Array = []
	var player: AudioStreamPlayer = SoundManager._cutscene_player if on_cutscene_voice else SoundManager._ui_player
	for i in PLAYS:
		SoundManager._sfx_cooldowns.erase(cue)  # the per-key cooldown would swallow every play after the first
		player.stop()
		if on_cutscene_voice:
			SoundManager.play_cutscene_sfx(cue)
		else:
			SoundManager.play_ui(cue)
		assert_true(player.playing, "PREMISE: %s started (play %d)" % [cue, i])
		out.append(player.pitch_scale)
	return out


func test_a_scene_cue_is_never_detuned() -> void:
	assert_not_null(SoundManager._cutscene_player, "PREMISE: the cutscene voice exists")
	for cue in CUES:
		var jittered: Array = _pitches(cue, false)
		assert_true(jittered.any(func(p): return not is_equal_approx(p, 1.0)), "CONTROL: the same cue on the UI voice IS jittered: %s" % str(jittered))
		var heard: Array = _pitches(cue, true)
		assert_true(heard.all(func(p): return is_equal_approx(p, 1.0)), "%s plays at unity on the cutscene voice every time: %s" % [cue, str(heard)])


## A jittered play before it must not leave its pitch on the shared player for the scene's cue.
func test_a_scene_cue_does_not_inherit_the_last_pitch() -> void:
	var player: AudioStreamPlayer = SoundManager._cutscene_player
	player.pitch_scale = 1.37
	SoundManager._sfx_cooldowns.erase("boss_intro_stinger")
	SoundManager.play_cutscene_sfx("boss_intro_stinger")
	assert_true(player.playing, "PREMISE: the cue started")
	assert_almost_eq(player.pitch_scale, 1.0, 0.0001, "the cue plays as it was made, whatever the player held before")
