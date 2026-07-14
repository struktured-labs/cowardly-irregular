extends GutTest

## Regression test for the jailbreak BACKFIRE "enrage_briefly" silent no-op.
##
## Bug summary: When a player's "Address the Boss" directive trips the
## mock/backfire vulnerability, BattleManager._on_boss_jailbreak_succeeded
## applies `boss.add_buff("enraged", "crit_rate", 1.5, dur)`. But the crit
## system never consulted active_buffs — _calculate_crit_chance only summed
## base 5% + speed*0.01 + the critical_strike passive + equip bonus. So the
## documented "BACKFIRE — Mordaine seizes the mock, crit-rate spiking"
## punishment had ZERO mechanical impact: the boss's crit chance was
## unchanged. This is the project's canonical silent-failure class — data /
## design promises an effect the engine never applies.
##
## Fix: _calculate_crit_chance now iterates the attacker's active_buffs and
## adds (modifier - 1.0) for any buff whose stat == "crit_rate", so the
## enrage actually spikes the boss's crit chance (pinned to the 50% cap).
## This test pins both halves: the buff is stored with stat "crit_rate", and
## the crit calc reads it.


const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


# Minimal Combatant standin (no JobSystem dependency) — surgical regression.
func _make_boss() -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "TestBoss"
	c.max_hp = 200
	c.current_hp = 200
	c.max_mp = 50
	c.current_mp = 50
	c.attack = 30
	c.defense = 20
	c.magic = 20
	c.speed = 0   # zero speed so base crit chance is just the 5% floor
	c.is_alive = true
	return c


func _new_battle_manager() -> Node:
	var bm = load(BATTLE_MANAGER_PATH).new()
	add_child_autofree(bm)
	return bm


func test_enrage_buff_is_stored_with_crit_rate_stat() -> void:
	# The buff the enrage_briefly path adds must carry stat == "crit_rate"
	# so the crit calc's reader can find it. (Bug was a write with no reader.)
	var boss := _make_boss()
	add_child_autofree(boss)
	boss.add_buff("enraged", "crit_rate", 1.5, 1)
	var found := false
	for b in boss.active_buffs:
		if str(b.get("stat", "")) == "crit_rate":
			found = true
			assert_almost_eq(float(b.get("modifier", 0.0)), 1.5, 0.001,
				"crit_rate buff must store the 1.5 modifier")
	assert_true(found,
		"enrage buff must be stored with stat 'crit_rate' for the crit calc to read")


func test_crit_chance_actually_increases_with_crit_rate_buff() -> void:
	# The core fix: _calculate_crit_chance must read the crit_rate buff so the
	# enrage punishment is mechanically real, not cosmetic.
	var bm = _new_battle_manager()
	var boss := _make_boss()
	add_child_autofree(boss)

	var crit_before: float = bm._calculate_crit_chance(boss)

	boss.add_buff("enraged", "crit_rate", 1.5, 1)
	var crit_after: float = bm._calculate_crit_chance(boss)

	assert_gt(crit_after, crit_before,
		"crit chance MUST increase after the enrage crit_rate buff lands — " +
		"otherwise the jailbreak BACKFIRE punishment is a silent no-op")
	# A 1.5 modifier contributes +0.5 additively, which the 0.50 cap pins to
	# the maximum 50% crit spike for the enraged turn.
	assert_almost_eq(crit_after, 0.50, 0.001,
		"a 1.5 crit_rate buff should spike crit chance to the 50% cap")


func test_crit_chance_unchanged_without_crit_rate_buff() -> void:
	# Guardrail: non-crit_rate buffs must NOT bleed into the crit calc.
	var bm = _new_battle_manager()
	var boss := _make_boss()
	add_child_autofree(boss)

	var crit_before: float = bm._calculate_crit_chance(boss)
	# An attack buff (a stat get_buffed_stat reads) must not affect crit.
	boss.add_buff("Berserk", "attack", 1.5, 2)
	var crit_after: float = bm._calculate_crit_chance(boss)

	assert_almost_eq(crit_after, crit_before, 0.001,
		"only crit_rate buffs may raise crit chance — an attack buff must not")


func test_battle_manager_crit_calc_reads_crit_rate_buff() -> void:
	# Source-level guard: make sure the crit_rate reader survives in
	# _calculate_crit_chance. Without this someone could "clean up" the fix
	# and silently re-break the BACKFIRE punishment.
	var src := FileAccess.get_file_as_string(BATTLE_MANAGER_PATH)
	assert_true(src != "", "BattleManager.gd must be readable from disk")
	var fn_idx := src.find("func _calculate_crit_chance")
	assert_gt(fn_idx, -1, "_calculate_crit_chance must exist")
	var fn_end := src.find("\nfunc ", fn_idx + 1)
	var body := src.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else src.substr(fn_idx)
	assert_true(body.find("crit_rate") > -1,
		"_calculate_crit_chance must read 'crit_rate' buffs so the enrage punishment is real")
	assert_true(body.find("active_buffs") > -1,
		"_calculate_crit_chance must iterate active_buffs to find the crit_rate buff")
