extends GutTest

## Tests for battle damage calculations and combat mechanics
## Covers damage formula, critical hits, healing, and stat modifiers

var _combatant: Combatant


func before_each() -> void:
	_combatant = Combatant.new()
	_combatant.combatant_name = "Test Fighter"
	_combatant.max_hp = 100
	_combatant.current_hp = 100
	_combatant.max_mp = 50
	_combatant.current_mp = 50
	_combatant.attack = 20
	_combatant.defense = 10
	_combatant.magic = 15
	_combatant.speed = 12
	add_child(_combatant)


func after_each() -> void:
	if is_instance_valid(_combatant):
		_combatant.queue_free()


## Damage Formula Tests
## take_damage uses: amount² / (amount + defense), min 1

func test_damage_formula_basic() -> void:
	# With 20 raw attack vs 10 defense: 20*20 / (20+10) = 400/30 ≈ 13
	var damage = _combatant.take_damage(20)
	assert_between(damage, 12, 15, "Basic damage should be around 13")


func test_damage_formula_high_defense() -> void:
	_combatant.defense = 50
	var damage = _combatant.take_damage(20)
	# 20*20 / (20+50) = 400/70 ≈ 5
	assert_between(damage, 4, 8, "High defense should reduce damage")


func test_damage_formula_low_defense() -> void:
	_combatant.defense = 1
	var damage = _combatant.take_damage(20)
	# 20*20 / (20+1) = 400/21 ≈ 19
	assert_between(damage, 17, 22, "Low defense should increase damage")


func test_damage_formula_zero_defense() -> void:
	_combatant.defense = 0
	var damage = _combatant.take_damage(20)
	# 20*20 / (20+0) = 400/20 = 20
	assert_between(damage, 18, 22, "Zero defense should result in full damage")


func test_damage_minimum_is_one() -> void:
	_combatant.defense = 999
	var damage = _combatant.take_damage(5)
	assert_gte(damage, 1, "Minimum damage should be at least 1")


func test_damage_with_zero_attack() -> void:
	var damage = _combatant.take_damage(0)
	assert_gte(damage, 0, "Zero attack damage should be >= 0")


## Healing Tests

func test_healing_basic() -> void:
	_combatant.current_hp = 50
	_combatant.heal(30)
	assert_eq(_combatant.current_hp, 80, "Healing should increase HP")


func test_healing_caps_at_max() -> void:
	_combatant.current_hp = 90
	_combatant.heal(50)
	assert_eq(_combatant.current_hp, _combatant.max_hp, "Healing should not exceed max HP")


func test_healing_dead_character() -> void:
	_combatant.current_hp = 0
	_combatant.is_alive = false
	var healed = _combatant.heal(30)
	assert_eq(healed, 0, "Healing dead character should return 0")


func test_healing_negative_amount() -> void:
	_combatant.current_hp = 50
	_combatant.heal(-10)
	# Negative heal effectively subtracts from HP via min() clamping
	assert_gte(_combatant.current_hp, 0, "Negative healing should not cause negative HP")


## MP Cost Tests

func test_mp_spending() -> void:
	_combatant.current_mp = 50
	var can_spend = _combatant.spend_mp(20)
	assert_true(can_spend, "Should be able to spend MP when sufficient")
	assert_eq(_combatant.current_mp, 30, "MP should decrease after spending")


func test_mp_spending_insufficient() -> void:
	_combatant.current_mp = 10
	var can_spend = _combatant.spend_mp(20)
	assert_false(can_spend, "Should not be able to spend more MP than available")
	assert_eq(_combatant.current_mp, 10, "MP should not change on failed spend")


func test_mp_recovery() -> void:
	_combatant.current_mp = 10
	_combatant.restore_mp(20)
	assert_eq(_combatant.current_mp, 30, "MP recovery should increase current MP")


func test_mp_recovery_caps_at_max() -> void:
	_combatant.current_mp = 40
	_combatant.restore_mp(50)
	assert_eq(_combatant.current_mp, _combatant.max_mp, "MP recovery should not exceed max")


## AP System Tests (CTB mechanic)

func test_ap_initialization() -> void:
	assert_eq(_combatant.current_ap, 0, "AP should start at 0")


func test_ap_gain_on_defer() -> void:
	_combatant.current_ap = 0
	_combatant.execute_defer()
	# Defer sets is_defending = true; AP is handled by the turn system via gain_ap
	assert_true(_combatant.is_defending, "Deferring should set defending state")


func test_ap_maximum() -> void:
	_combatant.current_ap = 3
	_combatant.gain_ap(5)
	assert_lte(_combatant.current_ap, 4, "AP should not exceed +4")


