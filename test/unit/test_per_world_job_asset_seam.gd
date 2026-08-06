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

## The runtime world vocabulary — an INDEPENDENT literal, deliberately not derived from any
## resolver map (cowir-sprites: a check derived from the thing it checks is vacuous). Runtime
## returns quadruple-confirmed 2026-08-06: medieval is the BASE (unsuffixed), and "futuristic"
## appears in bodies 39x but is RETURNED zero times — a futuristic sheet would load fine and
## never be requested. If a sixth world ever ships, this list is the one place to grow.
const RUNTIME_SUFFIXES: Array = ["suburban", "steampunk", "industrial", "digital", "abstract"]
const VARIANT_RX := "^(overworld|idle)_([a-z]+)\\.png$"


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
	# Skip-with-floor (cowir-overworld's arm): a world whose variant EXISTS on disk is skipped
	# (asserting fallback there reds on the first CORRECT sheet — sprites' 70-sheet batch is
	# inbound), but the floor arm below can never be skipped, so the test can't go vacuous.
	for w in ["digital", "abstract"]:
		var variant := "res://assets/sprites/jobs/fighter/overworld_%s.png" % w
		if ResourceLoader.exists(variant):
			gut.p("'%s' variant shipped — fallback arm skipped, reachability test covers it" % w)
			continue
		assert_eq(Loader.job_asset_path("fighter", "overworld", w),
			"res://assets/sprites/jobs/fighter/overworld.png",
			"absent variant for '%s' must fall back to base — silent procedural is the enemy" % w)
	# THE FLOOR: not a world, never shippable, always asserts — the arm that keeps this test real.
	assert_eq(Loader.job_asset_path("fighter", "overworld", "zzz_not_a_world"),
		"res://assets/sprites/jobs/fighter/overworld.png",
		"an unknown world must always fall back to base")


func test_every_variant_suffix_is_in_the_runtime_vocabulary() -> void:
	# cowir-overworld's arm: art registered under a suffix the runtime never RETURNS loads fine
	# and is never requested — dark forever (the overworld_futuristic.png trap). Walks the real
	# dirs so the check covers what actually shipped, not what anyone listed.
	assert_false("futuristic" in RUNTIME_SUFFIXES, "futuristic is authored in bodies, returned NEVER")
	assert_false("medieval" in RUNTIME_SUFFIXES, "medieval is the BASE — a _medieval file is dead on arrival")
	var dir := DirAccess.open("res://assets/sprites/jobs")
	assert_not_null(dir, "jobs dir readable")
	if dir == null:
		return
	for job in dir.get_directories():
		var jd := DirAccess.open("res://assets/sprites/jobs/" + job)
		if jd == null:
			continue
		for f in jd.get_files():
			var m := RegEx.create_from_string(VARIANT_RX).search(f)
			if m == null:
				continue
			assert_true(m.get_string(2) in RUNTIME_SUFFIXES,
				"%s/%s carries suffix '%s' the runtime NEVER returns — this art can never render" % [job, f, m.get_string(2)])


func test_the_fetch_site_returns_a_vocabulary_member() -> void:
	# cowir-cutscenes' arm, behavioural half: whatever source current_world_suffix() reads
	# (audio private today, the single visual resolver post-fold), its RETURN must stay inside
	# the vocabulary the helper understands — a rogue value silently disables every variant.
	var got := Loader.current_world_suffix()
	assert_true(got == "" or got == "medieval" or got in RUNTIME_SUFFIXES,
		"fetch site returned '%s' — outside vocabulary+base, every consumer falls back silently" % got)


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
			var m := RegEx.create_from_string(VARIANT_RX).search(f)
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
	# Every site must FETCH the suffix, not hardcode "" — cutscenes' arm, source half
	# (spelling-level; upgrades to behaviour when the single visual resolver folds).
	var sites := {
		"res://src/exploration/OverworldPlayer.gd": ["job_asset_path", "current_world_suffix"],
		"res://src/cutscene/CutsceneActor.gd": ["job_asset_path", "current_world_suffix"],
		"res://src/cutscene/CutsceneDialogue.gd": ["job_asset_path", "current_world_suffix", "cache_key := \"bust:%s:%s\""],
		"res://src/ui/SaveScreen.gd": ["job_asset_path", "current_world_suffix", "cache_key"],
	}
	for path in sites:
		var src := FileAccess.get_file_as_string(path)
		assert_gt(src.length(), 200, "CONTROL: %s read a real file" % path)
		for needle in sites[path]:
			assert_string_contains(src, needle,
				"%s must carry '%s' — a consumer off the helper re-splits the corpus" % [path, needle])
		assert_false(src.contains("\"res://assets/sprites/jobs/%s/overworld.png\" %"),
			"%s must not hand-build the base path any more" % path)
