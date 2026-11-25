extends GutTest

## Main 27620, autogrind 27621: keeping the intro on the encounter path widens the .654 shape (an intro defers
## start_battle). A real BattleScene from that path must show the intro, start its battle on dismiss and end cleanly;
## the seat reads this file's own log for freed-instance and SCRIPT ERROR lines. A grind fight must never wait on one.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _guard = null
var _saved_constants: Dictionary = {}


func before_each() -> void:
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	GameState.boss_intro_cutscene_for = ""
	_saved_constants = GameState.game_constants.duplicate(true)
	GameState.game_constants.erase("pool_intro_heard")


func after_each() -> void:
	GameState.boss_intro_cutscene_for = ""
	GameState.game_constants = _saved_constants
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


## Story 27694: the low_hp gate fires for a speaker that is NOT is_boss (a first-sighting pool monster, a field elite).
func _wounded_line_fires(encounter_id: String, species: String) -> void:
	var scene = SCENE.instantiate()
	scene.encounter_enemies = [encounter_id]
	add_child_autofree(scene)
	await _frames(3)
	assert_true(scene._waiting_for_dialogue, "CONTROL: %s's opening line showed, so it is this fight's speaker" % species)
	scene._battle_dialogue.dialogue_finished.emit()
	await _frames(3)
	var foe: Combatant = null
	for e in BattleManager.enemy_party:
		if is_instance_valid(e) and str(e.get_meta("monster_type", "")) == species:
			foe = e
	assert_not_null(foe, "CONTROL: %s is in the battle" % species)
	if foe == null:
		return
	assert_false(foe.has_meta("is_boss"), "CONTROL: %s speaks without being a boss" % species)
	assert_false(scene._boss_low_hp_spoken, "CONTROL: the wounded line had not fired before the hit")
	foe.current_hp = max(1, int(foe.max_hp * 0.1))
	scene._on_damage_dealt(foe, 1, false)
	assert_true(scene._boss_low_hp_spoken, "%s dropped below 25%% and its wounded line never fired" % species)
	BattleManager.end_battle(true)
	await _frames(10)


func test_a_first_sighting_pool_monster_speaks_when_wounded() -> void:
	await _wounded_line_fires("the_absence", "the_absence")


func test_a_field_elite_speaks_when_wounded() -> void:
	await _wounded_line_fires("brass_golem@elite", "brass_golem")
