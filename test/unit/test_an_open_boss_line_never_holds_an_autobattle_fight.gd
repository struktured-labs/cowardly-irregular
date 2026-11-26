extends GutTest

## Main 28112: a boss's low_hp and defeat lines open their panel directly (no _hold_beat_dialogue) at turbo or speed >= 1.0.
## A real Rat King fight under autobattle, with no input, must still reach its end with that panel open.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const CAP_MS := 60000

var _guard = null
var _saved_constants: Dictionary = {}
var _saved_scale := 1.0
var _saved_persist := false


func before_each() -> void:
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	GameState.boss_intro_cutscene_for = ""
	_saved_constants = GameState.game_constants.duplicate(true)
	_saved_scale = Engine.time_scale
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	GameState.boss_intro_cutscene_for = ""
	GameState.game_constants = _saved_constants
	Engine.time_scale = _saved_scale
	AutobattleSystem._test_disable_persistence = _saved_persist
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Returns {ended, won, low_hp, defeat, low_hp_panel, defeat_panel, ms}.
func _fight(turbo: bool, speed_index: int) -> Dictionary:
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["cave_rat_king"]
	add_child_autofree(scene)
	await _frames(3)
	if scene._waiting_for_dialogue:
		scene._battle_dialogue.dialogue_finished.emit()
		await _frames(3)
	scene.turbo_mode = turbo
	if speed_index >= 0:
		scene._apply_battle_speed_index(speed_index)
	for member in scene.party_members:
		member.attack = 200
		member.max_hp = 9999
		member.current_hp = 9999
	for foe in BattleManager.enemy_party:
		if is_instance_valid(foe):
			foe.attack = 1
			foe.magic = 1
	var ids: Array = []
	for member in scene.party_members:
		var id: String = member.combatant_name.to_lower().replace(" ", "_")
		ids.append(id)
		AutobattleSystem.set_autobattle_enabled(id, true)
	var out := {"ended": false, "won": false, "low_hp": false, "defeat": false, "low_hp_panel": false, "defeat_panel": false, "ms": 0}
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < CAP_MS and is_instance_valid(scene) and not scene._battle_ended:
		if scene._boss_low_hp_spoken and scene._battle_dialogue.visible:
			out["low_hp_panel"] = true
		await get_tree().process_frame
	out["ms"] = Time.get_ticks_msec() - t0
	if is_instance_valid(scene):
		out["ended"] = scene._battle_ended
		out["low_hp"] = scene._boss_low_hp_spoken
		out["defeat"] = scene._boss_defeat_spoken
		await _frames(2)
		out["defeat_panel"] = scene._boss_defeat_spoken and scene._battle_dialogue.visible
		var living := 0
		for foe in BattleManager.enemy_party:
			if is_instance_valid(foe) and foe.is_alive:
				living += 1
		out["won"] = living == 0
	for id in ids:
		AutobattleSystem.set_autobattle_enabled(id, false)
	return out


func _judge(r: Dictionary, label: String) -> void:
	gut.p("%s: %s" % [label, r])
	assert_true(r["low_hp"], "CONTROL @%s: the Rat King's low_hp line was spoken" % label)
	assert_true(r["low_hp_panel"], "CONTROL @%s: the low_hp panel was open while the fight ran" % label)
	assert_true(r["ended"], "@%s: the autobattle fight never ended with the boss's panel up (%d ms)" % [label, r["ms"]])
	assert_true(r["won"], "@%s: the fight ended without the Rat King down" % label)
	assert_true(r["defeat"], "CONTROL @%s: the defeat line was staged" % label)


func test_a_turbo_autobattle_fight_ends_with_the_boss_panel_open() -> void:
	_judge(await _fight(true, -1), "turbo")


func test_a_speed_one_autobattle_fight_ends_with_the_boss_panel_open() -> void:
	_judge(await _fight(false, 4), "speed 1.0")
