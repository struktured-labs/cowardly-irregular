extends GutTest

## ⛔ THE ONE-SHOT SYSTEM WAS BLIND TO THE PARTY'S OWN ALPHA STRIKE, IN BOTH ENGINES.
## `BattleManager._record_first_damage` has three call sites — `_execute_attack`,
## `_execute_physical_ability`, `_execute_magic_ability` — and every one of the NINE
## `take_damage` sites in the three group paths calls the combatant directly: one in
## `_execute_physical_group`, one in `_execute_combo_magic`, seven across `_execute_formation_special`'s
## six specials. So a party
## that banked AP for one round and then wiped the field with a single All-Out Attack left
## `_first_damage_phase` at its -1 sentinel, and `_check_one_shot` returns on that sentinel BEFORE
## it reaches its own `all_dead` test: no rank, no S-rank 3.0x EXP, no trophy — for the most
## canonical one-shot the game has, at exactly the one setup turn `_get_one_shot_rank` calls S.
##
## The grind had the same hole one layer over and for a different reason, which is why it is in
## this file rather than two: `HeadlessBattleResolver._try_group_attack` lands its damage during
## SELECTION and returns a `group_done` marker whose execute arm is `pass`, so
## `_note_first_enemy_hp_loss` — which only runs around `_execute_action` — captured its hp_before
## after the field was already dead. Measured on the balance harness: a banked party scored
## 0/4 one-shots before and 4/4 after, same seed, nothing else changed.
##
## ⚠️ Found while validating a three-path boss harness, NOT by reading the recorder: the harness's
## oneshot path reported 0% while its own battle log showed a 5351-damage all_out_attack wiping an
## untouched field in round 2. The three recorded sites each carry the comment "# Track first damage
## for one-shot detection"; the seven that do not carry nothing, so no grep for the mechanism finds
## the hole — only the contradiction between a log and a number does.

const HBR := preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _phase_backup: int = -1
var _round_backup: int = -1
var _count_backup: int = 0
var _players_backup: Array = []
var _enemies_backup: Array = []
var _group_flag_was: bool = false


func before_each() -> void:
	_phase_backup = BattleManager._first_damage_phase
	_round_backup = BattleManager._first_damage_round
	_count_backup = BattleManager._execution_phase_count
	_players_backup = BattleManager.player_party.duplicate()
	_enemies_backup = BattleManager.enemy_party.duplicate()
	## `_execute_group_action` fires event_flag_first_group_attack through PartyChatSystem, which
	## writes GameState.game_constants. A guard that leaves a story flag set behind it is a guard
	## that changes the next test's world.
	_group_flag_was = bool(_game_constants().get("event_flag_first_group_attack", false))


func after_each() -> void:
	BattleManager._first_damage_phase = _phase_backup
	BattleManager._first_damage_round = _round_backup
	BattleManager._execution_phase_count = _count_backup
	BattleManager._casualty_outside_execution = false
	BattleManager._all_out_attack_this_battle = false
	BattleManager.player_party.clear()
	BattleManager.enemy_party.clear()
	for c in _players_backup:
		BattleManager.player_party.append(c)
	for c in _enemies_backup:
		BattleManager.enemy_party.append(c)
	var gc := _game_constants()
	if _group_flag_was:
		gc["event_flag_first_group_attack"] = true
	else:
		gc.erase("event_flag_first_group_attack")


func _game_constants() -> Dictionary:
	var tree := Engine.get_main_loop()
	if tree is SceneTree and (tree as SceneTree).root.has_node("GameState"):
		return (tree as SceneTree).root.get_node("GameState").game_constants
	return {}


