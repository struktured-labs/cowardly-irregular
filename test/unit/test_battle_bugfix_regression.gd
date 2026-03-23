extends GutTest

## Regression tests for Phase 1 critical battle bug fixes (commit 3d364ad)
## Each test verifies a specific bug that was found and fixed during the
## battle system audit. If any of these fail, the corresponding fix has regressed.

const Combatant = preload("res://src/battle/Combatant.gd")

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
	add_child_autofree(_combatant)


# ---- Bug: take_damage() had no dead-combatant guard (double-kill) ----

func test_take_damage_on_dead_combatant_returns_zero() -> void:
	# Kill the combatant first
	_combatant.current_hp = 0
	_combatant.is_alive = false

	# Attempting damage on dead combatant should return 0
	var damage = _combatant.take_damage(50)
	assert_eq(damage, 0, "Dead combatant should take 0 damage")


func test_take_damage_dead_guard_prevents_double_die_signal() -> void:
	var die_count = 0
	_combatant.died.connect(func(): die_count += 1)

	# Deal lethal damage
	_combatant.current_hp = 1
	_combatant.take_damage(999)
	assert_eq(die_count, 1, "First lethal hit should emit died once")

	# Second hit on dead combatant should NOT emit died again
	_combatant.take_damage(999)
	assert_eq(die_count, 1, "Second hit on dead combatant should not emit died again")


# ---- Bug: Defense debuffs (Armor Break) had no effect ----

func test_defense_debuff_increases_damage_taken() -> void:
	# Baseline damage with no debuffs
	_combatant.current_hp = 100
	var damage_normal = _combatant.take_damage(30)

	# Reset HP, apply Armor Break debuff (halve defense)
	_combatant.current_hp = 100
	_combatant.add_debuff("Armor Break", "defense", 0.5, 3)
	var damage_debuffed = _combatant.take_damage(30)

	assert_gt(damage_debuffed, damage_normal,
		"Armor Break debuff should increase damage taken (got %d vs %d normal)" % [damage_debuffed, damage_normal])


func test_defense_buff_reduces_damage_taken() -> void:
	# Baseline damage with no buffs
	_combatant.current_hp = 100
	var damage_normal = _combatant.take_damage(30)

	# Reset HP, apply Protect buff (double defense)
	_combatant.current_hp = 100
	_combatant.add_buff("Protect", "defense", 2.0, 3)
	var damage_buffed = _combatant.take_damage(30)

	assert_lt(damage_buffed, damage_normal,
		"Protect buff should reduce damage taken (got %d vs %d normal)" % [damage_buffed, damage_normal])


# ---- Bug: Buffs/debuffs never expired (end_turn never called) ----

func test_buff_expires_after_duration() -> void:
	_combatant.add_buff("Protect", "defense", 2.0, 2)
	assert_eq(_combatant.active_buffs.size(), 1, "Should have 1 buff")

	# Tick once — 1 turn remaining
	_combatant.update_buff_durations()
	assert_eq(_combatant.active_buffs.size(), 1, "Buff should still be active after 1 tick")

	# Tick again — should expire
	_combatant.update_buff_durations()
	assert_eq(_combatant.active_buffs.size(), 0, "Buff should expire after 2 ticks (duration was 2)")


func test_debuff_expires_after_duration() -> void:
	_combatant.add_debuff("Armor Break", "defense", 0.5, 1)
	assert_eq(_combatant.active_debuffs.size(), 1, "Should have 1 debuff")

	# Tick once — should expire immediately (duration 1)
	_combatant.update_buff_durations()
	assert_eq(_combatant.active_debuffs.size(), 0, "Debuff with duration 1 should expire after 1 tick")


func test_doom_countdown_kills_at_zero() -> void:
	var die_count = 0
	_combatant.died.connect(func(): die_count += 1)
	_combatant.doom_counter = 2

	_combatant.update_buff_durations()
	assert_eq(_combatant.doom_counter, 1, "Doom should tick down to 1")
	assert_eq(die_count, 0, "Should not die yet")

	_combatant.update_buff_durations()
	assert_eq(_combatant.doom_counter, 0, "Doom should tick down to 0")
	assert_eq(die_count, 1, "Combatant should die when doom reaches 0")


