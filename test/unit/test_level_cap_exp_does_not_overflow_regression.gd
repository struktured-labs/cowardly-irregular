extends GutTest

## Level 99 is the ceiling (gain_job_exp stops the while, StatusMenu prints "EXP: MAX").
## EXP still added past that ceiling, so a capped character's party card read
## "EXP 514900/9900" — current above the bar — and a save reloaded the same pile.
## The threshold stays job_level * 100. Only the overflow above it is discarded.

const Combatant = preload("res://src/battle/Combatant.gd")

var _combatant: Combatant


func before_each() -> void:
	_combatant = Combatant.new()
	_combatant.combatant_name = "Cap"
	_combatant.job_level = 1
	_combatant.job_exp = 0
	_combatant.max_hp = 100
	_combatant.current_hp = 100
	add_child_autofree(_combatant)


func test_exp_already_at_the_cap_does_not_pass_the_threshold() -> void:
	_combatant.job_level = 99
	_combatant.job_exp = 0
	_combatant.gain_job_exp(50_000)
	assert_eq(_combatant.job_level, 99, "the level ceiling stays 99")
	assert_eq(_combatant.job_exp, 99 * 100,
		"EXP past level 99 must stop at the 9900 threshold, not pile up as 50000/9900")


func test_a_point_on_a_full_cap_bar_does_not_grow_it() -> void:
	_combatant.job_level = 99
	_combatant.job_exp = 99 * 100
	_combatant.gain_job_exp(1)
	assert_eq(_combatant.job_level, 99)
	assert_eq(_combatant.job_exp, 99 * 100,
		"one more point at a full level-99 bar must not read 9901/9900")


func test_remainder_under_the_cap_is_kept() -> void:
	_combatant.job_level = 99
	_combatant.job_exp = 100
	_combatant.gain_job_exp(50)
	assert_eq(_combatant.job_level, 99)
	assert_eq(_combatant.job_exp, 150,
		"EXP still short of the level-99 threshold is real progress and must be kept")


func test_crossing_into_the_cap_keeps_only_a_full_bar() -> void:
	_combatant.job_level = 98
	_combatant.job_exp = 0
	# 98 → 99 costs 9800. The rest has nowhere to go.
	_combatant.gain_job_exp(98 * 100 + 50_000)
	assert_eq(_combatant.job_level, 99)
	assert_eq(_combatant.job_exp, 99 * 100,
		"the level-up into 99 must not leave the overflow that would have bought level 100")


func test_save_load_clamps_exp_already_past_the_cap() -> void:
	# JSON.parse yields floats. A pre-fix save can already hold the pile.
	_combatant.from_dict({"job_level": 99.0, "job_exp": 514900.0})
	assert_eq(_combatant.job_level, 99)
	assert_eq(_combatant.job_exp, 99 * 100,
		"loading a level-99 save must not restore EXP past the 9900 threshold")


func test_save_load_keeps_exp_under_the_cap() -> void:
	_combatant.from_dict({"job_level": 99, "job_exp": 4200})
	assert_eq(_combatant.job_level, 99)
	assert_eq(_combatant.job_exp, 4200,
		"a level-99 remainder under the threshold must survive load unchanged")


func test_capped_exp_roundtrips_through_save() -> void:
	_combatant.job_level = 99
	_combatant.job_exp = 0
	_combatant.gain_job_exp(50_000)
	var restored := Combatant.new()
	add_child_autofree(restored)
	restored.from_dict(_combatant.to_dict())
	assert_eq(restored.job_level, 99)
	assert_eq(restored.job_exp, 99 * 100,
		"a save taken at the cap must come back at the cap, not with the discarded overflow")
