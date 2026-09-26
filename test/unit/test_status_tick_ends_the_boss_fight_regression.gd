extends GutTest

## A round-start poison/burn/doom tick used to kill the last boss and then still open the
## command menu: victory is checked at the next execution boundary, which is after selection.
## The player (and autobattle) had to commit a command against a corpse before the win, the
## dungeon flag, and the rewards. The execution-phase counter still names the previous swing
## at that moment, so ending the fight there must not also grant that swing's one-shot trophy.

const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const CALIBRANT := "the_calibrant"

var _guard: RefCounted = null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()
	BattleManager.is_autobattle_enabled = false
	BattleManager.turbo_mode = true
	BattleManager.current_state = BattleManager.BattleState.EXECUTION_PHASE
	BattleManager._one_shot_achieved = false
	if BattleManager.get("_casualty_outside_execution") != null:
		BattleManager._casualty_outside_execution = false
	BattleManager._first_damage_phase = 1
	BattleManager._execution_phase_count = 1
	BattleManager._autobattle_player_turns = 0
	BattleManager._full_autobattle = false
	BattleManager._win_condition = {}


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func _fighter(name_str: String) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.initialize({
		"name": name_str, "max_hp": 500, "max_mp": 20,
		"attack": 40, "defense": 20, "magic": 10, "speed": 12,
	})
	c.job = {"id": "fighter", "abilities": ["power_strike"]}
	c.is_alive = true
	c.current_hp = c.max_hp
	return c


func _boss(hp: int, max_hp: int) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.initialize({
		"name": "Cave Rat King", "max_hp": max_hp, "max_mp": 20,
		"attack": 40, "defense": 10, "magic": 10, "speed": 8,
	})
	c.combatant_name = "Cave Rat King"
	c.max_hp = max_hp
	c.current_hp = hp
	c.is_alive = true
	c.job = {"id": "cave_rat_king", "abilities": ["filth_spray"]}
	return c


func _seat(boss: Combatant, hero: Combatant) -> void:
	var players: Array[Combatant] = [hero]
	var enemies: Array[Combatant] = [boss]
	BattleManager.player_party = players
	BattleManager.enemy_party = enemies
	BattleManager.all_combatants = players + enemies


func test_poison_that_kills_the_boss_ends_the_fight_before_the_menu() -> void:
	var boss := _boss(4, 100)
	boss.add_status("poison", 3)
	var hero := _fighter("Mira")
	_seat(boss, hero)
	BattleManager._start_new_round()
	assert_false(boss.is_alive, "CONTROL: the poison tick must actually kill the boss, or this test is not looking at a status finish")
	assert_eq(BattleManager.current_state, BattleManager.BattleState.INACTIVE,
		"a boss killed by the round-start poison tick must end the fight before the command menu — state is %s"
		% BattleManager.BattleState.keys()[BattleManager.current_state])
	assert_false(BattleManager._one_shot_achieved,
		"that tick is not the earlier swing: a poison finish must not inherit the previous execution phase's one-shot trophy")


func test_a_poison_tick_that_crosses_a_face_still_changes_it() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var row: Dictionary = parsed.get(CALIBRANT, {}) if parsed is Dictionary else {}
	var max_hp := int(row.get("stats", {}).get("max_hp", 34000))
	var boss := _boss(int(max_hp * 0.81), max_hp)
	boss.combatant_name = str(row.get("name", "The Calibrant"))
	boss.set_meta("monster_type", CALIBRANT)
	boss.job = {"id": CALIBRANT, "abilities": ["firaga", "blizzaga"]}
	boss.add_status("poison", 3)
	var hero := _fighter("Mira")
	_seat(boss, hero)
	BattleManager._start_new_round()
	assert_true(boss.is_alive, "CONTROL: this tick crosses 80%% and must leave the Calibrant standing")
	assert_ne(BattleManager.current_state, BattleManager.BattleState.INACTIVE,
		"a non-lethal phase cross must not end the fight")
	assert_true("masterite_iron_guard" in boss.job["abilities"],
		"the same round-start tick must still put on the face it crossed — kit=%s" % str(boss.job["abilities"]))
	assert_false("blizzaga" in boss.job["abilities"], "the opening kit must not survive the face change")
