extends GutTest

## _cleanup_battle iterated all_combatants and read combatant.died BEFORE clearing anything.
## A freed member aborts that loop, so the three .clear() calls and the INACTIVE reset below it
## never ran — and :1051's own comment says an unreset state leaves every "!= INACTIVE" gate
## reading "in battle" for the rest of the session. The stale array then aborts the NEXT
## battle's _check_victory_conditions. Observed live in two full-suite runs, 2026-08-21.

var _saved_all: Array = []
var _saved_players: Array = []
var _saved_enemies: Array = []
var _saved_state = null
var _saved_cbs: Dictionary = {}


func before_each() -> void:
	_saved_all = BattleManager.all_combatants.duplicate()
	_saved_players = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	_saved_state = BattleManager.current_state
	_saved_cbs = BattleManager._died_callbacks.duplicate()


func after_each() -> void:
	## BattleManager is an autoload — a leaked freed key here aborts unrelated later tests.
	BattleManager.all_combatants.assign(_saved_all)
	BattleManager.player_party.assign(_saved_players)
	BattleManager.enemy_party.assign(_saved_enemies)
	BattleManager.current_state = _saved_state
	BattleManager._died_callbacks = _saved_cbs


func _noop() -> void:
	pass


## The abort needs cb truthy — an unregistered combatant short-circuits before touching .died,
## which is how the first version of this test passed with the guard removed.
func _registered_then_freed() -> Combatant:
	var c := Combatant.new()
	add_child(c)
	var cb := Callable(self, "_noop")
	c.died.connect(cb)
	BattleManager._died_callbacks[c] = cb
	return c


func test_cleanup_clears_state_even_with_a_freed_combatant() -> void:
	var doomed := _registered_then_freed()
	BattleManager.all_combatants.assign([doomed])
	BattleManager.player_party.assign([doomed])
	BattleManager.enemy_party.assign([])
	BattleManager.current_state = BattleManager.BattleState.VICTORY
	doomed.free()

	BattleManager._cleanup_battle()

	assert_eq(BattleManager.all_combatants.size(), 0, "all_combatants cleared — the loop above it must not abort")
	assert_eq(BattleManager.player_party.size(), 0, "player_party cleared")
	assert_eq(BattleManager.current_state, BattleManager.BattleState.INACTIVE,
		"state reset to INACTIVE — the wedge is that this line is BELOW the loop and gets skipped")


func test_victory_check_survives_a_freed_party_member() -> void:
	var doomed := _registered_then_freed()
	BattleManager.player_party.assign([doomed])
	BattleManager.enemy_party.assign([])
	doomed.free()
	var reached := 0
	var _r = BattleManager._check_victory_conditions()
	reached += 1
	assert_eq(reached, 1, "the call returned instead of aborting its caller on a freed member")
