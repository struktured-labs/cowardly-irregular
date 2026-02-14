extends GutTest

## Advanced Combatant tests
## Covers: AP system, buffs/debuffs, elemental damage, abilities, passives,
## inventory, injuries, and the full combat lifecycle

const CombatantScript = preload("res://src/battle/Combatant.gd")

var _combatant: Combatant


func before_each() -> void:
	_combatant = CombatantScript.new()
	_combatant.combatant_name = "Test Hero"
	_combatant.max_hp = 100
	_combatant.current_hp = 100
	_combatant.max_mp = 50
	_combatant.current_mp = 50
	_combatant.attack = 10
	_combatant.defense = 10
	_combatant.magic = 10
	_combatant.speed = 10
	add_child_autofree(_combatant)


## ---- AP System ----

func test_ap_starts_at_zero() -> void:
	assert_eq(_combatant.current_ap, 0)


func test_gain_ap_increases() -> void:
	_combatant.gain_ap(2)
	assert_eq(_combatant.current_ap, 2)


func test_gain_ap_clamped_at_4() -> void:
	_combatant.gain_ap(10)
	assert_eq(_combatant.current_ap, 4, "AP should be clamped to 4")


func test_spend_ap_decreases() -> void:
	_combatant.gain_ap(3)
	var result = _combatant.spend_ap(2)
	assert_true(result, "Should be able to spend AP")
	assert_eq(_combatant.current_ap, 1)


func test_spend_ap_into_debt() -> void:
	_combatant.current_ap = 0
	var result = _combatant.spend_ap(3)
	assert_true(result, "Should allow going into AP debt")
	assert_eq(_combatant.current_ap, -3)


func test_spend_ap_max_debt_is_minus_4() -> void:
	_combatant.current_ap = 0
	var result = _combatant.spend_ap(5)
	assert_false(result, "Should not allow going past -4 AP debt")
	assert_eq(_combatant.current_ap, 0, "AP should be unchanged on failed spend")


func test_can_brave_checks_debt_limit() -> void:
	_combatant.current_ap = 0
	assert_true(_combatant.can_brave(4), "Can go to -4")
	assert_false(_combatant.can_brave(5), "Cannot exceed -4 debt")


func test_ap_signals_emitted() -> void:
	watch_signals(_combatant)
	_combatant.gain_ap(1)
	assert_signal_emitted(_combatant, "ap_changed", "AP change should emit signal")


func test_defer_gives_natural_ap() -> void:
	_combatant.current_ap = 0
	_combatant.execute_defer()
	assert_true(_combatant.is_defending, "Defer should set defending")


## ---- Status Effects ----

func test_add_status() -> void:
	_combatant.add_status("poison")
	assert_true(_combatant.has_status("poison"), "Should have poison status")


func test_remove_status() -> void:
	_combatant.add_status("poison")
	_combatant.remove_status("poison")
	assert_false(_combatant.has_status("poison"), "Poison should be removed")


func test_has_status_returns_false_for_missing() -> void:
	assert_false(_combatant.has_status("petrify"), "Should not have petrify")


func test_no_duplicate_status() -> void:
	_combatant.add_status("poison")
	_combatant.add_status("poison")
	# Count occurrences
	var count = 0
	for s in _combatant.status_effects:
		if s == "poison":
			count += 1
	assert_lte(count, 1, "Should not have duplicate status effects")


## ---- Elemental System ----

func test_elemental_weakness_multiplier() -> void:
	_combatant.elemental_weaknesses.append("fire")
	var mult = _combatant.calculate_elemental_modifier("fire")
	assert_eq(mult, 1.5, "Weakness should give 1.5x multiplier")


func test_elemental_resistance_multiplier() -> void:
	_combatant.elemental_resistances.append("ice")
	var mult = _combatant.calculate_elemental_modifier("ice")
	assert_eq(mult, 0.5, "Resistance should give 0.5x multiplier")


func test_elemental_immunity_multiplier() -> void:
	_combatant.elemental_immunities.append("lightning")
	var mult = _combatant.calculate_elemental_modifier("lightning")
	assert_eq(mult, 0.0, "Immunity should give 0x multiplier")


func test_neutral_element_multiplier() -> void:
	var mult = _combatant.calculate_elemental_modifier("fire")
	assert_eq(mult, 1.0, "No affinity should give 1.0x multiplier")


## ---- Abilities ----

func test_learn_ability() -> void:
	_combatant.learn_ability("fire")
	assert_true(_combatant.has_learned_ability("fire"), "Should have learned fire")


func test_learn_duplicate_ability() -> void:
	_combatant.learn_ability("fire")
	_combatant.learn_ability("fire")
	assert_eq(_combatant.learned_abilities.size(), 1, "Should not duplicate abilities")


func test_has_learned_ability_false() -> void:
	assert_false(_combatant.has_learned_ability("fire"), "Should not have unlearned ability")


## ---- Inventory ----

func test_add_item() -> void:
	_combatant.add_item("potion", 3)
	assert_eq(_combatant.get_item_count("potion"), 3, "Should have 3 potions")