# ---- Bug: get_buffed_stat was not used for attack in basic attacks ----

func test_get_buffed_stat_applies_attack_buff() -> void:
	var base = _combatant.get_buffed_stat("attack", _combatant.attack)
	assert_eq(base, 20, "Base attack should be 20 with no buffs")

	_combatant.add_buff("Berserk", "attack", 1.5, 3)
	var buffed = _combatant.get_buffed_stat("attack", _combatant.attack)
	assert_eq(buffed, 30, "Buffed attack should be 30 (20 * 1.5)")


func test_get_buffed_stat_applies_defense_debuff() -> void:
	var base = _combatant.get_buffed_stat("defense", _combatant.defense)
	assert_eq(base, 10, "Base defense should be 10 with no debuffs")

	_combatant.add_debuff("Armor Break", "defense", 0.5, 3)
	var debuffed = _combatant.get_buffed_stat("defense", _combatant.defense)
	assert_eq(debuffed, 5, "Debuffed defense should be 5 (10 * 0.5)")


# ---- Bug: AP advance over-spend ----

func test_ap_spend_returns_false_at_floor() -> void:
	_combatant.current_ap = -4
	var result = _combatant.spend_ap(1)
	assert_false(result, "Cannot spend AP when already at floor (-4)")


func test_ap_gain_clamped_at_ceiling() -> void:
	_combatant.current_ap = 4
	_combatant.gain_ap(1)
	assert_eq(_combatant.current_ap, 4, "AP should not exceed 4")


func test_advance_ap_cost_calculation() -> void:
	# With 2 AP, a 3-action advance should cost 2 net AP (3 - 1 natural gain offset)
	_combatant.current_ap = 2
	assert_true(_combatant.can_brave(2), "Should be able to brave 2 AP from AP=2")
	_combatant.spend_ap(2)
	assert_eq(_combatant.current_ap, 0, "AP should be 0 after spending 2")


# ---- Data: Boss resistances should be explicit element lists, not "all" ----

func test_boss_resistances_no_all_string() -> void:
	var file = FileAccess.open("res://data/monsters.json", FileAccess.READ)
	assert_not_null(file, "monsters.json should exist")
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	assert_eq(err, OK, "monsters.json should parse")

	var monsters = json.data
	for monster_id in monsters:
		var monster = monsters[monster_id]
		if monster.has("resistances"):
			for r in monster["resistances"]:
				assert_ne(r, "all",
					"Monster '%s' has 'all' resistance string — must use explicit element list" % monster_id)


# ---- Data: All jobs should have evolution blocks ----

func test_all_jobs_have_evolution_block() -> void:
	var file = FileAccess.open("res://data/jobs.json", FileAccess.READ)
	assert_not_null(file, "jobs.json should exist")
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	assert_eq(err, OK, "jobs.json should parse")

	var jobs = json.data
	for job_id in jobs:
		var job = jobs[job_id]
		assert_has(job, "evolution",
			"Job '%s' is missing 'evolution' block — will crash on job[\"evolution\"][\"target\"]" % job_id)


# ===========================================================================
# Phase 2 regression tests (commit c7ee479)
# ===========================================================================

# ---- Bug: Buffs stacked infinitely with no cap or refresh ----

func test_duplicate_buff_refreshes_instead_of_stacking() -> void:
	_combatant.add_buff("Protect", "defense", 2.0, 3)
	assert_eq(_combatant.active_buffs.size(), 1, "Should have 1 buff")

	# Adding same effect again should refresh, not stack
	_combatant.add_buff("Protect", "defense", 2.0, 5)
	assert_eq(_combatant.active_buffs.size(), 1,
		"Duplicate buff should refresh, not stack (got %d buffs)" % _combatant.active_buffs.size())
	assert_eq(_combatant.active_buffs[0]["remaining_turns"], 5,
		"Refreshed buff should have new duration")


