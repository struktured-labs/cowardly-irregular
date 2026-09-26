extends GutTest

## A stun, sleep, charm, confuse, or cannot_act lock replaces that combatant's own action.
## A pooled strike is still their action: selection fast-forwards them into the roster, so the
## strike is the only place the lock can be honoured. Pre-fix the strike summed every living
## member, so a stunned ally paid AP and added their full attack — and if the stunned ally was
## the one who called it, the personal skip threw the whole group away and the rest of the
## party lost the round.


const HBR := preload("res://src/autogrind/HeadlessBattleResolver.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")

var _guard = null
var _prior_state: int = 0


func before_each() -> void:
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	BattleManager.turbo_mode = true
	_prior_state = BattleManager.current_state
	BattleManager.current_state = BattleManager.BattleState.EXECUTION_PHASE
	BattleManager.execution_order.clear()
	BattleManager.pending_actions.clear()


func after_each() -> void:
	BattleManager.current_state = _prior_state
	if _guard != null:
		_guard.restore()


func _member(name_str: String, attack: int = 40) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name_str
	c.max_hp = 500
	c.current_hp = 500
	c.attack = attack
	c.magic = attack
	c.defense = 0
	c.current_ap = 4
	c.is_alive = true
	return c


func _wall() -> Combatant:
	var e := Combatant.new()
	autofree(e)
	e.combatant_name = "Wall"
	e.max_hp = 100000000
	e.current_hp = 100000000
	e.defense = 0
	e.attack = 80
	e.is_alive = true
	return e


func _stage(roster: Array, wall: Combatant) -> void:
	BattleManager.player_party.assign(roster as Array[Combatant])
	BattleManager.enemy_party.assign([wall] as Array[Combatant])


func _physical(roster: Array, wall: Combatant) -> int:
	_stage(roster, wall)
	var before: int = wall.current_hp
	BattleManager._execute_physical_group(roster, [wall] as Array[Combatant], "all_out_attack", 1)
	return before - wall.current_hp


func test_a_stunned_ally_adds_no_power_and_spends_no_ap() -> void:
	var locked := _member("Cleric")
	locked.add_status("stun", 1)
	var pair: int = _physical([_member("Fighter"), _member("Rogue")], _wall())
	var with_locked: int = _physical([_member("Fighter"), _member("Rogue"), locked], _wall())
	assert_eq(with_locked, pair,
		"a stunned ally must not add attack or scale — two swinging is two swinging (%d vs %d)" % [with_locked, pair])
	assert_eq(locked.current_ap, 4, "the stunned ally's turn was not an attack, so it must not cost AP")
	assert_false(locked.has_status("stun"), "the group committed their turn, so the 1-turn stun is spent")


func test_a_stunned_caller_does_not_cancel_everyone_else() -> void:
	var caller := _member("Fighter")
	var ally := _member("Rogue")
	caller.add_status("stun", 1)
	var wall := _wall()
	var alone: int = _physical([_member("Rogue")], _wall())
	_stage([caller, ally], wall)
	var before: int = wall.current_hp
	BattleManager.execution_order.append({
		"type": "group",
		"combatant": caller,
		"group_type": "all_out_attack",
		"participants": [caller, ally],
		"speed": 1.0,
	})
	BattleManager._execute_next_action()
	var dealt: int = before - wall.current_hp
	assert_eq(dealt, alone,
		"the caller's stun skips the caller, not the ally who can still swing (%d vs %d)" % [dealt, alone])
	assert_false(caller.has_status("stun"), "the caller's 1-turn stun is spent by the strike they could not join")
	assert_eq(caller.current_ap, 4, "a skipped caller does not pay the group AP or the exposure penalty")
	# The ally pays the strike (1) and the vulnerability window (-2).
	assert_eq(ally.current_ap, 1, "the ally who swung pays the strike and the exposure that follows it")
	await get_tree().process_frame


func test_a_fully_locked_party_deals_nothing_and_the_next_action_still_runs() -> void:
	var a := _member("Fighter")
	var b := _member("Rogue")
	a.add_status("stun", 1)
	b.add_status("cannot_act", 1)
	var wall := _wall()
	_stage([a, b], wall)
	var before: int = wall.current_hp
	BattleManager.execution_order.append({
		"type": "attack",
		"combatant": wall,
		"target": a,
		"speed": 50.0,
	})
	BattleManager.execution_order.push_front({
		"type": "group",
		"combatant": a,
		"group_type": "all_out_attack",
		"participants": [a, b],
		"speed": 1.0,
	})
	BattleManager._execute_next_action()
	assert_eq(wall.current_hp, before, "nobody who can act was in the group, so the wall takes no group damage")
	assert_false(a.has_status("stun"), "the caller's stun is spent even though the strike fizzled")
	assert_false(b.has_status("cannot_act"), "the ally's hold is spent — their turn was committed to the group")
	assert_eq(a.current_ap, 4, "a locked caller does not pay AP for a strike they did not make")
	assert_eq(b.current_ap, 4, "a locked ally does not pay AP for a strike they did not make")
	assert_eq(BattleManager.execution_order.size(), 0,
		"the enemy action queued behind the group still ran — a fully locked party must not stall the battle")


func test_the_grind_drops_a_stunned_ally_too() -> void:
	var locked := _member("Cleric")
	locked.add_status("stun", 2)
	var wall := _wall()
	var fighter := _member("Fighter")
	var resolver = HBR.new()
	resolver._player_party = [fighter, locked]
	resolver._enemy_party = [wall]
	var before: int = wall.current_hp
	resolver._execute_group_physical([fighter, locked], "all_out_attack")
	var dealt: int = before - wall.current_hp

	var solo_wall := _wall()
	var solo_fighter := _member("Fighter")
	var solo = HBR.new()
	solo._player_party = [solo_fighter]
	solo._enemy_party = [solo_wall]
	var solo_before: int = solo_wall.current_hp
	solo._execute_group_physical([solo_fighter], "all_out_attack")
	assert_eq(dealt, solo_before - solo_wall.current_hp,
		"autogrind must drop a stunned ally from the pool, same as the battle")
	assert_eq(locked.current_ap, 4, "the grind must not charge AP for a swing the stun cancelled")
	assert_eq(int(locked.status_durations.get("stun", 0)), 1, "one committed turn spends one point of a 2-turn stun")
