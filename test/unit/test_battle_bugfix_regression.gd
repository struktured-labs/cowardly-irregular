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
