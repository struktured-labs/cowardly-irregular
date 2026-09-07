extends GutTest

## Regression test for the gain_job_exp multi-level-up bug.
##
## Original bug (found via audit on 2026-04-24):
##   gain_job_exp() used `if` not `while`, so a single call with EXP >= multiple
##   level thresholds would only level up ONCE, leaving the rest of the EXP
##   stalled. Autogrind/ludicrous-speed pipelines regularly award 500+ EXP
##   per battle, enough to skip 3-5 levels — which meant characters silently
##   capped at +1 level per autogrind tick.
##
## Fix: Loop while job_exp >= threshold, consuming level thresholds until
## the remainder is below the next threshold.

const Combatant = preload("res://src/battle/Combatant.gd")

var _combatant: Combatant


func before_each() -> void:
	_combatant = Combatant.new()
	_combatant.combatant_name = "Test"
	_combatant.job_level = 1
	_combatant.job_exp = 0
	_combatant.max_hp = 100
	_combatant.current_hp = 100
	_combatant.attack = 20
	_combatant.defense = 10
	_combatant.magic = 15
	_combatant.speed = 12
	add_child_autofree(_combatant)


func test_single_exp_gain_levels_up_once() -> void:
	# Baseline: single level-up still works
	_combatant.job_level = 1
	_combatant.job_exp = 0
	_combatant.gain_job_exp(100)
	assert_eq(_combatant.job_level, 2, "100 EXP at level 1 should level up to 2")
	assert_eq(_combatant.job_exp, 0, "Excess EXP after level up should be 0")


func test_partial_exp_does_not_level_up() -> void:
	_combatant.job_level = 1
	_combatant.job_exp = 0
	_combatant.gain_job_exp(50)
	assert_eq(_combatant.job_level, 1, "50 EXP at level 1 should NOT level up")
	assert_eq(_combatant.job_exp, 50, "job_exp should be 50")


func test_excess_exp_carries_over_to_next_level() -> void:
	# 150 EXP at level 1 → level up (consume 100), 50 EXP carry over into level 2
	_combatant.job_level = 1
	_combatant.job_exp = 0
	_combatant.gain_job_exp(150)
	assert_eq(_combatant.job_level, 2, "150 EXP at level 1 should level up to 2")
	assert_eq(_combatant.job_exp, 50, "50 EXP should carry into level 2")


func test_multi_level_exp_gain_crosses_multiple_thresholds() -> void:
	# Regression: 500 EXP at level 1 should level up to level 3 (not just 2)
	# Level 1 → 2 needs 100, level 2 → 3 needs 200. Total 300. Remainder 200.
	# Level 3 → 4 needs 300. Remainder 200 < 300 so stop at level 3.
	_combatant.job_level = 1
	_combatant.job_exp = 0
	_combatant.gain_job_exp(500)
	assert_eq(_combatant.job_level, 3,
		"500 EXP at level 1 should reach level 3 (NOT just 2 — regression: single level-up per call)")
	assert_eq(_combatant.job_exp, 200,
		"After consuming 100+200=300 for 2 levelups, 200 EXP should remain")


func test_huge_exp_gain_caps_at_level_99() -> void:
	# Very large EXP shouldn't blow past level 99 (or loop forever).
	_combatant.job_level = 1
	_combatant.job_exp = 0
	# 99 * 100 * 99 / 2 ≈ 490k EXP to hit level 99
	_combatant.gain_job_exp(1_000_000)
	assert_eq(_combatant.job_level, 99,
		"1M EXP should cap at level 99, not exceed (safety ceiling)")


func test_zero_exp_is_noop() -> void:
	_combatant.job_level = 5
	_combatant.job_exp = 50
	_combatant.gain_job_exp(0)
	assert_eq(_combatant.job_level, 5, "0 EXP should not change level")
	assert_eq(_combatant.job_exp, 50, "0 EXP should not change exp total")


func test_negative_exp_is_noop() -> void:
	# Defensive: negative EXP (from a buggy source) should not decrement
	_combatant.job_level = 5
	_combatant.job_exp = 50
	_combatant.gain_job_exp(-100)
	assert_eq(_combatant.job_level, 5, "Negative EXP should not change level")
	assert_eq(_combatant.job_exp, 50, "Negative EXP should not reduce exp total")


func test_exact_threshold_hits_next_level_with_zero_exp() -> void:
	# job_exp of exactly (level * 100) should level up and leave 0 EXP.
	_combatant.job_level = 3
	_combatant.job_exp = 0
	_combatant.gain_job_exp(300)  # Level 3 → 4 needs 300
	assert_eq(_combatant.job_level, 4, "Exactly 300 EXP at level 3 should reach level 4")
	assert_eq(_combatant.job_exp, 0, "Exactly threshold consumed — 0 remaining")


func test_recalculate_stats_called_only_when_leveling_up() -> void:
	# Partial EXP shouldn't trigger stat recalculation (save overhead).
	# We proxy this by checking that stats don't change on sub-threshold gain.
	_combatant.job_level = 1
	var initial_max_hp = _combatant.max_hp
	_combatant.gain_job_exp(50)  # Not enough to level up
	assert_eq(_combatant.max_hp, initial_max_hp,
		"Partial EXP should not trigger recalculate_stats (max_hp unchanged)")
