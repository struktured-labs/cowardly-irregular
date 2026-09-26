extends GutTest

## Front Line and Back Row live on BattleScene.current_formation, a script
## static. The next fight in the same process keeps the row. Quit and Continue
## does not: the save never recorded it, so the process starts on V-Formation
## and the attack/defense trade is gone. Quit to Title and New Game does the
## opposite: reset_game_state clears the leader index and the battle-speed
## ladder, and leaves the static, so the new party opens in the previous
## run's row. A partial apply (day phase, and every other caller that passes
## a dict without this key) must not wipe a row the save never mentioned.
## A full file load is the other input. An old save has no party_formation
## key; leaving this session's Back Row in place writes it into that slot
## on the next autosave. That path resets to V-Formation.

const BS_PATH := "res://src/battle/BattleScene.gd"

var _saved_formation: int = 0
var _prior_state: Dictionary = {}
var _started: bool = false


func before_each() -> void:
	_saved_formation = int(load(BS_PATH).current_formation)
	_prior_state = GameState.to_dict()
	_started = false


func after_each() -> void:
	if _started and BattleManager and BattleManager.has_method("_cleanup_battle"):
		BattleManager._cleanup_battle()
	if not _prior_state.is_empty():
		GameState.from_dict(_prior_state)
	load(BS_PATH).current_formation = _saved_formation


func _scene() -> GDScript:
	return load(BS_PATH)


func _mod(c: Combatant, effect: String) -> float:
	for bucket in [c.active_buffs, c.active_debuffs]:
		for entry in bucket:
			if str(entry.get("effect", "")) == effect:
				return float(entry.get("modifier", 0.0))
	return -1.0


func _reload(saved: Dictionary) -> void:
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	GameState.from_dict(parsed)


func test_saved_back_row_returns_on_load_and_the_next_battle() -> void:
	var scene := _scene()
	scene.current_formation = scene.PartyFormation.BACK_ROW
	var saved := GameState.to_dict()
	assert_eq(int(saved.get("party_formation", -1)), scene.PartyFormation.BACK_ROW,
		"the save must record the row the party is standing in")
	scene.current_formation = scene.PartyFormation.V_FORMATION
	_reload(saved)
	assert_eq(int(scene.current_formation), scene.PartyFormation.BACK_ROW,
		"Continue must put the party back in Back Row, not the process default")
	var pc := Combatant.new()
	pc.combatant_name = "Row Probe"
	pc.attack = 200
	pc.defense = 100
	pc.max_hp = 100
	pc.current_hp = 100
	pc.is_alive = true
	add_child_autofree(pc)
	var slime := Combatant.new()
	slime.combatant_name = "Row Slime"
	slime.max_hp = 10
	slime.current_hp = 10
	slime.is_alive = true
	add_child_autofree(slime)
	var party: Array[Combatant] = [pc]
	var foes: Array[Combatant] = [slime]
	_started = true
	BattleManager.start_battle(party, foes)
	assert_almost_eq(_mod(pc, "formation_def"), 1.1, 0.001,
		"the loaded Back Row has to be +10% DEF on the next fight")
	assert_almost_eq(_mod(pc, "formation_atk"), 0.9, 0.001,
		"and -10% ATK — the menu's Back Row line, not a bare V-Formation")
	assert_gt(pc.get_buffed_stat("defense", pc.defense), pc.defense,
		"the defense trade has to reach the number the swing uses")
	assert_lt(pc.get_buffed_stat("attack", pc.attack), pc.attack,
		"the attack penalty has to reach the number the swing uses")


func test_new_game_clears_the_previous_runs_row() -> void:
	var scene := _scene()
	scene.current_formation = scene.PartyFormation.BACK_ROW
	GameState.reset_game_state()
	assert_eq(int(scene.current_formation), scene.PartyFormation.V_FORMATION,
		"New Game must open on V-Formation — the previous run's Back Row is not this party's choice")


func test_an_old_file_without_the_key_resets_to_v_formation() -> void:
	var scene := _scene()
	scene.current_formation = scene.PartyFormation.BACK_ROW
	var ss = get_node_or_null("/root/SaveSystem")
	if ss == null:
		pending("SaveSystem autoload required")
		return
	var saved := GameState.to_dict()
	saved.erase("party_formation")
	assert_false(saved.has("party_formation"),
		"precondition: this file is an old save — it has no row key")
	var parsed: Variant = JSON.parse_string(JSON.stringify({"game_state": saved}))
	ss._apply_save_data(parsed)
	assert_eq(int(scene.current_formation), scene.PartyFormation.V_FORMATION,
		"an old save with no party_formation key must open on V-Formation — Back Row was this session, not that file")


func test_a_save_without_the_key_leaves_the_live_row() -> void:
	var scene := _scene()
	scene.current_formation = scene.PartyFormation.FRONT_LINE
	GameState._apply_save_data({"day_phase": 0.5})
	assert_eq(int(scene.current_formation), scene.PartyFormation.FRONT_LINE,
		"a dict that never stored a row must not clear the one this session is using")


func test_a_corrupt_formation_clamps_to_a_real_row() -> void:
	var scene := _scene()
	scene.current_formation = scene.PartyFormation.BACK_ROW
	var saved := GameState.to_dict()
	saved["party_formation"] = 99.0
	_reload(saved)
	assert_eq(int(scene.current_formation), scene.FORMATION_NAMES.size() - 1,
		"a formation past the list must land on the last real row")
	saved["party_formation"] = -3.0
	scene.current_formation = scene.PartyFormation.BACK_ROW
	_reload(saved)
	assert_eq(int(scene.current_formation), scene.PartyFormation.V_FORMATION,
		"a negative formation must land on V-Formation")