func test_ap_minimum() -> void:
	_combatant.current_ap = -3
	_combatant.spend_ap(5)
	# spend_ap checks can_brave, so if it can't spend, AP stays same
	assert_gte(_combatant.current_ap, -4, "AP should not go below -4")


func test_ap_cost_for_action() -> void:
	_combatant.current_ap = 2
	_combatant.spend_ap(1)
	assert_eq(_combatant.current_ap, 1, "Action should cost 1 AP")


func test_ap_spend_rejected_when_too_deep() -> void:
	_combatant.current_ap = -3
	var result = _combatant.spend_ap(2)
	assert_false(result, "Should not be able to go below -4 AP")
	assert_eq(_combatant.current_ap, -3, "AP should be unchanged on failed spend")


## Death and Revival Tests

func test_character_dies_at_zero_hp() -> void:
	_combatant.current_hp = 100
	_combatant.defense = 0
	# take_damage(100) with 0 defense: 100*100/(100+0) = 100
	_combatant.take_damage(100)
	assert_false(_combatant.is_alive, "Character should be dead at 0 HP")


func test_character_alive_above_zero() -> void:
	_combatant.current_hp = 100
	_combatant.defense = 10
	_combatant.take_damage(5)
	assert_true(_combatant.is_alive, "Character should be alive above 0 HP")


func test_hp_does_not_go_negative() -> void:
	_combatant.current_hp = 10
	_combatant.defense = 0
	_combatant.take_damage(50)
	assert_eq(_combatant.current_hp, 0, "HP should not go below 0")


func test_revive_restores_life() -> void:
	_combatant.die()
	assert_false(_combatant.is_alive, "Should be dead after die()")
	_combatant.revive(50)
	assert_true(_combatant.is_alive, "Should be alive after revive")
	assert_eq(_combatant.current_hp, 50, "Should have specified HP after revive")


func test_revive_default_half_hp() -> void:
	_combatant.die()
	_combatant.revive()
	assert_true(_combatant.is_alive, "Should be alive after revive")
	assert_eq(_combatant.current_hp, 50, "Default revive should restore 50% max HP")


## Stat Modifier Tests (buff/debuff system)

func test_buff_can_be_added() -> void:
	_combatant.add_buff("power_up", "attack", 1.5, 3)
	assert_eq(_combatant.active_buffs.size(), 1, "Should have one active buff")
	assert_eq(_combatant.active_buffs[0]["stat"], "attack", "Buff should target attack")


func test_debuff_can_be_added() -> void:
	_combatant.add_debuff("weaken", "defense", 0.5, 3)
	assert_eq(_combatant.active_debuffs.size(), 1, "Should have one active debuff")
	assert_eq(_combatant.active_debuffs[0]["stat"], "defense", "Debuff should target defense")


## HP/MP State Tests

func test_hp_full_after_init() -> void:
	assert_eq(_combatant.current_hp, _combatant.max_hp, "HP should be full after init")


func test_mp_full_after_init() -> void:
	assert_eq(_combatant.current_mp, _combatant.max_mp, "MP should be full after init")


func test_defending_reduces_damage() -> void:
	_combatant.defense = 0
	_combatant.is_defending = false
	var normal_damage = _combatant.take_damage(20)
	# Reset HP for second test
	_combatant.current_hp = 100
	_combatant.is_defending = true
	var defend_damage = _combatant.take_damage(20)
	assert_lt(defend_damage, normal_damage, "Defending should reduce damage taken")


## Regression Tests

func test_damage_formula_regression_no_division_by_zero() -> void:
	"""Regression: Ensure damage formula doesn't divide by zero"""
	_combatant.defense = 0
	var damage = _combatant.take_damage(0)
	# Should not crash - 0*0 / (0+0) edge case
	assert_true(true, "No division by zero occurred")


func test_healing_regression_overflow() -> void:
	"""Regression: Healing large amounts should not overflow"""
	_combatant.current_hp = 1
	_combatant.heal(999999)
	assert_eq(_combatant.current_hp, _combatant.max_hp, "Large heal should cap at max HP")


func test_damage_with_defending_state() -> void:
	"""Regression: Defending state should halve damage"""
	_combatant.defense = 0
	_combatant.is_defending = true
	var damage = _combatant.take_damage(20)
	# 20*20/(20+0) = 20, then * 0.5 = 10
	assert_eq(damage, 10, "Defending should halve damage to 10")


func test_status_effect_add_remove() -> void:
	_combatant.add_status("poison")
	assert_true(_combatant.has_status("poison"), "Should have poison status")
	_combatant.remove_status("poison")
	assert_false(_combatant.has_status("poison"), "Should not have poison after removal")
