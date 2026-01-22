extends GutTest

## Regression tests for Combatant class
## Tests HP/MP calculations, status effects, and combat mechanics

const Combatant = preload("res://src/battle/Combatant.gd")

var _combatant: Combatant


func before_each() -> void:
	_combatant = Combatant.new()
	_combatant.combatant_name = "Test Fighter"
	_combatant.max_hp = 100
	_combatant.current_hp = 100
	_combatant.max_mp = 50
	_combatant.current_mp = 50
	add_child_autofree(_combatant)


func test_combatant_initialization() -> void:
	assert_eq(_combatant.combatant_name, "Test Fighter")
	assert_eq(_combatant.max_hp, 100)
	assert_eq(_combatant.current_hp, 100)


func test_hp_percentage_full() -> void:
	# Full HP should return 100
	var hp_pct = _combatant.get_hp_percentage()
	assert_eq(hp_pct, 100.0, "Full HP should be 100%")


func test_hp_percentage_half() -> void:
	# Half HP should return 50
	_combatant.current_hp = 50
	var hp_pct = _combatant.get_hp_percentage()
	assert_eq(hp_pct, 50.0, "Half HP should be 50%")


func test_hp_percentage_zero() -> void:
	# Zero HP should return 0
	_combatant.current_hp = 0
	var hp_pct = _combatant.get_hp_percentage()
	assert_eq(hp_pct, 0.0, "Zero HP should be 0%")


func test_mp_percentage_full() -> void:
	var mp_pct = _combatant.get_mp_percentage()
	assert_eq(mp_pct, 100.0, "Full MP should be 100%")


func test_mp_percentage_partial() -> void:
	_combatant.current_mp = 25
	var mp_pct = _combatant.get_mp_percentage()
	assert_eq(mp_pct, 50.0, "Half MP should be 50%")


func test_is_alive_when_hp_positive() -> void:
	assert_true(_combatant.is_alive, "Combatant with HP > 0 should be alive")


func test_is_dead_when_hp_zero() -> void:
	_combatant.current_hp = 0
	assert_false(_combatant.is_alive, "Combatant with HP = 0 should be dead")


func test_take_damage_reduces_hp() -> void:
	_combatant.take_damage(30)
	assert_eq(_combatant.current_hp, 70, "Taking 30 damage from 100 HP should leave 70 HP")


func test_take_damage_caps_at_zero() -> void:
	_combatant.take_damage(150)  # More than max HP
	assert_eq(_combatant.current_hp, 0, "HP should not go below 0")


func test_heal_increases_hp() -> void:
	_combatant.current_hp = 50
	_combatant.heal(30)
	assert_eq(_combatant.current_hp, 80, "Healing 30 HP from 50 should give 80 HP")


func test_heal_caps_at_max() -> void:
	_combatant.current_hp = 90
	_combatant.heal(50)  # More than needed
	assert_eq(_combatant.current_hp, 100, "HP should not exceed max_hp")


func test_consume_mp_reduces_mp() -> void:
	var result = _combatant.consume_mp(20)
	assert_true(result, "Should be able to consume MP")
	assert_eq(_combatant.current_mp, 30, "Consuming 20 MP from 50 should leave 30")


func test_consume_mp_fails_when_insufficient() -> void:
	var result = _combatant.consume_mp(100)  # More than available
	assert_false(result, "Should not consume MP when insufficient")
	assert_eq(_combatant.current_mp, 50, "MP should be unchanged on failed consume")


func test_restore_mp_increases_mp() -> void:
	_combatant.current_mp = 20
	_combatant.restore_mp(15)
	assert_eq(_combatant.current_mp, 35, "Restoring 15 MP from 20 should give 35")


func test_restore_mp_caps_at_max() -> void:
	_combatant.current_mp = 45
	_combatant.restore_mp(20)
	assert_eq(_combatant.current_mp, 50, "MP should not exceed max_mp")


func test_status_effects_array_exists() -> void:
	assert_typeof(_combatant.status_effects, TYPE_ARRAY, "status_effects should be an Array")


func test_initial_ap_is_zero() -> void:
	assert_eq(_combatant.current_ap, 0, "Initial AP should be 0")


func test_can_have_multiple_status_effects() -> void:
	_combatant.status_effects.append("poison")
	_combatant.status_effects.append("slow")
	assert_eq(_combatant.status_effects.size(), 2, "Should have 2 status effects")
	assert_true("poison" in _combatant.status_effects, "Should have poison")
	assert_true("slow" in _combatant.status_effects, "Should have slow")
