extends GutTest

## Y (Repeat) re-queues every party member and then jumps selection_index to the end.
## Players select before enemies, so that jump never reaches the monsters: they take
## no turn. A party member who already confirmed this round is queued a second time
## and acts twice. Repeat may only fill characters who have not chosen yet, then
## selection continues so the enemy side still goes.

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


func _make(cname: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = cname
	c.max_hp = 500
	c.current_hp = 500
	c.max_mp = 30
	c.current_mp = 30
	c.attack = 10
	c.defense = 80
	c.magic = 10
	c.speed = 10
	c.current_ap = 1
	c.is_alive = true
	return c


func _remember_attack(who: Combatant, target: Combatant) -> void:
	var key := who.combatant_name.to_lower()
	_bm.previous_round_actions[key] = [{
		"type": "attack",
		"target": target,
		"speed": 1.0,
	}]


func _count(who: Combatant) -> int:
	var n := 0
	for action in _bm.pending_actions:
		if action.get("combatant") == who:
			n += 1
	return n


func _stage(party: Array, enemy: Combatant, index: int) -> void:
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	_bm.all_combatants.clear()
	_bm.selection_order.clear()
	_bm.pending_actions.clear()
	_bm.execution_order.clear()
	_bm.previous_round_actions.clear()
	for member in party:
		_bm.player_party.append(member)
		_bm.all_combatants.append(member)
		_bm.selection_order.append(member)
		_remember_attack(member, enemy)
		if AutobattleSystem:
			AutobattleSystem.set_autobattle_enabled(_bm._get_character_id(member), false)
	_bm.enemy_party.append(enemy)
	_bm.all_combatants.append(enemy)
	_bm.selection_order.append(enemy)
	_bm.selection_index = index
	_bm.current_combatant = party[index]
	_bm.current_state = _bm.BattleState.PLAYER_SELECTING
	_bm.volatility = VolatilitySystem.new()
	_bm.volatility.reset_battle()


func test_repeat_on_the_first_menu_still_lets_the_enemy_act() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var ada := _make("Ada")
	var bo := _make("Bo")
	var slime := _make("Slime")
	add_child_autofree(ada)
	add_child_autofree(bo)
	add_child_autofree(slime)
	_stage([ada, bo], slime, 0)
	assert_true(_bm.repeat_previous_actions(), "repeat must accept a remembered round")
	assert_eq(_count(ada), 1, "the character whose menu was open gets one repeated action")
	assert_eq(_count(bo), 1, "a later ally who had not chosen yet gets exactly one repeated action")
	assert_gte(_count(slime), 1, "the enemy still selects after Repeat — the round does not skip them")


func test_repeat_after_someone_confirmed_does_not_give_them_a_second_action() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null:
		return
	var ada := _make("Ada")
	var bo := _make("Bo")
	var slime := _make("Slime")
	add_child_autofree(ada)
	add_child_autofree(bo)
	add_child_autofree(slime)
	_stage([ada, bo], slime, 1)
	# Ada already confirmed this round. Repeat is pressed on Bo's menu.
	_bm.pending_actions.append({
		"type": "attack",
		"combatant": ada,
		"target": slime,
		"speed": 1.0,
	})
	assert_true(_bm.repeat_previous_actions(), "repeat must accept a remembered round")
	assert_eq(_count(ada), 1, "a character who already chose this round must not act twice")
	assert_eq(_count(bo), 1, "the character whose menu was open gets one repeated action")
	assert_gte(_count(slime), 1, "the enemy still selects after Repeat — the round does not skip them")
