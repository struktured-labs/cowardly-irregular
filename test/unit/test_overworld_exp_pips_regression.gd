extends GutTest

## Bugfix 2026-07-05: OverworldMenu._create_exp_indicator read two properties
## that DON'T EXIST on Combatant — member.experience (field is job_exp) and
## member.exp_to_next_level (threshold is job_level*100). Both `in` checks
## failed, so the numerator was permanently 0 and the denominator a flat 100 →
## the party menu's EXP pips were stuck empty (□□□□□) at every level. Now reads
## the real fields, so the pips reflect actual progress against job_level*100.

const OM := preload("res://src/ui/OverworldMenu.gd")


func _filled_pips(job_level: int, job_exp: int) -> int:
	var menu: OverworldMenu = OM.new()
	autofree(menu)
	var c := Combatant.new()
	autofree(c)
	c.job_level = job_level
	c.job_exp = job_exp
	var ind: Control = menu._create_exp_indicator(c)
	autofree(ind)
	for child in ind.get_children():
		if child is Label:
			var t: String = (child as Label).text
			if t.contains("■") or t.contains("□"):
				return t.count("■")
	return -1  # pip label not found


func test_halfway_through_level_fills_half_the_pips() -> void:
	# job_level 3 → threshold 300; job_exp 150 = 50% → 2 of 5 pips. This single
	# assertion rejects BOTH old bugs: experience→0 (all empty) and flat-100
	# denominator (150/100 = 150% → all full).
	assert_eq(_filled_pips(3, 150), 2, "half-way through level 3 must fill exactly 2 of 5 pips")


func test_zero_exp_is_empty() -> void:
	assert_eq(_filled_pips(1, 0), 0, "no EXP → no filled pips")


func test_any_progress_fills_at_least_one_pip() -> void:
	# The headline regression: pips were permanently empty regardless of EXP.
	assert_gt(_filled_pips(2, 100), 0, "real EXP progress must fill at least one pip")


func test_full_bar_at_threshold() -> void:
	assert_eq(_filled_pips(4, 400), 5, "EXP at the level threshold fills all 5 pips")
