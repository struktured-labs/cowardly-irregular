extends GutTest

## Live BattleManager consumer: authored stun duration is skipped actions, not one.
##
## Drives _execute_next_action the way test_boss_jailbreak_battle_integration does.
## Each call also falls through to _start_new_round, which runs end_turn. Duration
## must still survive that boundary — the round-start ticker used to burn a second point.

const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")

var _bm: Node = null
var _bm_guard = null


func before_each() -> void:
	_bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	_bm_guard = BattleStateGuard.new()
	_bm_guard.snapshot()
	if _bm:
		_bm.turbo_mode = true
		_bm.is_autobattle_enabled = false


func after_each() -> void:
	if _bm_guard != null:
		_bm_guard.restore()


func _make(cname: String, atk: int) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = cname
	c.max_hp = 400
	c.current_hp = 400
	c.max_mp = 30
	c.current_mp = 30
	c.attack = atk
	c.defense = 10
	c.magic = 10
	c.speed = 10
	c.is_alive = true
	return c


func _stage(attacker: Combatant, victim: Combatant) -> void:
	_bm.enemy_party.clear()
	_bm.player_party.clear()
	_bm.all_combatants.clear()
	_bm.enemy_party.append(attacker)
	_bm.player_party.append(victim)
	_bm.all_combatants.append(victim)
	_bm.all_combatants.append(attacker)
	_bm.volatility = VolatilitySystem.new()
	_bm.volatility.reset_battle()
	_bm.current_state = _bm.BattleState.PROCESSING_ACTION
	if AutobattleSystem:
		AutobattleSystem.set_autobattle_enabled(_bm._get_character_id(victim), false)
		AutobattleSystem.set_autobattle_enabled(_bm._get_character_id(attacker), false)


func _skip_once(attacker: Combatant, victim: Combatant) -> void:
	_bm.execution_order.clear()
	_bm.execution_order.append({
		"type": "attack",
		"combatant": attacker,
		"target": victim,
		"speed": 1.0,
	})
	_bm._execute_next_action()


func test_duration_one_clears_on_the_first_live_skip() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var attacker := _make("Brute", 80)
	var victim := _make("Stun Probe", 20)
	add_child_autofree(attacker)
	add_child_autofree(victim)
	_stage(attacker, victim)
	attacker.add_status("stun", 1)
	var hp := victim.current_hp
	_skip_once(attacker, victim)
	assert_eq(victim.current_hp, hp, "a stunned action must not land")
	assert_false(attacker.has_status("stun"), "duration 1 clears on the skip that spends it")


func test_duration_two_skips_twice_across_the_round_boundary() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var attacker := _make("Brute", 80)
	var victim := _make("Stun Probe", 20)
	add_child_autofree(attacker)
	add_child_autofree(victim)
	_stage(attacker, victim)
	attacker.add_status("stun", 2)
	var hp := victim.current_hp
	_skip_once(attacker, victim)
	assert_eq(victim.current_hp, hp, "first stunned action must not land")
	assert_true(attacker.has_status("stun"), "duration 2 survives the first skip and the round-start tick")
	assert_eq(int(attacker.status_durations.get("stun", 0)), 1)
	_skip_once(attacker, victim)
	assert_eq(victim.current_hp, hp, "second stunned action must not land")
	assert_false(attacker.has_status("stun"), "the second skip spends the last point")


func test_duration_three_skips_three_times() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var attacker := _make("Brute", 80)
	var victim := _make("Stun Probe", 20)
	add_child_autofree(attacker)
	add_child_autofree(victim)
	_stage(attacker, victim)
	attacker.add_status("stun", 3)
	var hp := victim.current_hp
	_skip_once(attacker, victim)
	assert_eq(int(attacker.status_durations.get("stun", 0)), 2, "first skip of a 3-point stun leaves 2")
	_skip_once(attacker, victim)
	assert_eq(int(attacker.status_durations.get("stun", 0)), 1, "second skip leaves 1")
	assert_true(attacker.has_status("stun"))
	_skip_once(attacker, victim)
	assert_eq(victim.current_hp, hp, "none of the three stunned actions may land")
	assert_false(attacker.has_status("stun"), "the third skip clears a duration-3 stun")
