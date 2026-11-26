extends GutTest

## His log (2026-11-15, godot2026-11-15T21.28.43.log): a Hero Mimics fight wrote hero_mimic_0/1/2 into the bestiary save.
## A mimic copies the party and has no monsters.json row, so the battle's three bestiary writers now skip it.

const BattleState := preload("res://test/unit/helpers/battle_state.gd")

const MIMIC := "mimic_guard_copy_0"
const OTHER := "mimic_guard_control"

var _guard: RefCounted = null


class SpawnHost:
	extends Node
	var enemy_positions: Array = [0, 0, 0]
	var test_enemies: Array = []

	func _on_enemy_hp_changed(_old_value, _new_value, _enemy_idx) -> void:
		pass

	func _on_enemy_died(_enemy_idx) -> void:
		pass

	func _on_status_added(_status, _combatant) -> void:
		pass

	func _on_status_removed(_status, _combatant) -> void:
		pass

	func _on_status_tick_damage(_amount, _source, _target) -> void:
		pass

	func _on_status_tick_heal(_amount, _source, _target) -> void:
		pass

	func log_message(_message: String) -> void:
		pass

	func _update_ui() -> void:
		pass


class QuipScene:
	extends "res://src/battle/BattleScene.gd"
	var logged: Array = []

	func log_message(message: String) -> void:
		logged.append(message)

	func _get_combatant_sprite(_combatant: Combatant) -> Node2D:
		return null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()
	_erase(MIMIC)
	_erase(OTHER)


func after_each() -> void:
	_erase(MIMIC)
	_erase(OTHER)
	if _guard != null:
		_guard.restore()


func _erase(monster_id: String) -> void:
	for key in ["defeated_monsters", "defeated_counts", "seen_monsters", "seen_monsters_last_location"]:
		var bucket: Variant = GameState.game_constants.get(key, null)
		if bucket is Dictionary:
			(bucket as Dictionary).erase(monster_id)


func _foe(monster_id: String, mimic: bool, alive: bool = true) -> Combatant:
	var enemy := Combatant.new()
	enemy.combatant_name = monster_id
	enemy.max_hp = 100
	enemy.current_hp = 100 if alive else 0
	enemy.is_alive = alive
	enemy.set_meta("monster_type", monster_id)
	if mimic:
		enemy.set_meta("is_mimic", true)
	add_child_autofree(enemy)
	return enemy


func _hero() -> Combatant:
	var hero := Combatant.new()
	hero.combatant_name = "Cleric"
	hero.job_level = 2
	hero.is_alive = true
	hero.current_hp = hero.max_hp
	add_child_autofree(hero)
	return hero


func test_the_spawner_tags_a_mimic_and_nothing_else() -> void:
	var host := SpawnHost.new()
	add_child_autofree(host)
	var mimic := {"id": MIMIC, "name": "Cleric Mimic", "max_hp": 80, "max_mp": 20, "attack": 10, "defense": 10,
		"magic": 10, "speed": 10, "is_mimic": true, "mimic_index": 0, "reward_multiplier": 2.5}
	var plain := mimic.duplicate()
	plain["id"] = OTHER
	plain.erase("is_mimic")
	BattleEnemySpawner.new(host).spawn_from_data([mimic, plain])
	assert_eq(host.test_enemies.size(), 2, "CONTROL: both enemies spawned")
	if host.test_enemies.size() < 2:
		return
	assert_false(BestiarySystem.records(host.test_enemies[0]), "a spawned Hero Mimic still counts for the bestiary")
	assert_true(BestiarySystem.records(host.test_enemies[1]), "CONTROL: an ordinary spawned enemy counts for the bestiary")


func test_beating_a_mimic_records_no_kill() -> void:
	var hero := _hero()
	var copy := _foe(MIMIC, true, false)
	var other := _foe(OTHER, false, false)
	BattleManager._first_damage_phase = -1
	BattleManager._one_shot_achieved = false
	BattleManager._full_autobattle = false
	BattleManager._autobattle_player_turns = 0
	BattleManager._ko_this_battle.clear()
	var party: Array[Combatant] = [hero]
	var foes: Array[Combatant] = [copy, other]
	var everyone: Array[Combatant] = [hero, copy, other]
	BattleManager.player_party = party
	BattleManager.enemy_party = foes
	BattleManager.all_combatants = everyone
	BattleManager.defer_victory_payout = false
	BattleManager.end_battle(true)
	assert_eq(BestiarySystem.get_defeat_count(OTHER), 1, "CONTROL: the ordinary foe's kill was recorded")
	assert_false(BestiarySystem.is_seen(MIMIC), "beating a Hero Mimic wrote its copy id into the bestiary")


func test_scanning_a_mimic_records_nothing() -> void:
	var caster := _hero()
	BattleManager._execute_scan_effect(caster, [_foe(MIMIC, true), _foe(OTHER, false)])
	assert_true(BestiarySystem.is_seen(OTHER), "CONTROL: scanning an ordinary foe marks it seen")
	assert_false(BestiarySystem.is_seen(MIMIC), "scanning a Hero Mimic wrote its copy id into the bestiary")


func test_meeting_a_mimic_is_not_a_new_monster() -> void:
	var scene: QuipScene = autofree(QuipScene.new())
	scene.party_members.append(_hero())
	scene.test_enemies.append(_foe(MIMIC, true))
	scene._show_battle_quip()
	assert_false(scene.logged.is_empty(), "CONTROL: the battle-start quip ran")
	assert_false(BestiarySystem.is_seen(MIMIC), "meeting a Hero Mimic marked its copy id seen as a new monster")
	scene.test_enemies.clear()
	scene.test_enemies.append(_foe(OTHER, false))
	scene._show_battle_quip()
	assert_true(BestiarySystem.is_seen(OTHER), "CONTROL: meeting an unseen ordinary foe marks it seen")
