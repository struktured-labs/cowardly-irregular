extends GutTest

## Main 27620, autogrind 27621: keeping the intro on the encounter path widens the .654 shape (an intro defers
## start_battle). A real BattleScene from that path must show the intro, start its battle on dismiss and end cleanly;
## the seat reads this file's own log for freed-instance and SCRIPT ERROR lines. A grind fight must never wait on one.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _guard = null


func before_each() -> void:
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	GameState.boss_intro_cutscene_for = ""


func after_each() -> void:
	GameState.boss_intro_cutscene_for = ""
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run_through(encounter_id: String, species: String) -> void:
	var before: int = BattleManager.battle_serial
	var scene = SCENE.instantiate()
	scene.encounter_enemies = [encounter_id]
	add_child_autofree(scene)
	await _frames(3)
	assert_true(scene._waiting_for_dialogue, "CONTROL: %s's intro panel did not show, so nothing below is measured" % species)
	assert_eq(BattleManager.battle_serial, before, "%s's battle started under its open intro" % species)
	scene._battle_dialogue.dialogue_finished.emit()
	await _frames(3)
	assert_eq(BattleManager.battle_serial, before + 1, "dismissing %s's intro did not start its battle" % species)
	var foes: Array = []
	for e in BattleManager.enemy_party:
		if is_instance_valid(e):
			foes.append(str(e.get_meta("monster_type", "")))
	assert_eq(foes, [species], "the battle the intro started is not %s's own" % species)
	BattleManager.end_battle(true)
	await _frames(10)
	assert_true(scene._battle_ended, "%s's battle never reached its end" % species)
	assert_false(scene._waiting_for_dialogue, "the intro latch outlived %s's battle" % species)


func test_a_pool_miniboss_shows_its_intro_then_fights_to_the_end() -> void:
	await _run_through("crystal_golem", "crystal_golem")


func test_the_f3_meta_knight_shows_its_intro_then_fights_to_the_end() -> void:
	await _run_through("meta_knight@L23", "meta_knight")


func test_a_grind_fight_with_a_miniboss_never_waits_on_an_intro() -> void:
	var data: Dictionary = EncounterSystem._create_enemy_data("crystal_golem")
	assert_eq(str(data.get("id", "")), "crystal_golem", "CONTROL: the grind roster entry is the Crystal Golem")
	var before: int = BattleManager.battle_serial
	var scene = SCENE.instantiate()
	scene.autogrind_enemy_data = [data]
	add_child_autofree(scene)
	await _frames(3)
	assert_false(scene._waiting_for_dialogue, "a grind fight with a miniboss stopped on an intro panel")
	assert_eq(BattleManager.battle_serial, before + 1, "a grind fight with a miniboss did not start at once")
	BattleManager.end_battle(true)
	await _frames(10)
