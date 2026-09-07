extends GutTest

## tick 295: JobSystem._create_default_jobs now includes rogue.
##
## Pre-fix the defaults fallback (used when data/jobs.json is missing
## or broken) had: fighter, cleric, mage, bard, scriptweaver.
##
## ROGUE WAS MISSING. A real gap — rogue is a starter job per
## CLAUDE.md and ships in every default party. With jobs.json broken,
## the rogue PC's stat_modifiers / abilities / passives silently
## degraded to whatever the downstream fallbacks produced (sprite,
## job menu, etc.).
##
## Scriptweaver is intentionally present (meta-job test surface for
## the fallback path — debug-mode gates the actual job menu entry).

const JOB_SYSTEM := "res://src/jobs/JobSystem.gd"

# Every starter job MUST be in the defaults — they're guaranteed to
# load in the starter party.
const STARTER_JOBS: Array[String] = ["fighter", "cleric", "mage", "rogue", "bard"]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Every starter job present in defaults ─────────────────────────

func test_every_starter_job_in_defaults() -> void:
	var src := _read(JOB_SYSTEM)
	var fn_idx: int = src.find("func _create_default_jobs")
	assert_gt(fn_idx, -1, "_create_default_jobs must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var missing: Array[String] = []
	for jid in STARTER_JOBS:
		# Default-jobs dict shape: "id": "<jid>", AND a literal key
		# entry "<jid>": { in the dict. Check the id form because the
		# key may be inside a multiline context that's harder to grep.
		if not body.contains("\"id\": \"%s\"" % jid):
			missing.append(jid)
	assert_eq(missing.size(), 0,
		"_create_default_jobs must include every starter job (CLAUDE.md strict): %s" % str(missing))


# ── Rogue specifically (the tick 295 fix) ────────────────────────

func test_rogue_default_entry_landed() -> void:
	var src := _read(JOB_SYSTEM)
	# Negative pin can't be done cleanly — scriptweaver mentions
	# nothing about rogue, but the absence pre-tick-295 was real.
	# Positive pin on the new entry.
	assert_true(src.contains("\"id\": \"rogue\""),
		"rogue must have an entry in _create_default_jobs (was missing pre-tick-295)")
	# Match the type (STARTER) and stat shape to detect a regression
	# where rogue silently drifts to wrong stats.
	var rogue_idx: int = src.find("\"id\": \"rogue\"")
	var slice: String = src.substr(rogue_idx, 600)
	assert_true(slice.contains("JobType.STARTER"),
		"rogue defaults entry must be tagged JobType.STARTER")
	assert_true(slice.contains("\"speed\": 16"),
		"rogue must have speed 16 (per live jobs.json — speed-stat striker)")


# ── Defaults still survive when actually called ──────────────────

func test_defaults_actually_load_via_callable() -> void:
	# Behavioral: instantiate JobSystem, force the defaults path by
	# checking what _create_default_jobs produces. We can't easily
	# stub FileAccess to "fail" so just call the function directly
	# and verify the dict it produces has rogue.
	var script: GDScript = load(JOB_SYSTEM)
	var inst: Object = script.new()
	add_child_autofree(inst)
	# Drive the defaults path. _create_default_jobs writes to the
	# instance's `jobs` Dictionary.
	inst._create_default_jobs()
	assert_true(inst.jobs.has("rogue"),
		"after _create_default_jobs runs, jobs['rogue'] must be present")
	var rogue: Dictionary = inst.jobs["rogue"]
	assert_eq(rogue.get("name", ""), "Rogue",
		"rogue defaults entry must carry display name")
	var mods: Dictionary = rogue.get("stat_modifiers", {})
	assert_eq(int(mods.get("speed", 0)), 16,
		"rogue speed_modifier must be 16")


# ── Each starter has stat_modifiers + abilities (sanity) ─────────

func test_each_starter_has_required_fields() -> void:
	var script: GDScript = load(JOB_SYSTEM)
	var inst: Object = script.new()
	add_child_autofree(inst)
	inst._create_default_jobs()
	var missing: Array[String] = []
	for jid in STARTER_JOBS:
		var entry: Dictionary = inst.jobs.get(jid, {})
		if entry.is_empty():
			missing.append("%s: entry missing" % jid)
			continue
		for required in ["id", "name", "type", "stat_modifiers", "abilities"]:
			if not entry.has(required):
				missing.append("%s missing %s" % [jid, required])
	assert_eq(missing.size(), 0,
		"each starter default must have id/name/type/stat_modifiers/abilities: %s" % str(missing))
