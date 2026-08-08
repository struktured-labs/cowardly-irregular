extends GutTest

## Regression: dialogue portraits must change with the world.
##
## struktured, 2026-08-08, while playing: "the portraits have to change from one world to
## another in addition to the character sprites (which cowir-sprites already did)."
##
## The world-dressed BUST path already existed and was correct — driven across all six
## worlds it resolves idle.png / idle_suburban.png / ... / idle_abstract.png, and every one
## loads. It was also UNREACHABLE: _create_portrait tries PORTRAIT_SPRITES first, and all 14
## jobs have painted portrait art, so the bust ran for 0 of them. A correct mechanism behind
## a rung that always wins is indistinguishable from a missing one.
##
## So rung 1 now probes for <portrait>_<world>.png. The load-bearing property is that an
## ABSENT variant falls back to the base art — otherwise this would hide every painted
## portrait behind a broken path, which is the "never overwrite artist sprites" rule
## violated at the lookup rather than by a write.

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
	# Source pin with a reason: the bust path was already correct and never ran, so
	# "a world-dressed portrait mechanism exists" is not the property worth asserting.
	#
	# ⚠️ The rung that WINS is the PORTRAIT_SPRITES load, NOT the bust. My first version
	# asserted probe-before-bust and PASSED with the probe moved below the base load —
	# dead code, the exact defect, scored green. Anchor on the thing that returns.
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
	# The behavioural arm, and the one that survives a refactor: pin the VALUE, not the
	# source order. A job with world art on disk must hand back a DIFFERENT texture in a
	# dressed world than in medieval — which is the thing he asked for, stated as an
	# outcome rather than as the presence of a mechanism.
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

	# Control naming a known-present member: a run that resolved nothing would report
	# zero mismatches and read exactly like a clean pass.
	assert_true(checked > 0,
		"asserted nothing — no job resolved a world variant, so this test could not fail")
	unchanged.sort()
	assert_eq(unchanged, [],
		("%d job/world pair(s) have world art on disk and STILL serve the medieval " +
		"portrait — the probe is present but not reached: %s") % [unchanged.size(), unchanged])
	assert_eq(int(gs.current_world), restore, "current_world must be restored")


func test_a_missing_variant_falls_back_to_the_painted_ART() -> void:
	# The safety property, driven. For every job and every world, a portrait must resolve —
	# whether or not world-dressed art exists yet.
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
	# A generated .png is invisible to ResourceLoader until imported, while FileAccess sees
	# it — so art can be present, correctly named, and never render. Cost this lane 42
	# sheets once already.
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
	# Same rule as the battle sheets: one party member transformed beside three who are not
	# reads as a bug; nobody transformed reads as a style.
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
