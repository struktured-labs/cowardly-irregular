extends GutTest

## tick 319: PassiveSystem._create_default_passives covers every
## passive referenced by JobSystem._create_default_jobs's starter
## passive_abilities.
##
## Pre-fix Bard's default passive 'encore' was MISSING from the
## PassiveSystem fallback. If BOTH jobs.json AND passives.json failed
## to load (independent push_warning paths — file missing / parse
## error / non-Dict root), equip_passive("encore") would fire its
## "passive_id not found in passives table" warning and the Bard's
## passive slot stayed empty. Same silent-fallback gap class as
## tick 295 (rogue missing from JobSystem defaults) and tick 318
## (max_mp missing from JobSystem stat_modifiers).
##
## Pinning the cross-file invariant (every passive_abilities ref in
## JobSystem defaults must exist in PassiveSystem defaults) prevents
## the gap from re-opening if either file's defaults are extended.

const JOB_SYSTEM_PATH := "res://src/jobs/JobSystem.gd"
const PASSIVE_SYSTEM_PATH := "res://src/jobs/PassiveSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: encore exists in PassiveSystem defaults ─────────────

func test_encore_exists_in_passive_defaults() -> void:
	var src := _read(PASSIVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func _create_default_passives")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"encore\":"),
		"encore must exist in PassiveSystem defaults — Bard's default passive_abilities references it")
	assert_true(body.contains("\"song_duration_bonus\""),
		"encore must include meta_effects.song_duration_bonus (mirrors data/passives.json)")


# ── Cross-file invariant: every JobSystem default passive ref exists ─

func test_every_job_default_passive_is_in_passive_defaults() -> void:
	var job_src := _read(JOB_SYSTEM_PATH)
	var passive_src := _read(PASSIVE_SYSTEM_PATH)
	# Slice JobSystem._create_default_jobs.
	var fn_idx: int = job_src.find("func _create_default_jobs")
	assert_gt(fn_idx, -1)
	var next_fn: int = job_src.find("\nfunc ", fn_idx + 1)
	var job_body: String = job_src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else job_src.substr(fn_idx)
	# Slice PassiveSystem._create_default_passives.
	var pfn_idx: int = passive_src.find("func _create_default_passives")
	assert_gt(pfn_idx, -1)
	var pnext_fn: int = passive_src.find("\nfunc ", pfn_idx + 1)
	var passive_body: String = passive_src.substr(pfn_idx, pnext_fn - pfn_idx) if pnext_fn > 0 else passive_src.substr(pfn_idx)

	# Extract every passive_abilities entry from job_body.
	var rx := RegEx.new()
	rx.compile("\"passive_abilities\":\\s*\\[([^\\]]*)\\]")
	var matches: Array = rx.search_all(job_body)
	var all_refs: Array[String] = []
	for m in matches:
		var arr_str: String = m.get_string(1)
		var rx2 := RegEx.new()
		rx2.compile("\"([a-z_]+)\"")
		for m2 in rx2.search_all(arr_str):
			all_refs.append(m2.get_string(1))

	# Verify each ref exists in passive_body as a key.
	var missing: Array[String] = []
	for ref in all_refs:
		var marker: String = "\"%s\":" % ref
		if not passive_body.contains(marker):
			missing.append(ref)
	assert_eq(missing.size(), 0,
		"Every passive_abilities ref in JobSystem defaults must exist in PassiveSystem defaults. Missing: %s" % str(missing))


# ── Behavioral: PassiveSystem.get_passive('encore') returns data ────

func test_get_passive_encore_returns_data() -> void:
	# Real autoload — passives.json IS available, so this just exercises
	# the canonical path. The defaults path runs only when jobs.json /
	# passives.json fail to load; that's covered by the source pin above.
	assert_not_null(PassiveSystem, "PassiveSystem autoload required")
	if PassiveSystem == null:
		return

	var encore: Dictionary = PassiveSystem.get_passive("encore") if PassiveSystem.has_method("get_passive") else {}
	assert_false(encore.is_empty(),
		"PassiveSystem.get_passive('encore') must return data — confirms either the JSON OR the new default covers it")
