extends GutTest

## "Permanent injuries" is a headline real-stakes mechanic — the penalty
## must survive recalculate_stats (which fires on every level-up, equip,
## and save-load). apply_permanent_injury subtracts once for immediate
## effect, but recalc RESETS every stat to base+mods, so it must
## re-subtract the injury from its own list. The max_mp arm was silently
## missing pre-tick-316; only max_mp has a behavioral survival test.
## This pins ALL stat arms behaviorally so a recalc refactor can't
## quietly drop one and un-maim the party.

const STAT_BASES := {
	"attack": "base_attack", "defense": "base_defense",
	"magic": "base_magic", "speed": "base_speed", "max_hp": "base_max_hp",
}


func _injured(stat: String, base_val: int, penalty: int) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)  # recalc's autoload lookups are absolute-path (need a tree)
	c.combatant_name = "Maimed"
	c.set(STAT_BASES[stat], base_val)
	c.set(stat, base_val)
	c.job_level = 1  # no job dict → stat == base grown by the level-1 curve
	c.apply_permanent_injury({"stat": stat, "penalty": penalty})
	return c


## What recalc rebuilds a base of `v` to at level 1 before the injury comes off (spectrum curve, 2026-10-31).
func _grown(stat: String, v: int) -> int:
	if stat in Combatant.SCALED_STAT_FIELDS:
		return maxi(1, int(v * Combatant.level_multiplier(1)))
	return int(v * Combatant.linear_level_multiplier(1))


func test_each_stat_injury_survives_one_recalc() -> void:
	for stat in STAT_BASES:
		var c := _injured(stat, 50, 10)
		assert_eq(c.get(stat), 40, "%s injury must apply immediately (50-10)" % stat)
		c.recalculate_stats()
		assert_eq(c.get(stat), _grown(stat, 50) - 10,
			"%s injury must SURVIVE recalculate_stats — 'permanent' is the whole mechanic" % stat)


func test_injury_not_double_applied_across_repeated_recalcs() -> void:
	# Two recalcs in a row must not stack the penalty (base resets each time).
	var c := _injured("attack", 50, 10)
	c.recalculate_stats()
	c.recalculate_stats()
	assert_eq(c.get("attack"), _grown("attack", 50) - 10,
		"repeated recalcs must not compound the injury (one penalty, never two) — base reset guarantees single application")


func test_injury_floor_is_one_for_combat_stats() -> void:
	# A penalty larger than the stat must floor at 1, not go negative,
	# and survive recalc at the floor.
	var c := _injured("attack", 5, 999)
	assert_eq(c.get("attack"), 1, "over-penalty floors at 1 on apply")
	c.recalculate_stats()
	assert_eq(c.get("attack"), 1, "floor must hold across recalc")
