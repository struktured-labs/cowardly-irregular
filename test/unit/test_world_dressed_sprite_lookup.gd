extends GutTest

## Regression: per-world costume sheets must be REACHABLE, and must never be able
## to take an artist sheet away.
##
## struktured, 2026-08: characters change costume per world (option B — costume
## progression, not a rendering-era change). That ships ~140 `<anim>_<suffix>.png`
## sheets next to the artist's base art. The hazard is not the art, it is the seam:
##
##   1. sheets nothing loads are dead weight — the lookup has to actually fire
##   2. a suffix that resolves when the file is ABSENT hides the artist's base art
##      behind a broken path, which is exactly the "never overwrite artist sprites"
##      rule violated by lookup instead of by write
##
## So the contract is one sentence: a dressed sheet wins ONLY when it exists.
## These drive HybridSpriteLoader.world_suffix directly rather than pinning source
## text, because a rename should be free and a behaviour change should not be.

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")


func test_world_one_is_UNSUFFIXED_because_it_is_the_artists_own_art() -> void:
	# The base sheets ARE the artist's medieval art. If world 1 ever gained a suffix,
	# every starter would look for idle_medieval.png, find nothing, and the fallback
	# would be the only thing keeping the artist's work on screen.
	assert_eq(Loader.world_suffix(1), "",
		"world 1 must resolve to the empty suffix — its sheets are the artist's base art")


func test_each_world_maps_to_its_own_distinct_suffix() -> void:
	# Pinned to WorldMapMenu.WORLD_DATA: 1 Medieval, 2 Suburban, 3 Steampunk,
	# 4 Industrial, 5 Digital, 6 Abstract. A shifted mapping dresses the cast for
	# the wrong world — visible, but only to someone who plays that far.
	var expected := {2: "suburban", 3: "steampunk", 4: "industrial", 5: "digital", 6: "abstract"}
	for world in expected:
		assert_eq(Loader.world_suffix(world), expected[world],
			"world %d must dress as '%s'" % [world, expected[world]])

	var seen := {}
	for world in range(1, 7):
		var s: String = Loader.world_suffix(world)
		assert_false(seen.has(s) and s != "",
			"suffix '%s' is claimed by two worlds — one world's costumes would render in the other" % [s])
		seen[s] = true


func test_out_of_range_worlds_degrade_to_base_never_to_a_broken_path() -> void:
	# current_world is an int with no enforced ceiling. A 0 or a 7 must land on the
	# artist's base art, not on a suffix that resolves to a file nobody authored.
	for bad in [-1, 0, 7, 99]:
		assert_eq(Loader.world_suffix(bad), "",
			"out-of-range world %d must fall back to the unsuffixed artist sheet" % [bad])


func test_the_suffix_vocabulary_matches_what_is_ON_DISK() -> void:
	# The join nothing had: the suffixes the CODE will ask for vs the ones the
	# GENERATOR writes. A vocabulary drift here is silent — every lookup misses and
	# every job quietly renders its medieval sheet in all six worlds, which looks
	# exactly like "the feature was never turned on".
	var dir := DirAccess.open("res://assets/sprites/jobs")
	assert_not_null(dir, "jobs sprite dir must exist — otherwise this test measures nothing")
	if dir == null:
		return

	var on_disk := {}
	for job in dir.get_directories():
		var jd := DirAccess.open("res://assets/sprites/jobs/%s" % job)
		if jd == null:
			continue
		for f in jd.get_files():
			if not f.ends_with(".png") or f.ends_with(".import"):
				continue
			var stem: String = f.get_basename()
			if not stem.contains("_"):
				continue
			var tail: String = stem.substr(stem.rfind("_") + 1)
			if tail != "":
				on_disk[tail] = true

	# NAMED control: idle.png is shipped for every job, so a scan finding no bare
	# sheets at all has drifted and every result below is a false clean.
	assert_true(DirAccess.open("res://assets/sprites/jobs/fighter") != null,
		"fighter's sheet dir must be scannable — it is the artist's anchor")

	var vocabulary := {}
	for s in Loader.WORLD_SUFFIXES:
		if s != "":
			vocabulary[s] = true

	# Only flag tails that LOOK like a world claim. Animation names (walk_up, etc.)
	# and unrelated variants are not this test's business.
	var orphaned: Array = []
	for tail in on_disk:
		if vocabulary.has(tail):
			continue
		if tail in ["suburban", "steampunk", "industrial", "digital", "abstract",
				"medieval", "futuristic"]:
			orphaned.append(tail)
	orphaned.sort()
	assert_eq(orphaned, [],
		("world-dressed sheet(s) on disk whose suffix the loader will never ask for — " +
		"the art was generated and is unreachable: %s") % [orphaned])


func test_a_dressed_sheet_never_REPLACES_a_missing_one() -> void:
	# The core safety property, stated as behaviour: for a job with base art and no
	# world art, every world must still resolve to a loadable sheet. This is the
	# "never overwrite artist sprites" rule enforced at the LOOKUP, where a bad
	# suffix could hide the artist's work without touching a single byte of it.
	var base := "res://assets/sprites/jobs/fighter/idle.png"
	assert_true(ResourceLoader.exists(base),
		"fighter/idle.png is the artist's anchor sheet — if it is gone this test is meaningless")

	for world in range(1, 7):
		var suffix: String = Loader.world_suffix(world)
		var dressed := "res://assets/sprites/jobs/fighter/idle_%s.png" % [suffix]
		var resolved: String = dressed if suffix != "" and ResourceLoader.exists(dressed) else base
		assert_true(ResourceLoader.exists(resolved),
			("world %d resolves fighter idle to '%s', which does not load — a world with no " +
			"costume art must fall back to the artist's base sheet") % [world, resolved])
