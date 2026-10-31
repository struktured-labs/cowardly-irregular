extends GutTest

## A lens tilt reaches a stat only if its key is seeded in BOTH LensSystem.NEUTRAL_MODS and
## get_passive_mods' total; an unseeded key is dropped, with a warning at one gate and silently at
## the other. magic_defense_multiplier was missing from both for months while recalculate_stats
## applied it, so the Warden could not be authored to resist magic. The lens-data guard in
## test_the_warden_holds_against_magic only reds once a lens DECLARES a missing key; this one
## derives from the CONSUMER, so a stat added to MODDABLE_STATS reds before anyone tries.
## It reads which keys EXIST, never what they are worth.


func _seed() -> Dictionary:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = "nobody_with_a_lens"
	return PassiveSystem.get_passive_mods(c)


func test_every_stat_recalculate_stats_scales_is_seeded_at_both_gates() -> void:
	var seed := _seed()
	assert_false(seed.is_empty(), "get_passive_mods must return its seed for a live combatant")
	assert_gt(Combatant.MODDABLE_STATS.size(), 0, "the derivation must reach some stats")
	for stat in Combatant.MODDABLE_STATS:
		var key: String = str(stat) + "_multiplier"
		assert_true(LensSystem.NEUTRAL_MODS.has(key),
			"recalculate_stats applies '%s', but LensSystem.NEUTRAL_MODS drops it" % key)
		assert_true(seed.has(key),
			"recalculate_stats applies '%s', but get_passive_mods' seed lacks it, so _compose_lens_mods drops it" % key)


func test_the_two_seeds_name_the_same_keys() -> void:
	## NEUTRAL_MODS says it mirrors the seed; a key in one and not the other is a lens tilt that
	## passes the first gate and dies at the second, or the reverse.
	var seed := _seed()
	var lens_keys: Array = LensSystem.NEUTRAL_MODS.keys()
	var seed_keys: Array = seed.keys()
	lens_keys.sort()
	seed_keys.sort()
	assert_gt(lens_keys.size(), 0, "NEUTRAL_MODS must carry keys")
	assert_eq(lens_keys, seed_keys, "LensSystem.NEUTRAL_MODS and get_passive_mods' seed must name the same keys")
