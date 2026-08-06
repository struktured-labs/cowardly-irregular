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


## The core safety property, driven through the REAL loader.
##
## An earlier version of this test recomputed the dressed-vs-base choice inline and
## asserted on its own arithmetic. It passed 5/5 against a mutation that deleted the
## existence check entirely — it was measuring the test, not the seam. Mutation
## testing is the only reason that was caught, so this drives _load_external_sheet
## itself and lets GameState.current_world select the world, exercising the autoload
## read in world_suffix() at the same time.
func test_every_job_still_loads_in_EVERY_world_through_the_real_loader() -> void:
	var gs := get_node_or_null("/root/GameState")
	assert_not_null(gs, "GameState autoload required — run via tools/run_tests.sh, not -s")
	if gs == null:
		return

	var jobs := _jobs_with_base_art()
	# NAMED control: a scan that lost the artist's own jobs would pass vacuously.
	for known in ["fighter", "cleric", "mage", "rogue"]:
		assert_true(known in jobs,
			("the job scan must find '%s' — it is an artist sheet on disk, so if this " +
			"fails every result below is a false clean") % [known])

	var restore: int = int(gs.current_world)
	var broken: Array = []
	for world in range(1, 7):
		gs.current_world = world
		for job in jobs:
			var data := {"path": "res://assets/sprites/jobs/%s" % job,
				"frame_width": 256, "frame_height": 256}
			var frames = Loader._load_external_sheet(data, job)
			if frames == null or frames.get_animation_names().is_empty():
				broken.append("%s in world %d (suffix '%s')" % [job, world, Loader.world_suffix(world)])
	gs.current_world = restore

	broken.sort()
	assert_eq(broken, [],
		("job(s) that load NOTHING in some world — a world with no costume art must fall " +
		"back to the artist's base sheet, not resolve to a path nobody authored: %s") % [broken])
	assert_eq(int(gs.current_world), restore, "current_world must be restored for later tests")


## A world sheet on disk must be LOADABLE, not merely present.
##
## Every sheet this lane generated sat unreachable and nothing said so: gpt-image-1 writes
## the .png, but Godot needs a .png.import sidecar, and without one ResourceLoader.exists()
## returns false while FileAccess.file_exists() returns true. Measured on cleric:
##   idle.png          ResourceLoader=true   FileAccess=true
##   idle_digital.png  ResourceLoader=false  FileAccess=true    <- 42 sheets in this state
##
## The lookup then falls back to base art and the game looks completely fine, which is why
## the load-bearing test above (every job loads in every world) stayed green throughout —
## it asserts SOMETHING loads, and base art always does. Scanning with DirAccess sees the
## file and agrees it exists. Only ResourceLoader knows the truth, so only ResourceLoader
## can catch a batch of art that was generated, committed, and never once rendered.
func test_world_sheets_on_disk_are_actually_LOADABLE() -> void:
	var dir := DirAccess.open("res://assets/sprites/jobs")
	assert_not_null(dir, "jobs sprite dir must be scannable")
	if dir == null:
		return

	var suffixes: Array = []
	for s in Loader.WORLD_SUFFIXES:
		if s != "":
			suffixes.append(s)

	var unimported: Array = []
	var found := 0
	for job in dir.get_directories():
		for suffix in suffixes:
			var path := "res://assets/sprites/jobs/%s/idle_%s.png" % [job, suffix]
			if not FileAccess.file_exists(path):
				continue
			found += 1
			if not ResourceLoader.exists(path):
				unimported.append("%s/idle_%s.png" % [job, suffix])
	unimported.sort()

	# Honest when there is nothing to check, rather than passing as if verified.
	if found == 0:
		gut.p("NOTE: no world-dressed sheets on disk yet — nothing to verify")
		assert_true(true, "no world sheets present; guard arms when the art lands")
		return

	assert_eq(unimported, [],
		("%d world sheet(s) present on disk but NOT importable — they never render, the " +
		"lookup silently serves base art, and nothing else in this file can see it. " +
		"Run: godot --headless --audio-driver Dummy --import  : %s") % [unimported.size(), unimported])


## Audio owns the world vocabulary; sheets own the suffix vocabulary. They differ by one
## entry and that difference is load-bearing: audio says "medieval" for world 1 where the
## sheets say "" because world 1 IS the artist's base art. If _normalize_suffix ever passed
## "medieval" through, every world-1 lookup would ask for idle_medieval.png, miss, and land
## on base art — correct art, reached by accident, with nothing failing to say so.
func test_audio_vocabulary_is_translated_not_trusted() -> void:
	assert_eq(Loader._normalize_suffix("medieval"), "",
		"audio's 'medieval' must translate to the unsuffixed artist sheet, not to a filename")
	for shared in ["suburban", "steampunk", "industrial", "digital", "abstract"]:
		assert_eq(Loader._normalize_suffix(shared), shared,
			"'%s' is shared vocabulary and must pass through unchanged" % [shared])
	# 'futuristic' is the name W5 goes by in several places but is NEVER a sheet suffix.
	for foreign in ["futuristic", "", "OVERWORLD", "world2", "suburban_overworld"]:
		assert_eq(Loader._normalize_suffix(foreign), "",
			"unrecognised world name '%s' must degrade to base art, not to a broken path" % [foreign])


## The convergence itself. cowir-sfx added SoundManager.get_current_world_suffix() for this
## consumer, with the note that a second copy "would drift silently into base-art fallback".
## While that branch is unfolded this tree has no such method and the GameState fallback is
## live; the moment it lands, the accessor takes over. This asserts they AGREE, so the
## handover cannot change what the player sees without failing here first.
func test_when_audios_accessor_exists_we_agree_with_it() -> void:
	var sm := get_node_or_null("/root/SoundManager")
	assert_not_null(sm, "SoundManager autoload must exist — it is the world-suffix authority")
	if sm == null:
		return
	if not sm.has_method("get_current_world_suffix"):
		# Honest about which path is live rather than passing silently.
		gut.p("NOTE: public accessor not on this tree yet — GameState fallback is the live path")
		assert_true(true, "fallback path active; convergence check arms itself on fold")
		return
	var theirs: String = str(sm.call("get_current_world_suffix"))
	assert_eq(Loader.world_suffix(), Loader._normalize_suffix(theirs),
		("the loader must return audio's world, translated — a disagreement dresses the party " +
		"for one world while the music plays another (audio said '%s')") % [theirs])


func _jobs_with_base_art() -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://assets/sprites/jobs")
	if dir == null:
		return out
	for job in dir.get_directories():
		if ResourceLoader.exists("res://assets/sprites/jobs/%s/idle.png" % job):
			out.append(job)
	out.sort()
	return out
