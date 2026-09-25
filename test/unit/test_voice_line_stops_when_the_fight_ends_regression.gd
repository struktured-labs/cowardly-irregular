extends GutTest

## Party barks play on SoundManager's voice player, which outlives the battle scene, so a line kept talking over the results and onto the map.

const TURN := "voice_fighter_turn_start"
const VICTORY := "voice_fighter_victory"
const SCENE := "res://src/battle/BattleScene.gd"
const BattleState := preload("res://test/unit/helpers/battle_state.gd")

var _guard: RefCounted = null
var _scale: float = 1.0
var _llm: bool = false


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()
	_scale = Engine.time_scale
	_llm = GameState.party_llm_dialogue_enabled
	GameState.party_llm_dialogue_enabled = false
	SoundManager._sfx_cooldowns.clear()
	BattleManager._party_line_cooldowns.clear()
	BattleManager._party_line_last_kind.clear()


func after_each() -> void:
	if SoundManager._voice_player != null and SoundManager._voice_player.playing:
		SoundManager._voice_player.stop()
	SoundManager._sfx_cooldowns.clear()
	Engine.time_scale = _scale
	GameState.party_llm_dialogue_enabled = _llm
	if _guard != null:
		_guard.restore()


func _silence_parties() -> void:
	var nobody: Array[Combatant] = []
	BattleManager.player_party = nobody
	BattleManager.enemy_party = nobody
	BattleManager.all_combatants = nobody


func test_a_line_in_progress_stops_when_the_fight_ends() -> void:
	var heard: float = SoundManager.play_voice(TURN)
	assert_gt(heard, 2.0, "CONTROL: the fighter turn line must resolve, or this test measures silence")
	assert_true(SoundManager._voice_player.playing, "CONTROL: the voice player must be running")
	_silence_parties()
	BattleManager.end_battle(false)
	assert_false(SoundManager._voice_player.playing,
		"the fighter was still talking after the fight ended, so that line plays over the result screen")


func test_the_fight_line_is_quiet_before_the_victory_bark_is_chosen() -> void:
	## Stopping after the victory dispatch would cut the victory bark in the same instant it starts.
	var heard: float = SoundManager.play_voice(TURN)
	assert_gt(heard, 2.0, "CONTROL: the in-fight line must be audible before the win")
	var hero := Combatant.new()
	add_child_autofree(hero)
	hero.combatant_name = "BarkStopHero"
	hero.job = {"id": "fighter"}
	hero.is_alive = true
	hero.max_hp = 100
	hero.current_hp = 100
	hero.job_level = 5
	var party: Array[Combatant] = [hero]
	var nobody: Array[Combatant] = []
	BattleManager.player_party = party
	BattleManager.enemy_party = nobody
	BattleManager.all_combatants = party
	BattleManager._ko_this_battle = nobody
	BattleManager._one_shot_achieved = false
	BattleManager._full_autobattle = false
	BattleManager._autobattle_player_turns = 0
	var playing_when_victory_spoke: Array = []
	var cb := func(_who, _line, _trig):
		playing_when_victory_spoke.append(SoundManager._voice_player.playing)
	BattleManager.party_combat_line.connect(cb)
	BattleManager.end_battle(true)
	if BattleManager.party_combat_line.is_connected(cb):
		BattleManager.party_combat_line.disconnect(cb)
	assert_eq(playing_when_victory_spoke.size(), 1,
		"CONTROL: the victory line must be chosen, or this never watched the handoff")
	assert_false(bool(playing_when_victory_spoke[0]),
		"the in-fight bark was still playing when the victory line was chosen, so the two overlap on the results")


func test_leaving_the_battle_scene_stops_a_line_still_playing() -> void:
	var heard: float = SoundManager.play_voice(VICTORY)
	assert_gt(heard, 0.0, "CONTROL: the victory clip must resolve")
	assert_true(SoundManager._voice_player.playing, "CONTROL: the victory line must be running")
	var scene = load(SCENE).new()
	scene._exit_tree()
	scene.free()
	assert_false(SoundManager._voice_player.playing,
		"the victory line kept playing after the battle scene was gone, so it follows you onto the map")


func test_a_stopped_player_can_start_the_next_line() -> void:
	SoundManager.play_voice(TURN)
	_silence_parties()
	BattleManager.end_battle(false)
	var again: float = SoundManager.play_voice(VICTORY)
	assert_gt(again, 0.0, "stopping the in-fight line must not leave the voice player unable to say the next one")
	assert_true(SoundManager._voice_player.playing, "the victory bark must be able to start after the fight line was cut")
