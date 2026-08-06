extends GutTest

## The per-world job-sprite SEAM (struktured: "your characters are supposed to xform as they
## shift overworlds"). Five consumer sites built this path by hand — OverworldPlayer,
## CutsceneActor, CutsceneDialogue busts, SaveScreen busts — and none knew about the others.
## Now all four resolve through ONE pure helper, and the suffix rides every cache key
## (a cached medieval form surviving a world transition is the transform silently never
## rendering — the failure that looks like nothing).
##
## The test spec is the fleet's, written before the code: fighter in "digital" resolves the
## digital sheet; fighter in "medieval" resolves the BASE (the unsuffixed file IS the medieval
## art — a test demanding suffixed sheets everywhere reds on a correct batch); an unlisted
## world falls back to base. The fallback arm is the design, so it is tested or it is nothing.

const Loader = preload("res://src/battle/sprites/HybridSpriteLoader.gd")


func test_medieval_resolves_the_base_sheet() -> void:
	# The arm most likely to be got wrong, per cowir-sfx: medieval is deliberately unsuffixed.
	# The all-true probe makes SKIPPED distinguishable from PROBED-AND-MISSED — without it,
	# deleting the medieval guard survives every test until someone ships a _medieval file
	# (measured: mutation M1 survived 4/4 on the default probe).
	var always := func(_p: String) -> bool: return true
	assert_eq(Loader.job_asset_path("fighter", "overworld", "medieval", always),
		"res://assets/sprites/jobs/fighter/overworld.png",
		"medieval must SKIP the probe entirely — fighter_medieval is dead on arrival even if it exists")
	assert_eq(Loader.job_asset_path("fighter", "idle", "", always),
		"res://assets/sprites/jobs/fighter/idle.png",
		"an empty suffix (no world known) also skips the probe")
	assert_eq(Loader.job_asset_path("fighter", "overworld", "digital", always),
		"res://assets/sprites/jobs/fighter/overworld_digital.png",
		"POSITIVE ARM, live today: a real suffix takes the variant when the probe finds it")


func test_a_world_without_a_variant_falls_back_to_base() -> void:
	# TODAY this covers "digital" too: no variant sheets exist yet. When cowir-sprites' pilot
	# lands fighter/overworld_<suffix>.png, ADD the positive arm asserting the variant WINS —
	# this comment is the reminder, and the coverage guard below reds if the art lands unshipped.
	for w in ["digital", "abstract", "zzz_not_a_world"]:
		assert_eq(Loader.job_asset_path("fighter", "overworld", w),
			"res://assets/sprites/jobs/fighter/overworld.png",
			"absent variant for '%s' must fall back to base — silent procedural is the enemy" % w)


func test_every_variant_sheet_on_disk_is_reachable_by_the_helper() -> void:
	# The masterite-silhouette lesson inverted: when variant art DOES land, this walks the
	# real directories and asserts the helper resolves each sheet — art that ships unreachable
	# fails here instead of sitting dark for months.
	var dir := DirAccess.open("res://assets/sprites/jobs")
	assert_not_null(dir, "jobs dir readable")
	if dir == null:
		return
	var checked: int = 0
	for job in dir.get_directories():
		var jd := DirAccess.open("res://assets/sprites/jobs/" + job)
		if jd == null:
			continue
		for f in jd.get_files():
			var m := RegEx.create_from_string("^(overworld|idle)_([a-z]+)\\.png$").search(f)
			if m == null:
				continue
			checked += 1
			var resolved := Loader.job_asset_path(job, m.get_string(1), m.get_string(2))
			assert_string_contains(resolved, f,
				"variant sheet %s/%s exists on disk but the helper does not resolve it — unreachable art" % [job, f])
	gut.p("variant sheets on disk: %d (0 is correct until the pilot lands)" % checked)


func test_all_four_consumers_resolve_through_the_helper() -> void:
	# Five hand-built constructions became one; a site regressing to a literal re-splits the
	# corpus. The suffix must also be IN the cache keys at the three caching sites.
	var sites := {
		"res://src/exploration/OverworldPlayer.gd": ["job_asset_path", "current_world_suffix"],
		"res://src/cutscene/CutsceneActor.gd": ["job_asset_path"],
		"res://src/cutscene/CutsceneDialogue.gd": ["job_asset_path", "cache_key := \"bust:%s:%s\""],
		"res://src/ui/SaveScreen.gd": ["job_asset_path", "cache_key"],
	}
	for path in sites:
		var src := FileAccess.get_file_as_string(path)
		assert_gt(src.length(), 200, "CONTROL: %s read a real file" % path)
		for needle in sites[path]:
			assert_string_contains(src, needle,
				"%s must carry '%s' — a consumer off the helper re-splits the corpus" % [path, needle])
		assert_false(src.contains("\"res://assets/sprites/jobs/%s/overworld.png\" %"),
			"%s must not hand-build the base path any more" % path)