func test_duplicate_debuff_refreshes_instead_of_stacking() -> void:
	_combatant.add_debuff("Armor Break", "defense", 0.5, 2)
	assert_eq(_combatant.active_debuffs.size(), 1, "Should have 1 debuff")

	_combatant.add_debuff("Armor Break", "defense", 0.5, 4)
	assert_eq(_combatant.active_debuffs.size(), 1,
		"Duplicate debuff should refresh, not stack")
	assert_eq(_combatant.active_debuffs[0]["remaining_turns"], 4,
		"Refreshed debuff should have new duration")


func test_stronger_buff_upgrades_modifier() -> void:
	_combatant.add_buff("Berserk", "attack", 1.5, 3)
	_combatant.add_buff("Berserk", "attack", 2.0, 3)
	assert_eq(_combatant.active_buffs.size(), 1, "Should still be 1 buff")
	assert_eq(_combatant.active_buffs[0]["modifier"], 2.0,
		"Stronger buff should upgrade modifier")


func test_weaker_buff_does_not_downgrade_modifier() -> void:
	_combatant.add_buff("Berserk", "attack", 2.0, 3)
	_combatant.add_buff("Berserk", "attack", 1.5, 5)
	assert_eq(_combatant.active_buffs[0]["modifier"], 2.0,
		"Weaker buff should not downgrade modifier")
	assert_eq(_combatant.active_buffs[0]["remaining_turns"], 5,
		"Duration should still refresh even if modifier is not upgraded")


# ---- Bug: get_buffed_stat had no cap ----

func test_buffed_stat_capped_at_4x() -> void:
	# Stack multiple different buffs to try to exceed 4x
	# With refresh-on-duplicate, we need different effect names
	_combatant.add_buff("Berserk", "attack", 3.0, 5)
	_combatant.add_buff("War Cry", "attack", 3.0, 5)
	# 20 * 3.0 * 3.0 = 180, but cap is 4x base = 80
	var buffed = _combatant.get_buffed_stat("attack", _combatant.attack)
	assert_true(buffed <= _combatant.attack * 4,
		"Buffed stat should not exceed 4x base (got %d, max %d)" % [buffed, _combatant.attack * 4])


func test_debuffed_stat_floored_at_25_percent() -> void:
	_combatant.add_debuff("Weaken", "attack", 0.1, 5)
	# 20 * 0.1 = 2, but floor is 0.25x base = 5
	var debuffed = _combatant.get_buffed_stat("attack", _combatant.attack)
	assert_true(debuffed >= int(_combatant.attack * 0.25),
		"Debuffed stat should not go below 25%% base (got %d, min %d)" % [debuffed, int(_combatant.attack * 0.25)])


func test_buffed_stat_minimum_is_one() -> void:
	# Combatant with very low base stat + debuff
	_combatant.defense = 1
	_combatant.add_debuff("Shatter", "defense", 0.1, 5)
	var debuffed = _combatant.get_buffed_stat("defense", _combatant.defense)
	assert_true(debuffed >= 1, "Buffed stat should never go below 1")


# ---- Bug: restore_mp/spend_mp had no dead-combatant guard ----

func test_restore_mp_on_dead_combatant_returns_zero() -> void:
	_combatant.current_hp = 0
	_combatant.is_alive = false
	var restored = _combatant.restore_mp(20)
	assert_eq(restored, 0, "Dead combatant should not restore MP")


func test_spend_mp_on_dead_combatant_returns_false() -> void:
	_combatant.current_hp = 0
	_combatant.is_alive = false
	var result = _combatant.spend_mp(10)
	assert_false(result, "Dead combatant should not spend MP")


# ---- Bug: Volatility starting bands only had 2 tiers ----

