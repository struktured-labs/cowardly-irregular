extends GutTest

## The .794 balance ruling in the data (cowir-main 24513 / 24521, from the fixed-engine tables): the Mage's second tier lands at 2.8, and a signature physical move crits as its user's swing does.
## Tier 1 at 2.0 is about twice a Power Strike off-weakness at every level, which was the target; tier 2 at 3.5 was 3.7 times one.

const TIERS := {
	1: ["fire", "blizzard", "thunder"],
	2: ["fira", "blizzara", "thundara"],
	3: ["firaga", "blizzaga", "thundaga"],
}


func _mult(id: String) -> float:
	return float(JobSystem.get_ability(id).get("damage_multiplier", 0.0))


func _tier_value(tier: int) -> float:
	var seen: Array = []
	for id in TIERS[tier]:
		if not seen.has(_mult(id)):
			seen.append(_mult(id))
	assert_eq(seen.size(), 1, "the three elements of tier %d must hit alike: %s" % [tier, str(seen)])
	return float(seen[0]) if seen.size() > 0 else 0.0


func test_the_three_elements_of_a_tier_agree_and_the_tiers_are_in_order() -> void:
	for id in TIERS[2]:
		assert_eq(str(JobSystem.get_ability(id).get("target_type", "")), "single_enemy", "CONTROL: %s is a one-foe spell" % id)
	for id in TIERS[3]:
		assert_eq(str(JobSystem.get_ability(id).get("target_type", "")), "all_enemies", "CONTROL: %s reaches every foe" % id)
	var one: float = _tier_value(1)
	var two: float = _tier_value(2)
	var all: float = _tier_value(3)
	assert_gt(one, 0.0, "CONTROL: tier 1 has a multiplier")
	assert_gt(two, one, "the second tier out-hits the first")
	assert_lte(all, two, "and a spell for every foe never out-hits, per foe, the best one-foe spell (the standing rule)")
	assert_gt(all, one, "while still out-hitting the first tier on each foe it reaches")


func test_the_second_tier_is_the_ruled_value() -> void:
	assert_almost_eq(_tier_value(2), 2.8, 0.0001, "ruled 2026-11-12: tier 2 at 2.8 (about 2.9 times a Power Strike); change it with a new table, not by hand")


func test_both_engines_read_the_same_defaults() -> void:
	assert_true(DamageRules.abilities_inherit_swing_crit, "shipped: a physical ability with no crit_chance crits as its user's swing does")
	assert_eq(DamageRules.crit_mode, "shipped", "shipped: the speed rule is unchanged")
	assert_almost_eq(DamageRules.ability_crit_chance({}, 0.19), 0.19, 0.0001, "so Power Strike crits at the swing's chance")
	assert_almost_eq(DamageRules.ability_crit_chance({"crit_chance": 0}, 0.19), 0.0, 0.0001, "and a row can still opt out")
	var live: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var grind: String = FileAccess.get_file_as_string("res://src/autogrind/HeadlessBattleResolver.gd")
	assert_gt(live.length(), 50000, "CONTROL: BattleManager was read")
	assert_gt(grind.length(), 10000, "CONTROL: the resolver was read")
	for call in ["DamageRules.ability_crit_chance(", "DamageRules.speed_crit_bonus(", "DamageRules.spread_factor(", "DamageRules.crit_cap()"]:
		assert_true(live.contains(call), "live must ask the shared rule: %s" % call)
		assert_true(grind.contains(call), "the grind must ask the shared rule: %s" % call)
	for engine in [live, grind]:
		assert_false(engine.contains("abilities_inherit_swing_crit ="), "neither engine sets the dial itself; the default is DamageRules' own")
		assert_false(engine.contains("enemy_spread ="), "neither engine sets the spread itself")
