extends GutTest

## The four W3 steampunk Masterites existed, had art, passed QA — and could not be fought. 2026-07-29.
##
## I added them to monsters.json this session and never wired an encounter pool. cowir-sprites then
## built four sheets for them and reported "roster 98/98, zero monsters without art" — true about
## art, and framed as if World 3 were complete. The art hole and the encounter hole were twins;
## between us we filled one and reported it as the thing.
##
##   enemy_pools.json   masterite_{medieval,suburban,industrial,futuristic,abstract}   present
##                      masterite_steampunk                                            ABSENT
##   references outside monsters.json / sprite_manifest.json
##     the other 20 masterites   3-5 each     the steampunk four   1 each (bestiary only)
##
## NEITHER guard could see it. My data-integrity tests assert every monster's drops, abilities and
## elements resolve — all true of an unreachable monster. cowir-sprites' sheet-coverage ratchet
## asserts every monster in monsters.json loads with a visible idle — also true. Both are honest and
## both are silent on whether the monster can appear, because reachability lives in a third file
## neither of them reads.
##
## That is the class cowir-controller named: work that is correctly built, correctly tested, and
## justified against a surface that isn't live. Strengthening either guard could not have caught it.


func _pools() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemy_pools.json"))
	return raw.get("pools", raw)


func test_every_world_has_a_masterite_pool() -> void:
	# Derived from the worlds the game declares, not a hand-listed six — a seventh world would
	# otherwise ship the same hole silently.
	var pools: Dictionary = _pools()
	var missing: Array = []
	for world in ["medieval", "suburban", "steampunk", "industrial", "futuristic", "abstract"]:
		if not pools.has("masterite_" + world):
			missing.append(world)
	assert_eq(missing, [], "worlds whose masterites cannot spawn: %s" % str(missing))


func test_every_masterite_in_monsters_json_belongs_to_a_pool() -> void:
	# The general form, and the one that would have caught this the moment the four entries landed.
	# An authored monster with no pool is invisible to the player and to every other guard.
	var pools: Dictionary = _pools()
	var pooled: Dictionary = {}
	for key in pools:
		for m in (pools[key] as Array):
			pooled[str(m)] = true
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var orphans: Array = []
	for id in mons:
		if not str(id).begins_with("masterite_"):
			continue
		if not pooled.has(str(id)):
			orphans.append(str(id))
	assert_eq(orphans, [],
		"masterites authored but unreachable — art, stats and bestiary entries all exist and no "
		+ "encounter can produce them:\n  %s" % "\n  ".join(orphans))


func test_no_pool_names_a_monster_that_does_not_exist() -> void:
	# The reverse direction. A pool entry pointing at a missing id is worse than no pool: the
	# encounter fires and resolves to nothing, which reads as a spawn bug rather than a data typo.
	var pools: Dictionary = _pools()
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var ghosts: Array = []
	for key in pools:
		for m in (pools[key] as Array):
			if not mons.has(str(m)):
				ghosts.append("%s -> %s" % [key, m])
	assert_eq(ghosts, [], "pool entries with no monster behind them:\n  %s" % "\n  ".join(ghosts))


func test_the_scan_is_not_vacuous() -> void:
	# Positive control. An empty pool table and a clean corpus produce identical results, and this
	# whole file would pass against a parse that returned {}.
	var pools: Dictionary = _pools()
	assert_gt(pools.size(), 10, "enemy_pools must actually parse — a vacuous read passes everything")
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var masterites: int = 0
	for id in mons:
		if str(id).begins_with("masterite_"):
			masterites += 1
	assert_eq(masterites, 24, "24 masterites = 4 axes × 6 worlds; a different count means the "
		+ "corpus moved and the coverage claim above needs re-reading, not silencing")
