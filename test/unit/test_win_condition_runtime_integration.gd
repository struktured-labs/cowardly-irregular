extends GutTest

const BattleState := preload("res://test/unit/helpers/battle_state.gd")

## Runtime companion to test_win_condition_dispatch_regression.gd
## (which is all source pins). These tests drive the tick-472 win_
## condition machinery with REAL Combatants through the live
## BattleManager autoload — catching wiring bugs the source pins
## can't (dispatch ordering, meta-read typos, end_battle side-effect
## crashes) BEFORE the user's first Spotlight Duel playtest.
##
## Covers the two shipped non-HP duels:
##   - cleric_survive_target → survive_turns: 8
##   - bard_hostile_courtier → status_threshold: swayed >= 3

const COMBATANT_PATH := "res://src/battle/Combatant.gd"

var _bm: Node = null
var _guard: RefCounted = null


## ⛔ WAS A FIVE-FIELD HAND-LIST AND LEAKED THREE MORE. This teardown was careful — it restored
## player_party, enemy_party, current_round, _win_condition and current_state, and its comment
## correctly warned that `is` on a freed instance aborts after_each. It still left
## _battle_results, _party_line_cooldowns and _party_line_last_kind on the AUTOLOAD for every file
## sorting after this one (measured 2026-09-18 by running this file then a surface probe in ONE
## process). The author thought about the teardown and restored the fields they were reasoning
## about; a hand-list cannot cover the ones they were not. The helper derives the surface from
## get_property_list(), keeps the freed-instance guard this file discovered, and restores typed
## arrays through assign() so a plain-Array assignment cannot abort the loop.
func before_each() -> void:
	_bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if _bm == null:
		return
	_guard = BattleState.new()
	_guard.snapshot()


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func _make(name_str: String) -> Combatant:
	var s: GDScript = load(COMBATANT_PATH)
	var c: Combatant = s.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 5, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func _stage(wc: Dictionary) -> Dictionary:
	# Returns {"pc": Combatant, "foe": Combatant} with parties staged.
	var pc: Combatant = _make("DuelPC")
	var foe: Combatant = _make("DuelFoe")
	var party: Array[Combatant] = [pc]
	var foes: Array[Combatant] = [foe]
	_bm.player_party = party
	_bm.enemy_party = foes
	_bm._win_condition = wc
	return {"pc": pc, "foe": foe}


func test_survive_turns_evaluates_true_at_target_round() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	_stage({"type": "survive_turns", "value": 3})
	_bm.current_round = 3
	assert_true(_bm._evaluate_custom_win_condition(),
		"survive_turns must evaluate true when current_round reaches the authored value")


func test_survive_turns_evaluates_false_before_target() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	_stage({"type": "survive_turns", "value": 8})
	_bm.current_round = 7
	assert_false(_bm._evaluate_custom_win_condition(),
		"survive_turns must stay false one round short of the target — the Cleric duel is 8 full rounds")


func test_status_threshold_meta_counter_path() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var staged := _stage({"type": "status_threshold", "status": "swayed", "value": 3})
	var foe: Combatant = staged["foe"]
	foe.set_meta("_swayed_stacks", 2)
	assert_false(_bm._evaluate_custom_win_condition(),
		"2/3 swayed stacks must not win yet")
	foe.set_meta("_swayed_stacks", 3)
	assert_true(_bm._evaluate_custom_win_condition(),
		"3/3 swayed stacks (meta counter) must evaluate true — the Bard duel talk-down")


func test_status_threshold_dead_target_does_not_count() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var staged := _stage({"type": "status_threshold", "status": "swayed", "value": 3})
	var foe: Combatant = staged["foe"]
	foe.set_meta("_swayed_stacks", 3)
	foe.current_hp = 0
	foe.is_alive = false
	assert_false(_bm._evaluate_custom_win_condition(),
		"a dead target's stacks must not count for status_threshold — the talk-down needs a live listener (dead courtier falls through to standard hp_zero victory instead)")


func test_check_victory_fires_end_battle_on_survive_turns() -> void:
	# Full wiring: _check_victory_conditions → end_battle(true) with the
	# custom condition met while enemies are STILL ALIVE. This is the
	# path source pins can't prove — end_battle's victory chain must
	# survive a meta-less dummy enemy without crashing.
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	_stage({"type": "survive_turns", "value": 2})
	_bm.current_round = 2
	var ended: bool = _bm._check_victory_conditions()
	assert_true(ended,
		"_check_victory_conditions must report battle-ended when survive_turns met")
	# 2026-07-03: cleanup now returns the machine to INACTIVE, so the terminal observable is the cleaned state (VICTORY is transient during the battle_ended emit)
	assert_eq(_bm.current_state, _bm.BattleState.INACTIVE,
		"custom win must complete end_battle + cleanup even though the enemy is still alive")
	assert_true(_bm._win_condition.is_empty(),
		"end_battle must have cleared _win_condition (one-shot per battle)")


func test_check_victory_no_false_positive_with_default_condition() -> void:
	# Empty _win_condition + both sides alive = battle continues.
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	_stage({})
	_bm.current_round = 99
	assert_false(_bm._check_victory_conditions(),
		"with default (empty) win_condition and both sides alive, no victory may fire regardless of round count")