func test_volatility_starting_bands() -> void:
	var VolatilitySystem = preload("res://src/battle/VolatilitySystem.gd")
	var vol = VolatilitySystem.new()

	# Low macro → STABLE
	vol.macro_volatility = 0.2
	vol.reset_battle()
	assert_eq(vol.get_band_name(), "Stable", "Low macro should start STABLE")

	# Medium macro → SHIFTING
	vol.macro_volatility = 0.5
	vol.reset_battle()
	assert_eq(vol.get_band_name(), "Shifting", "Medium macro should start SHIFTING")

	# High macro → UNSTABLE
	vol.macro_volatility = 0.8
	vol.reset_battle()
	assert_eq(vol.get_band_name(), "Unstable", "High macro should start UNSTABLE")

	# Very high macro → FRACTURED
	vol.macro_volatility = 0.95
	vol.reset_battle()
	assert_eq(vol.get_band_name(), "Fractured", "Very high macro should start FRACTURED")


# ===========================================================================
# Phase 3 regression tests (commit 85bace6) + Feature tests (c44250f, 0b64069)
# ===========================================================================

# ---- Balance: backstab no longer strictly superior to power_strike ----

func test_backstab_costs_more_than_power_strike() -> void:
	var file = FileAccess.open("res://data/abilities.json", FileAccess.READ)
	assert_not_null(file, "abilities.json should exist")
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	assert_eq(err, OK, "abilities.json should parse")
	var abilities = json.data

	var backstab = abilities.get("backstab", {})
	var power_strike = abilities.get("power_strike", {})
	assert_gt(backstab.get("mp_cost", 0), power_strike.get("mp_cost", 0),
		"Backstab should cost more MP than power_strike to offset crit advantage")


func test_drain_life_not_full_drain() -> void:
	var file = FileAccess.open("res://data/abilities.json", FileAccess.READ)
	assert_not_null(file, "abilities.json should exist")
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	assert_eq(err, OK, "abilities.json should parse")
	var abilities = json.data

	var drain_life = abilities.get("drain_life", {})
	assert_true(drain_life.get("drain_percentage", 100) <= 50,
		"drain_life should drain at most 50%% (got %d)" % drain_life.get("drain_percentage", 100))


func test_absorb_meaning_is_support_type() -> void:
	var file = FileAccess.open("res://data/abilities.json", FileAccess.READ)
	assert_not_null(file, "abilities.json should exist")
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	assert_eq(err, OK, "abilities.json should parse")
	var abilities = json.data

	var absorb = abilities.get("absorb_meaning", {})
	assert_eq(absorb.get("type", ""), "support",
		"absorb_meaning should be support type (was magic with 0 damage)")


# ---- Balance: mug should be reachable via rogue ----

func test_mug_in_rogue_abilities() -> void:
	var file = FileAccess.open("res://data/jobs.json", FileAccess.READ)
	assert_not_null(file, "jobs.json should exist")
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	assert_eq(err, OK, "jobs.json should parse")
	var jobs = json.data

	var rogue = jobs.get("rogue", {})
	var abilities = rogue.get("abilities", [])
	assert_true("mug" in abilities, "Rogue should have 'mug' in abilities list")


# ---- Balance: mushroom/fungoid name dedup ----

func test_mushroom_fungoid_distinct_names() -> void:
	var file = FileAccess.open("res://data/monsters.json", FileAccess.READ)
	assert_not_null(file, "monsters.json should exist")
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	assert_eq(err, OK, "monsters.json should parse")
	var monsters = json.data

	var mushroom_name = monsters.get("mushroom", {}).get("name", "")
	var fungoid_name = monsters.get("fungoid", {}).get("name", "")
	assert_ne(mushroom_name, fungoid_name,
		"mushroom and fungoid should have distinct display names")


# ---- Elemental damage: calculate_elemental_modifier returns correct values ----

func test_elemental_weakness_modifier() -> void:
	_combatant.elemental_weaknesses = ["fire"]
	var mod = _combatant.calculate_elemental_modifier("fire")
	assert_eq(mod, 1.5, "Weakness should return 1.5x modifier")


func test_elemental_resistance_modifier() -> void:
	_combatant.elemental_resistances = ["ice"]
	var mod = _combatant.calculate_elemental_modifier("ice")
	assert_eq(mod, 0.5, "Resistance should return 0.5x modifier")


