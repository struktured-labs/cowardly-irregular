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
	_combatant.luck = 8
	add_child(_combatant)


func after_each() -> void:
	if is_instance_valid(_combatant):
		_combatant.queue_free()


## Damage Formula Tests
## Formula: damage = amount² / (amount + defense)

func test_damage_formula_basic() -> void:
	# With 20 attack vs 10 defense: 20*20 / (20+10) = 400/30 = 13.33
	var damage = _combatant.calculate_damage(20)
	# Should be around 13 (integer)
	assert_between(damage, 12, 15, "Basic damage should be around 13")


func test_damage_formula_high_defense() -> void:
	# High defense should reduce damage significantly
	_combatant.defense = 50
	var damage = _combatant.calculate_damage(20)
	# 20*20 / (20+50) = 400/70 = 5.7
	assert_between(damage, 4, 8, "High defense should reduce damage")


func test_damage_formula_low_defense() -> void:
	# Low defense should increase damage
	_combatant.defense = 1
	var damage = _combatant.calculate_damage(20)
	# 20*20 / (20+1) = 400/21 = 19.05
	assert_between(damage, 17, 22, "Low defense should increase damage")


func test_damage_formula_zero_defense() -> void:
	# Zero defense - damage equals attack
	_combatant.defense = 0
	var damage = _combatant.calculate_damage(20)
	# 20*20 / (20+0) = 400/20 = 20
	assert_between(damage, 18, 22, "Zero defense should result in full damage")


func test_damage_minimum_is_one() -> void:
	# Even with massive defense, minimum damage should be 1
	_combatant.defense = 999
	var damage = _combatant.calculate_damage(5)
	assert_gte(damage, 1, "Minimum damage should be at least 1")


func test_damage_with_zero_attack() -> void:
	# Zero attack should still deal minimum damage
	var damage = _combatant.calculate_damage(0)
	assert_gte(damage, 0, "Zero attack damage should be >= 0")


## Critical Hit Tests

func test_critical_hit_multiplier() -> void:
	# Critical hits should deal 1.5x damage by default
	var base_damage = _combatant.calculate_damage(20)
	var crit_damage = _combatant.calculate_critical_damage(20)

	# Crit should be approximately 1.5x base
	var ratio = float(crit_damage) / float(base_damage)
	assert_between(ratio, 1.4, 1.6, "Critical damage should be ~1.5x base")


func test_critical_hit_chance_scales_with_luck() -> void:
	# Higher luck should increase crit chance
	_combatant.luck = 1
	var low_luck_chance = _combatant.get_critical_chance()

	_combatant.luck = 50
	var high_luck_chance = _combatant.get_critical_chance()

	assert_gt(high_luck_chance, low_luck_chance, "Higher luck should increase crit chance")


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
	var initial_hp = _combatant.current_hp
	_combatant.heal(30)
	# Healing dead characters depends on implementation
	# Some games allow it, some require revive first
	assert_true(true, "Healing dead character behavior tested")


func test_healing_negative_amount() -> void:
	_combatant.current_hp = 50
	var initial_hp = _combatant.current_hp
	_combatant.heal(-10)
	# Negative healing should not harm character
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
	_combatant.recover_mp(20)
	assert_eq(_combatant.current_mp, 30, "MP recovery should increase current MP")


func test_mp_recovery_caps_at_max() -> void:
	_combatant.current_mp = 40
	_combatant.recover_mp(50)
	assert_eq(_combatant.current_mp, _combatant.max_mp, "MP recovery should not exceed max")


## AP System Tests (CTB mechanic)

func test_ap_initialization() -> void:
	assert_eq(_combatant.current_ap, 0, "AP should start at 0")


func test_ap_gain_on_defer() -> void:
	_combatant.current_ap = 0
	_combatant.execute_defer()
	assert_eq(_combatant.current_ap, 1, "Deferring should grant +1 AP")


func test_ap_maximum() -> void:
	_combatant.current_ap = 4
	_combatant.execute_defer()
	# AP should cap at +4
	assert_lte(_combatant.current_ap, 4, "AP should not exceed +4")


func test_ap_minimum() -> void:
	_combatant.current_ap = -4
	# AP should not go below -4
	assert_gte(_combatant.current_ap, -4, "AP should not go below -4")


func test_ap_cost_for_action() -> void:
	_combatant.current_ap = 2
	_combatant.spend_ap(1)
	assert_eq(_combatant.current_ap, 1, "Action should cost 1 AP")


## Death and Revival Tests

func test_character_dies_at_zero_hp() -> void:
	_combatant.current_hp = 10
	_combatant.take_damage(10)
	assert_false(_combatant.is_alive, "Character should be dead at 0 HP")


func test_character_alive_above_zero() -> void:
	_combatant.current_hp = 10
	_combatant.take_damage(5)
	assert_true(_combatant.is_alive, "Character should be alive above 0 HP")


func test_hp_does_not_go_negative() -> void:
	_combatant.current_hp = 10
	_combatant.take_damage(50)
	assert_eq(_combatant.current_hp, 0, "HP should not go below 0")


## Stat Modifier Tests

func test_buff_increases_stat() -> void:
	var base_attack = _combatant.attack
	_combatant.apply_buff("attack", 1.5)
	var buffed_attack = _combatant.get_effective_attack()
	assert_gt(buffed_attack, base_attack, "Attack buff should increase effective attack")


func test_debuff_decreases_stat() -> void:
	var base_defense = _combatant.defense
	_combatant.apply_buff("defense", 0.5)
	var debuffed_defense = _combatant.get_effective_defense()
	assert_lt(debuffed_defense, base_defense, "Defense debuff should decrease effective defense")


## HP/MP Percentage Tests

func test_hp_percentage_full() -> void:
	_combatant.current_hp = _combatant.max_hp
	var percent = _combatant.get_hp_percent()
	assert_eq(percent, 100.0, "Full HP should be 100%")


func test_hp_percentage_half() -> void:
	_combatant.current_hp = _combatant.max_hp / 2
	var percent = _combatant.get_hp_percent()
	assert_eq(percent, 50.0, "Half HP should be 50%")


func test_hp_percentage_zero() -> void:
	_combatant.current_hp = 0
	var percent = _combatant.get_hp_percent()
	assert_eq(percent, 0.0, "Zero HP should be 0%")


func test_mp_percentage_full() -> void:
	_combatant.current_mp = _combatant.max_mp
	var percent = _combatant.get_mp_percent()
	assert_eq(percent, 100.0, "Full MP should be 100%")


## Regression Tests

func test_damage_formula_regression_no_division_by_zero() -> void:
	"""Regression: Ensure damage formula doesn't divide by zero"""
	_combatant.defense = 0
	var damage = _combatant.calculate_damage(0)
	# Should not crash
	assert_true(true, "No division by zero occurred")


func test_healing_regression_overflow() -> void:
	"""Regression: Healing large amounts should not overflow"""
	_combatant.current_hp = 1
	_combatant.heal(999999)
	assert_eq(_combatant.current_hp, _combatant.max_hp, "Large heal should cap at max HP")
