extends GutTest

## Regression: BattleManager.current_state was found ACTIVE with EMPTY parties at another
## test file's position (documented in test_battle_state_not_leaked_by_tests.gd, which
## measured `current_state=6 PROCESSING_ACTION, player_party=0, enemy_party=0` and named
## the mechanism as unconfirmed).
##
## Confirmed here: _execute_next_action() had NO guard against running after the battle
## ended. end_battle() sets VICTORY/DEFEAT and then _cleanup_battle() clears the queue, but
## an awaited continuation that resumes afterwards re-enters and:
##   - with a stale queued action -> sets current_state = PROCESSING_ACTION (the measured state)
##   - with an empty queue        -> falls through to _start_new_round(), resurrecting the battle
##
## Either way is_battle_active() becomes true with no battle, which blocks saving and makes
## GameLoop._start_exploration bail ("a live battle owns the screen").
##
## ⚠️ This file mutates the BattleManager AUTOLOAD. It saves and restores every field it
## touches — the leak this regression is about was itself caused by a test that didn't.

var _saved_state: int = 0
var _saved_order: Array = []
var _saved_player: Array = []
var _saved_enemy: Array = []


func before_each() -> void:
	_saved_state = BattleManager.current_state
	_saved_order = BattleManager.execution_order.duplicate()
	_saved_player = BattleManager.player_party.duplicate()
	_saved_enemy = BattleManager.enemy_party.duplicate()


func after_each() -> void:
	BattleManager.execution_order = _saved_order.duplicate()
	BattleManager.player_party = _saved_player.duplicate()
	BattleManager.enemy_party = _saved_enemy.duplicate()
	BattleManager.current_state = _saved_state


func _live_combatant(who: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = who
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	return c


## A battle that ENDED with both sides still alive. That is not hypothetical: the spotlight
## duels use custom win conditions (survive_turns for the Cleric, status_threshold for the
## Bard), so end_battle fires with the enemy at full HP. _check_victory_conditions() then
## returns FALSE on re-entry — which is precisely why a guard is needed and why the empty-
## party fixture I first wrote could not detect its absence.
func _ended_battle_with_stale_action(ended_state: int) -> void:
	var hero := _live_combatant("Hero")
	BattleManager.player_party = [hero]
	BattleManager.enemy_party = [_live_combatant("Duelist")]
	BattleManager.execution_order = [{"combatant": hero, "type": "attack"}]
	BattleManager.current_state = ended_state


func test_stale_action_after_victory_does_not_reactivate() -> void:
	_ended_battle_with_stale_action(BattleManager.BattleState.VICTORY)
	BattleManager._execute_next_action()
	assert_eq(BattleManager.current_state, BattleManager.BattleState.VICTORY,
		"a continuation resuming after victory must not set PROCESSING_ACTION")
	assert_false(BattleManager.is_battle_active(),
		"is_battle_active() must stay false — true here blocks saving and bails exploration")


func test_stale_action_after_defeat_does_not_reactivate() -> void:
	_ended_battle_with_stale_action(BattleManager.BattleState.DEFEAT)
	BattleManager._execute_next_action()
	assert_eq(BattleManager.current_state, BattleManager.BattleState.DEFEAT,
		"same guard must hold on the defeat path")


func test_empty_queue_after_end_does_not_start_a_new_round() -> void:
	BattleManager.player_party = [_live_combatant("Hero")]
	BattleManager.enemy_party = [_live_combatant("Duelist")]
	BattleManager.execution_order = []
	BattleManager.current_state = BattleManager.BattleState.INACTIVE
	BattleManager._execute_next_action()
	assert_eq(BattleManager.current_state, BattleManager.BattleState.INACTIVE,
		"an empty queue after the battle ended must not fall through to _start_new_round")


func test_control_guard_permits_a_live_battle() -> void:
	# CONTROL: the guard must not swallow legitimate execution. Needs a real combatant on
	# BOTH sides — with empty parties _check_victory_conditions() returns first and nothing
	# advances no matter what the guard does, which is how this control failed when I
	# reused the ended-battle fixture.
	var hero := _live_combatant("Hero")
	BattleManager.player_party = [hero]
	BattleManager.enemy_party = [_live_combatant("Slime")]
	BattleManager.execution_order = [{"combatant": hero, "type": "attack"}]
	BattleManager.current_state = BattleManager.BattleState.EXECUTION_PHASE
	BattleManager._execute_next_action()
	assert_ne(BattleManager.current_state, BattleManager.BattleState.EXECUTION_PHASE,
		"CONTROL: a live battle must still advance past the guard — otherwise the assertions above are vacuous")
