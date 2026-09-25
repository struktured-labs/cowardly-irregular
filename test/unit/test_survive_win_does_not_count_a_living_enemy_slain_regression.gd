extends GutTest

## A non-HP victory used to mark every foe slain. The Cleric duel (survive_turns
## against The Grinding Wound — "cannot be defeated, only outlasted"), the Bard
## sway duel, and a W6 withhold all call end_battle(true) while the foe is still
## standing. Records' Monsters Slain and the bestiary counted that as a kill.


const BattleState := preload("res://test/unit/helpers/battle_state.gd")

const LIVING := "survive_win_still_standing"
const SLAIN := "survive_win_actually_down"

var _guard: RefCounted = null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()
	_erase(LIVING)
	_erase(SLAIN)


func after_each() -> void:
	_erase(LIVING)
	_erase(SLAIN)
	if _guard != null:
		_guard.restore()


func _erase(monster_id: String) -> void:
	if GameState == null or not ("game_constants" in GameState):
		return
	for key in ["defeated_monsters", "defeated_counts", "seen_monsters", "seen_monsters_last_location"]:
		var bucket: Variant = GameState.game_constants.get(key, null)
		if bucket is Dictionary:
			(bucket as Dictionary).erase(monster_id)


func _foe(monster_id: String, alive: bool) -> Combatant:
	var enemy := Combatant.new()
	enemy.combatant_name = monster_id
	enemy.max_hp = 100
	enemy.current_hp = 100 if alive else 0
	enemy.is_alive = alive
	enemy.set_meta("monster_type", monster_id)
	add_child_autofree(enemy)
	return enemy


func _finish(enemies: Array[Combatant]) -> void:
	var hero := Combatant.new()
	hero.combatant_name = "Cleric"
	hero.job_level = 2
	hero.job_exp = 0
	hero.is_alive = true
	hero.current_hp = hero.max_hp
	add_child_autofree(hero)
	BattleManager._first_damage_phase = -1
	BattleManager._one_shot_achieved = false
	BattleManager._full_autobattle = false
	BattleManager._autobattle_player_turns = 0
	BattleManager._ko_this_battle.clear()
	BattleManager._win_condition = {"type": "survive_turns", "value": 8}
	var party: Array[Combatant] = [hero]
	var everyone: Array[Combatant] = [hero]
	for enemy in enemies:
		everyone.append(enemy)
	BattleManager.player_party = party
	BattleManager.enemy_party = enemies
	BattleManager.all_combatants = everyone
	BattleManager.defer_victory_payout = false
	BattleManager.end_battle(true)


func test_a_survive_win_does_not_count_the_enemy_still_standing() -> void:
	var living := _foe(LIVING, true)
	var dead := _foe(SLAIN, false)
	_finish([living, dead])
	assert_eq(BestiarySystem.get_defeat_count(LIVING), 0,
		"a survive win left this foe standing — Monsters Slain must not count them")
	assert_false(BestiarySystem.is_defeated(LIVING),
		"the bestiary must not file a living foe as defeated")
	assert_eq(BestiarySystem.get_defeat_count(SLAIN), 1,
		"an enemy that actually went down in the same victory is still one kill")
