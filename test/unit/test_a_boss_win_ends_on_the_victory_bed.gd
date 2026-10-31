extends GutTest

## Regression, struktured on .747 (via cowir-main 20447): "victory music didn't kick in or sustain after
## taking down rat king". His log: stinger_boss_defeated played with resume={track: boss_rat_king, 86.18},
## then boss_rat_king loop=true came back under the rewards. A boss win played the stinger INSTEAD of the
## victory bed, so the stinger's resume target was the fight it had interrupted, and no victory bed ever ran.
## BattleScene.play_victory_music now starts the bed first, so the stinger resumes to it.

const SCENE := preload("res://src/battle/BattleScene.gd")
const BOSS_BED := "boss_rat_king"


func before_each() -> void:
	SoundManager.stop_music()


func after_each() -> void:
	SoundManager.stop_music()


func _finish_the_stinger() -> void:
	## The real one-shot the stinger armed on its own finished signal; the Dummy mix never reaches the end.
	SoundManager._music_player.finished.emit()


func test_the_boss_stinger_resumes_to_the_victory_bed() -> void:
	SoundManager.play_music(BOSS_BED)
	assert_eq(SoundManager._current_music, BOSS_BED, "CONTROL: the boss bed is the fight's music before the win")
	SCENE.play_victory_music(true)
	assert_eq(SoundManager._current_music, "stinger_boss_defeated", "a boss win must still play its stinger")
	assert_eq(str(SoundManager._stinger_resume_state.get("track", "")), "victory",
		"the stinger will resume to '%s' — the fight it interrupted comes back under the rewards" % SoundManager._stinger_resume_state.get("track", ""))
	_finish_the_stinger()
	assert_eq(SoundManager._current_music, "victory", "after the stinger the music is '%s', not the victory bed" % SoundManager._current_music)
	assert_true(SoundManager.playing_track_stem().begins_with("victory"),
		"the bed heard after a boss win is '%s' — it must be the world's victory bed, never the boss track" % SoundManager.playing_track_stem())


func test_the_victory_bed_sustains_rather_than_ending() -> void:
	SoundManager.play_music(BOSS_BED)
	SCENE.play_victory_music(true)
	_finish_the_stinger()
	var s: AudioStream = SoundManager._music_player.stream
	assert_not_null(s, "CONTROL: a victory bed stream is loaded")
	assert_true(bool(s.get("loop")), "the victory bed after a boss win does not loop, so it ends under the rewards screen")


func test_an_ordinary_win_plays_the_bed_with_no_stinger() -> void:
	## Control: the ordinary path is unchanged, and it is what the boss path now ends on.
	SoundManager.play_music("battle")
	SCENE.play_victory_music(false)
	assert_eq(SoundManager._current_music, "victory", "an ordinary win must play the victory bed directly")
	assert_true(SoundManager.playing_track_stem().begins_with("victory"), "CONTROL: the ordinary win's bed is a victory track")