func test_elemental_immunity_modifier() -> void:
	_combatant.elemental_immunities = ["lightning"]
	var mod = _combatant.calculate_elemental_modifier("lightning")
	assert_eq(mod, 0.0, "Immunity should return 0.0x modifier")


func test_elemental_neutral_modifier() -> void:
	var mod = _combatant.calculate_elemental_modifier("dark")
	assert_eq(mod, 1.0, "Neutral element should return 1.0x modifier")


# ===========================================================================
# Status effect regression tests (commit 0e830a0)
# ===========================================================================

# ---- Status effect duration tracking ----

func test_status_added_with_duration() -> void:
	_combatant.add_status("poison", 3)
	assert_true(_combatant.has_status("poison"), "Combatant should have poison status")
	assert_eq(_combatant.status_durations.get("poison", 0), 3, "Poison should have 3 turns remaining")


func test_status_expires_after_duration() -> void:
	_combatant.add_status("blind", 2)
	assert_true(_combatant.has_status("blind"), "Should have blind status")

	_combatant.update_buff_durations()
	assert_true(_combatant.has_status("blind"), "Blind should persist after 1 tick")
	assert_eq(_combatant.status_durations.get("blind", 0), 1, "Blind should have 1 turn remaining")

	_combatant.update_buff_durations()
	assert_false(_combatant.has_status("blind"), "Blind should expire after 2 ticks")


func test_status_removed_cleans_duration() -> void:
	_combatant.add_status("stun", 3)
	_combatant.remove_status("stun")
	assert_false(_combatant.has_status("stun"), "Stun should be removed")
	assert_false(_combatant.status_durations.has("stun"), "Duration entry should be cleaned up")


func test_permanent_status_never_expires() -> void:
	_combatant.add_status("curse", -1)
	for i in range(10):
		_combatant.update_buff_durations()
	assert_true(_combatant.has_status("curse"), "Permanent status (-1) should never expire")


# ---- Poison DOT ----

func test_poison_deals_damage_per_turn() -> void:
	_combatant.max_hp = 100
	_combatant.current_hp = 100
	_combatant.add_status("poison", 3)

	_combatant.update_buff_durations()
	# Poison deals 5% max HP = 5 damage
	assert_eq(_combatant.current_hp, 95, "Poison should deal 5%% max HP (5 damage)")


func test_poison_can_kill() -> void:
	var die_count = 0
	_combatant.died.connect(func(): die_count += 1)
	_combatant.max_hp = 100
	_combatant.current_hp = 3
	_combatant.add_status("poison", 5)

	_combatant.update_buff_durations()
	# Poison deals 5 damage, HP was 3 → should die
	assert_eq(_combatant.current_hp, 0, "HP should reach 0 from poison")
	assert_eq(die_count, 1, "Poison should kill combatant at 0 HP")


func test_poison_minimum_1_damage() -> void:
	_combatant.max_hp = 10
	_combatant.current_hp = 10
	_combatant.add_status("poison", 2)

	_combatant.update_buff_durations()
	# 5% of 10 = 0.5, floored to 0, but min is 1
	assert_eq(_combatant.current_hp, 9, "Poison should deal minimum 1 damage even on low HP targets")


# ---- Status signal emissions ----

func test_status_added_signal_fires() -> void:
	var added_status = ""
	_combatant.status_added.connect(func(s): added_status = s)
	_combatant.add_status("sleep", 2)
	assert_eq(added_status, "sleep", "status_added signal should fire with status name")


func test_status_removed_signal_fires() -> void:
	var removed_status = ""
	_combatant.status_removed.connect(func(s): removed_status = s)
	_combatant.add_status("stun", 1)
	_combatant.update_buff_durations()
	assert_eq(removed_status, "stun", "status_removed signal should fire when status expires")


# ---- No duplicate statuses ----

func test_duplicate_status_not_stacked() -> void:
	_combatant.add_status("poison", 3)
	_combatant.add_status("poison", 5)
	var count = 0
	for s in _combatant.status_effects:
		if s == "poison":
			count += 1
	assert_eq(count, 1, "Same status should not stack — only one instance")
