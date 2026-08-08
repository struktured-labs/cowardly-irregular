extends GutTest

## Portraits must change with the world; an ABSENT variant must fall back to painted art

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const CD := preload("res://src/cutscene/CutsceneDialogue.gd")
const PORTRAIT_DIR := "res://assets/sprites/portraits"


func _job_ids() -> Array:
	var raw := FileAccess.get_file_as_string("res://data/jobs.json")
	if raw == "":
		return []
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return []
	var src: Variant = parsed.get("jobs", parsed)
	var out: Array = (src.keys() if src is Dictionary else [])
	out.sort()
	return out


func test_the_probe_is_WIRED_at_the_rung_that_actually_wins() -> void:
	# Anchor on the rung that RETURNS — probe-before-bust passes with the probe dead
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDialogue.gd")
	assert_ne(src, "", "CutsceneDialogue must be readable")
	var head := src.find("func _create_portrait")
	var base_load := src.find("ResourceLoader.exists(sprite_path)", head)
	var probe := src.find("current_world_suffix()", head)
	assert_true(head >= 0 and base_load > head, "the resolution function must be readable")
	assert_true(probe > head and probe < base_load,
		"the world probe must sit BEFORE the PORTRAIT_SPRITES load — below it the base " +
		"art returns first and the probe is unreachable, which is the defect this file " +
		"exists for and is invisible to every behaviour that only asks 'did a portrait load'")


func test_the_portrait_ACTUALLY_CHANGES_between_worlds() -> void:
	# Pins the VALUE, not the source order — survives a reorder that a source pin cannot
	var gs := get_node_or_null("/root/GameState")
	assert_not_null(gs, "GameState required — run via tools/run_tests.sh")
	if gs == null:
		return
	var suffixes: Array = []
	for s in Loader.WORLD_SUFFIXES:
		if s != "":
			suffixes.append(s)

	var inst = CD.new()
	autofree(inst)
	var restore: int = int(gs.current_world)
	gs.current_world = 1
	var unchanged: Array = []
	var checked := 0
	for job in _job_ids():
		var base_tex = inst._create_portrait(job)
		if base_tex == null:
			continue
		for w in range(2, 7):
			var suffix: String = suffixes[w - 2]
			if not FileAccess.file_exists("%s/%s_%s.png" % [PORTRAIT_DIR, job, suffix]):
				continue
			gs.current_world = w
			checked += 1
			if inst._create_portrait(job) == base_tex:
				unchanged.append("%s/%s" % [job, suffix])
			gs.current_world = 1
	gs.current_world = restore

	# A run that resolved nothing reports zero mismatches and reads like a clean pass
	assert_true(checked > 0,
		"asserted nothing — no job resolved a world variant, so this test could not fail")
	unchanged.sort()
	assert_eq(unchanged, [],
		("%d job/world pair(s) have world art on disk and STILL serve the medieval " +
		"portrait — the probe is present but not reached: %s") % [unchanged.size(), unchanged])
	assert_eq(int(gs.current_world), restore, "current_world must be restored")


func test_a_missing_variant_falls_back_to_the_painted_ART() -> void:
	# Every job, every world, resolves — whether or not world art exists yet
	var gs := get_node_or_null("/root/GameState")
	assert_not_null(gs, "GameState required — run via tools/run_tests.sh")
	if gs == null:
		return
	var jobs := _job_ids()
	assert_eq(jobs.size(), 14, "jobs.json must yield 14 ids, got %d" % [jobs.size()])

	var inst = CD.new()
	autofree(inst)
	var restore: int = int(gs.current_world)
	var blank: Array = []
	for world in range(1, 7):
		gs.current_world = world
		for job in jobs:
			if inst._create_portrait(job) == null:
				blank.append("%s in world %d" % [job, world])
	gs.current_world = restore
	blank.sort()
	assert_eq(blank, [],
		("job(s) with NO portrait in some world — a variant probe must never leave a " +
		"speaker faceless, it must fall back to the painted art: %s") % [blank])
	assert_eq(int(gs.current_world), restore, "current_world must be restored")


func test_world_dressed_portraits_on_disk_are_LOADABLE() -> void:
	# A .png is invisible to ResourceLoader until imported while FileAccess still sees it
	var dir := DirAccess.open(PORTRAIT_DIR)
	assert_not_null(dir, "portraits dir must be scannable")
	if dir == null:
		return
	var suffixes: Array = []
	for s in Loader.WORLD_SUFFIXES:
		if s != "":
			suffixes.append(s)

	var unimported: Array = []
	var found := 0
	for job in _job_ids():
		for suffix in suffixes:
			var path := "%s/%s_%s.png" % [PORTRAIT_DIR, job, suffix]
			if not FileAccess.file_exists(path):
				continue
			found += 1
			if not ResourceLoader.exists(path):
				unimported.append("%s_%s.png" % [job, suffix])
	unimported.sort()
	if found == 0:
		gut.p("NOTE: no world-dressed portraits on disk yet — guard arms when the art lands")
		assert_true(true, "nothing to verify")
		return
	assert_eq(unimported, [],
		("%d world portrait(s) on disk but NOT importable — they never render and the " +
		"lookup silently serves the base art: %s") % [unimported.size(), unimported])


func test_a_world_is_dressed_for_ALL_jobs_or_for_NONE() -> void:
	# One member transformed beside three who are not reads as a bug; none reads as style
	var jobs := _job_ids()
	assert_eq(jobs.size(), 14, "jobs.json must yield 14 ids")
	var partial: Array = []
	for suffix in Loader.WORLD_SUFFIXES:
		if suffix == "":
			continue
		var dressed := 0
		for job in jobs:
			if FileAccess.file_exists("%s/%s_%s.png" % [PORTRAIT_DIR, job, suffix]):
				dressed += 1
		if dressed > 0 and dressed < jobs.size():
			partial.append("%s: %d/%d" % [suffix, dressed, jobs.size()])
	partial.sort()
	assert_eq(partial, [],
		"world(s) with portraits for SOME jobs but not all — the party looks half-changed: %s" % [partial])