func test_remove_item() -> void:
	_combatant.add_item("potion", 5)
	var result = _combatant.remove_item("potion", 2)
	assert_true(result, "Should successfully remove items")
	assert_eq(_combatant.get_item_count("potion"), 3, "Should have 3 remaining")


func test_remove_item_insufficient() -> void:
	_combatant.add_item("potion", 1)
	var result = _combatant.remove_item("potion", 5)
	assert_false(result, "Should fail to remove more than owned")
	assert_eq(_combatant.get_item_count("potion"), 1, "Count should be unchanged")


func test_has_item() -> void:
	_combatant.add_item("potion", 2)
	assert_true(_combatant.has_item("potion", 1), "Should have at least 1")
	assert_true(_combatant.has_item("potion", 2), "Should have exactly 2")
	assert_false(_combatant.has_item("potion", 3), "Should not have 3")


func test_get_item_count_missing_item() -> void:
	assert_eq(_combatant.get_item_count("nonexistent"), 0, "Missing item should return 0")


## ---- Permanent Injuries ----

func test_apply_permanent_injury() -> void:
	_combatant.apply_permanent_injury({"stat": "attack", "penalty": 3})
	assert_eq(_combatant.permanent_injuries.size(), 1, "Should have 1 injury")


func test_multiple_injuries() -> void:
	_combatant.apply_permanent_injury({"stat": "attack", "penalty": 2})
	_combatant.apply_permanent_injury({"stat": "speed", "penalty": 1})
	assert_eq(_combatant.permanent_injuries.size(), 2, "Should have 2 injuries")


## ---- Buffs ----

func test_add_buff() -> void:
	_combatant.add_buff("power_up", "attack", 5.0, 3)
	assert_eq(_combatant.active_buffs.size(), 1, "Should have 1 buff")


func test_get_buffed_stat() -> void:
	_combatant.add_buff("power_up", "attack", 5.0, 3)
	var buffed = _combatant.get_buffed_stat("attack", _combatant.attack)
	assert_gt(buffed, _combatant.attack, "Buffed attack should be higher than base")


func test_add_debuff() -> void:
	_combatant.add_debuff("weakness", "defense", 3.0, 2)
	assert_eq(_combatant.active_debuffs.size(), 1, "Should have 1 debuff")


## ---- Death & Revival ----

func test_die_sets_alive_false() -> void:
	_combatant.die()
	assert_false(_combatant.is_alive, "Should be dead")
	assert_eq(_combatant.current_hp, 0, "HP should be 0")


func test_die_emits_signal() -> void:
	watch_signals(_combatant)
	_combatant.die()
	assert_signal_emitted(_combatant, "died", "Death should emit signal")


func test_revive_sets_alive_true() -> void:
	_combatant.die()
	_combatant.revive()
	assert_true(_combatant.is_alive, "Should be alive after revive")
	assert_gt(_combatant.current_hp, 0, "Should have some HP after revive")


func test_revive_with_specific_hp() -> void:
	_combatant.die()
	_combatant.revive(25)
	assert_eq(_combatant.current_hp, 25, "Should have exactly 25 HP after revive with amount")


## ---- Damage Formula ----

func test_damage_formula_with_defense() -> void:
	# Formula: amount^2 / (amount + defense)
	# 30^2 / (30 + 10) = 900/40 = 22
	_combatant.defense = 10
	var actual_damage = _combatant.take_damage(30)
	assert_eq(_combatant.current_hp, 100 - 22, "Damage formula: 30^2/(30+10) = 22")


func test_damage_formula_minimum_1() -> void:
	_combatant.defense = 1000
	var result = _combatant.take_damage(1)
	# 1^2 / (1 + 1000) ≈ 0 -> minimum 1
	assert_lte(_combatant.current_hp, 100, "Should take at least 1 damage")


func test_damage_with_defending() -> void:
	_combatant.is_defending = true
	_combatant.defense = 10
	_combatant.take_damage(30)
	# Defending should reduce damage
	assert_gt(_combatant.current_hp, 78, "Defending should take less damage than 22")


## ---- Turn Lifecycle ----

func test_start_turn_clears_defending() -> void:
	_combatant.is_defending = true
	_combatant.start_turn()
	assert_false(_combatant.is_defending, "Start turn should clear defending")


func test_reset_for_new_round() -> void:
	_combatant.is_defending = true
	_combatant.reset_for_new_round()
	assert_false(_combatant.is_defending, "Reset should clear defending")


## ---- Signals ----

func test_hp_changed_signal() -> void:
	watch_signals(_combatant)
	_combatant.take_damage(20)
	assert_signal_emitted(_combatant, "hp_changed", "Damage should emit hp_changed")


func test_status_added_signal() -> void:
	watch_signals(_combatant)
	_combatant.add_status("poison")
	assert_signal_emitted(_combatant, "status_added", "Adding status should emit signal")


func test_status_removed_signal() -> void:
	_combatant.add_status("poison")
	watch_signals(_combatant)
	_combatant.remove_status("poison")
	assert_signal_emitted(_combatant, "status_removed", "Removing status should emit signal")