func _make(cname: String, attack: int, defense: int, hp: int, ap: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = cname
	c.attack = attack
	c.defense = defense
	c.max_hp = hp
	c.current_hp = hp
	c.current_ap = ap
	c.is_alive = true
	return c


## Both parties are populated with LIVING members on purpose. `_execute_group_action` calls
## `_check_victory_conditions` after its dispatch, and that helper reads BattleManager's own
## rosters: an empty player_party reads as a wipe and would call end_battle(false) inside the
## guard. The enemy survives the strike for the same reason — a dead field is a victory.
func _drive_a_group_attack(enemy_hp: int) -> Array:
	var a := _make("Hero A", 40, 0, 500, 4)
	var b := _make("Hero B", 40, 0, 500, 4)
	var foes: Array[Combatant] = [_make("Foe 1", 10, 0, enemy_hp, 1), _make("Foe 2", 10, 0, enemy_hp, 1)]
	BattleManager.player_party.clear()
	BattleManager.enemy_party.clear()
	for c in [a, b]:
		BattleManager.player_party.append(c)
	for c in foes:
		BattleManager.enemy_party.append(c)
	BattleManager._execute_group_action({
		"type": "group", "group_type": "all_out_attack", "participants": [a, b],
	})
	return foes


func test_floor_the_names_this_file_reaches_still_exist() -> void:
	## Its own arm, so it cannot shift any other arm's statement order. Every name below is reached
	## at RUNTIME (a property read or a method call), so a rename aborts the reaching function and
	## an arm with a prior assert would score Passing on that assert with the subject never checked.
	for n in ["_first_damage_phase", "_first_damage_round", "_execution_phase_count",
			"_casualty_outside_execution", "_all_out_attack_this_battle"]:
		assert_true(n in BattleManager,
			"BattleManager.%s is state this guard reads and restores; a rename makes the arms below it vacuous" % n)
	for m in ["_execute_group_action", "_record_first_damage", "_check_one_shot"]:
		assert_true(BattleManager.has_method(m),
			"BattleManager.%s is the mechanism under test here" % m)
	assert_true(HBR.new().has_method("_note_first_enemy_hp_loss"),
		"the resolver's first-damage observer is what the grind arm below mutates")


func test_a_landed_group_attack_records_the_first_damage() -> void:
	BattleManager._first_damage_phase = -1
	BattleManager._first_damage_round = -1
	BattleManager._execution_phase_count = 1
	BattleManager.current_round = 1
	assert_eq(BattleManager._first_damage_phase, -1,
		"CONTROL: the phase must be unset before the strike, or the flip below proves nothing")
	var foes := _drive_a_group_attack(1_000_000)
	assert_lt(int(foes[0].current_hp), 1_000_000,
		"CONTROL: the all-out attack has to actually land, or there is no first damage to record")
	assert_eq(BattleManager._first_damage_phase, 1,
		"a pooled group attack that drew blood must record the first damage at the CURRENT execution phase — without it _check_one_shot returns on the -1 sentinel and the party's alpha strike can never be a one-shot")


func test_a_second_group_attack_does_not_move_the_first_damage() -> void:
	## `_record_first_damage` is idempotent behind `if _first_damage_round == -1`, and this arm is
	## why the fix observes HP loss rather than recording unconditionally: a group attack in phase 3
	## that re-stamped the phase would make `_execution_phase_count == _first_damage_phase` true
	## again and score a one-shot for a fight that had been going for three phases.
	BattleManager._first_damage_phase = -1
	BattleManager._first_damage_round = -1
	BattleManager._execution_phase_count = 1
	BattleManager.current_round = 1
	_drive_a_group_attack(1_000_000)
	assert_eq(BattleManager._first_damage_phase, 1, "CONTROL: the first strike recorded phase 1")
	BattleManager._execution_phase_count = 3
	BattleManager.current_round = 3
	_drive_a_group_attack(1_000_000)
	assert_eq(BattleManager._first_damage_phase, 1,
		"the SECOND pooled strike must not re-stamp the phase — a late group attack would otherwise read as the fight's first damage and award an unearned one-shot")


func test_the_grind_scores_a_pooled_wipe_as_a_one_shot() -> void:
	## End to end through the engine autogrind actually runs: two members with AP and two enemies is
	## exactly `_try_group_attack`'s all-out condition, and these two carry no job so
	## `_detect_formation` cannot pick a formation special instead.
	var a := _make("Hero A", 400, 0, 500, 1)
	var b := _make("Hero B", 400, 0, 500, 1)
	var resolver = HBR.new()
	var result: Dictionary = resolver.resolve_battle([a, b],
		[_make("Foe 1", 1, 0, 1, 1), _make("Foe 2", 1, 0, 1, 1)])
	assert_true(bool(result.get("victory", false)), "CONTROL: the party has to win for a one-shot to be on the table")
	## THE DISCRIMINATOR. An ordinary swing already recorded first damage correctly, so a true
	## `_one_shot` proves nothing until the log says the kill came from the pooled path.
	var pooled := false
	for line in (result.get("log", []) as Array):
		if str(line).contains("GROUP"):
			pooled = true
	assert_true(pooled,
		"CONTROL: this fixture must wipe the field with a GROUP attack, not with two ordinary attacks — otherwise the arm below tests the path that already worked")
	assert_true(bool(resolver._one_shot),
		"the grind must score a pooled wipe as a one-shot: _try_group_attack lands its damage during SELECTION and its execute arm is a no-op, so without an hp-loss observation at the selection site _first_damage_round stays -1 and _grant_one_shot_trophies never runs")
