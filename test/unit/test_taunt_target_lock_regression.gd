extends GutTest

## Regression: Taunt sets a `taunted_<caster>` status on the target enemy, but
## no AI target picker read it — taunt had zero mechanical effect, attacks
## proceeded to the lowest-HP PC as if no taunt applied.
##
## Fix: BattleManager._choose_target now consults _find_taunter first, locking
## onto the matching taunter when the attacker has a taunted_<name> status.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _make_combatant(cname: String, hp: int = 100) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = cname
	c.max_hp = hp
	c.current_hp = hp
	c.max_mp = 30
	c.current_mp = 30
	c.attack = 10
	c.defense = 10
	c.magic = 10
	c.speed = 10
	c.is_alive = true
	return c


func test_choose_target_returns_taunter_when_status_present() -> void:
	var bm = load(BATTLE_MANAGER_PATH).new()
	add_child_autofree(bm)
	var attacker := _make_combatant("Goblin")
	var tank := _make_combatant("Guardian", 200)
	var glass := _make_combatant("Mage", 20)
	add_child_autofree(attacker)
	add_child_autofree(tank)
	add_child_autofree(glass)
	# Tank taunts the goblin — goblin must lock onto tank even though glass is
	# the lowest-HP target the unbiased picker would prefer.
	attacker.add_status("taunted_Guardian")
	for i in range(20):
		var pick = bm._choose_target(attacker, [glass, tank], {})
		assert_eq(pick, tank,
			"taunted attacker must lock onto the named taunter on every roll")


func test_find_taunter_ignores_unmatched_status() -> void:
	var bm = load(BATTLE_MANAGER_PATH).new()
	add_child_autofree(bm)
	var attacker := _make_combatant("Goblin")
	var tank := _make_combatant("Guardian")
	add_child_autofree(attacker)
	add_child_autofree(tank)
	# Different taunter name — must NOT match the only candidate.
	attacker.add_status("taunted_Paladin")
	var pick = bm._find_taunter(attacker, [tank])
	assert_null(pick, "name mismatch must not produce a false-positive taunt lock")


func test_find_taunter_skips_dead_taunter() -> void:
	var bm = load(BATTLE_MANAGER_PATH).new()
	add_child_autofree(bm)
	var attacker := _make_combatant("Goblin")
	var tank := _make_combatant("Guardian")
	tank.is_alive = false
	add_child_autofree(attacker)
	add_child_autofree(tank)
	attacker.add_status("taunted_Guardian")
	var pick = bm._find_taunter(attacker, [tank])
	assert_null(pick, "dead taunter must not lock the attacker (taunt is broken)")


func test_battle_manager_choose_target_calls_find_taunter() -> void:
	# Source-level guard: keep the taunt path wired so a refactor can't silently
	# drop the taunt check from _choose_target again.
	var file = FileAccess.open(BATTLE_MANAGER_PATH, FileAccess.READ)
	assert_not_null(file)
	var text = file.get_as_text()
	file.close()
	assert_true(text.find("_find_taunter(attacker, targets)") != -1,
		"_choose_target must call _find_taunter to honor taunt status.")
