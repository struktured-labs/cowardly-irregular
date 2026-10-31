extends GutTest

## Regression, struktured on .747 (via cowir-main 20447): "victory music didn't kick in or sustain after
## taking down rat king". His log: stinger_boss_defeated played with resume={track: boss_rat_king, 86.18},
## then boss_rat_king loop=true came back under the rewards. A boss win played the stinger INSTEAD of the
## victory bed, so the stinger's resume target was the fight it had interrupted, and no victory bed ever ran.
## BattleScene.play_victory_music now starts the bed first, so the stinger resumes to it.
## RULED (struktured, via cowir-main 20448): "it should never go back to the battle music after a victory
## ditty" -- an INVARIANT over every battle bed and every stinger once the battle is won, not one boss arm.

const SCENE := preload("res://src/battle/BattleScene.gd")
const BOSS_BED := "boss_rat_king"


var _state_before: int = 0


func before_each() -> void:
	SoundManager.stop_music()
	_state_before = int(BattleManager.current_state)


func after_each() -> void:
	SoundManager.stop_music()
	BattleManager.current_state = _state_before


func _battle_beds() -> Array:
	## Derived from the manifest, so a new boss or danger bed is judged on arrival.
	var out: Array = []
	SoundManager._load_music_manifest()
	for k in SoundManager._music_manifest.keys():
		if SoundManager._is_battle_bed(str(k)) and not SoundManager._is_stinger_track(str(k)):
			out.append(str(k))
	return out


func _stingers() -> Array:
	var out: Array = []
	for k in SoundManager._music_manifest.keys():
		if SoundManager._is_stinger_track(str(k)):
			out.append(str(k))
	return out


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


func test_no_stinger_resumes_to_a_battle_bed_once_the_battle_is_won() -> void:
	var beds: Array = _battle_beds()
	var stingers: Array = _stingers()
	assert_gt(beds.size(), 10, "SCOPE control: only %d battle/boss/danger beds derived" % beds.size())
	assert_true(stingers.has("stinger_boss_defeated") and stingers.has("stinger_level_up"),
		"SCOPE control: the post-victory stingers are not in the derived set: %s" % str(stingers))
	var bad: Array = []
	var played: int = 0
	for bed in beds:
		for st in ["stinger_boss_defeated", "stinger_level_up"]:
			SoundManager.stop_music()
			BattleManager.current_state = BattleManager.BattleState.EXECUTION_PHASE
			SoundManager.play_music(bed)
			if SoundManager._current_music == bed:
				played += 1
			BattleManager.current_state = BattleManager.BattleState.VICTORY
			SoundManager.play_music(st)
			_finish_the_stinger()
			if SoundManager._is_battle_bed(SoundManager._current_music):
				bad.append("%s after %s -> %s" % [st, bed, SoundManager._current_music])
	## A bed that never started makes its pass vacuous; most must really be the fight's music first.
	assert_gt(played, beds.size(), "CONTROL: only %d of %d bed plays actually started, so the rest asserted nothing" % [played, beds.size() * 2])
	assert_eq(bad, [], "after a won battle these stingers handed back to battle music: %s" % str(bad))


func test_a_mid_battle_stinger_still_returns_to_the_fight() -> void:
	## Control: the rule starts at VICTORY. A Limit Break mid-fight must come back to the battle bed.
	BattleManager.current_state = BattleManager.BattleState.EXECUTION_PHASE
	SoundManager.play_music(BOSS_BED)
	SoundManager.play_music("stinger_level_up")
	_finish_the_stinger()
	assert_eq(SoundManager._current_music, BOSS_BED, "a mid-battle stinger no longer returns to the fight it interrupted")
