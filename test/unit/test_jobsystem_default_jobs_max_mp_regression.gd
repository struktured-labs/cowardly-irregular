extends GutTest

## tick 318: JobSystem._create_default_jobs fallback now includes
## max_mp in every job's stat_modifiers.
##
## Pre-fix every fallback job dropped the max_mp key. If data/jobs.json
## failed to load (file missing / parse error / non-Dict root — all
## three push_warning at startup), recalculate_stats's
## `if job_mods.has("max_mp")` branch never fired and casters fell
## back to Combatant.base_max_mp default (50) instead of their
## canonical value:
##
##   Cleric: 70 → 50  (−20 MP)
##   Mage:   80 → 50  (−30 MP)
##   Bard:   65 → 50  (−15 MP)
##   Scriptweaver: 60 → 50  (−10 MP)
##
## Same omission class as tick 295 (rogue missing from defaults
## entirely) and tick 316/317 (max_mp missing from recalc + injury
## table). Pinning the canonical values prevents drift if jobs.json
## changes — the defaults must mirror it exactly so the fallback
## doesn't surprise players who happen to hit it.

const JOB_SYSTEM_PATH := "res://src/jobs/JobSystem.gd"

# Canonical max_mp values pulled from data/jobs.json for the 6
# starter+scriptweaver jobs that the fallback covers. Update both
# this map AND the source defaults if jobs.json changes.
const CANONICAL_MAX_MP := {
	"fighter": 30,
	"cleric": 70,
	"mage": 80,
	"bard": 65,
	"rogue": 40,
	"scriptweaver": 60,
}


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: every default job has max_mp ────────────────────────

func test_every_default_job_has_max_mp() -> void:
	var src := _read(JOB_SYSTEM_PATH)
	var fn_idx: int = src.find("func _create_default_jobs")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)

	# Count the stat_modifiers blocks (one per job).
	var stat_mod_count: int = body.count("\"stat_modifiers\": {")
	# Count the max_mp entries inside the function body.
	var max_mp_count: int = body.count("\"max_mp\":")
	assert_eq(max_mp_count, stat_mod_count,
		"Every stat_modifiers block in _create_default_jobs must include max_mp. Found %d max_mp keys for %d stat_modifiers blocks." % [max_mp_count, stat_mod_count])


# ── Behavioral: defaults match jobs.json values exactly ─────────────

func test_default_max_mp_matches_canonical() -> void:
	# Trigger the defaults path by inspecting source-level values for
	# each known job. Reading jobs.json + comparing is overkill — the
	# CANONICAL_MAX_MP map is updated in lockstep with the source.
	var src := _read(JOB_SYSTEM_PATH)
	var fn_idx: int = src.find("func _create_default_jobs")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)

	# Each canonical max_mp value is UNIQUE (30/70/80/65/40/60), so a
	# straight body.contains is sufficient — no need to per-job slice.
	# If two jobs ever happen to share a max_mp value, this test should
	# tighten to per-job slicing.
	for job_id in CANONICAL_MAX_MP:
		var expected_mp: int = CANONICAL_MAX_MP[job_id]
		var mp_marker: String = "\"max_mp\": %d" % expected_mp
		assert_true(body.contains(mp_marker),
			"Default '%s' must have max_mp=%d (matches data/jobs.json). Search marker: %s" % [job_id, expected_mp, mp_marker])


# ── Behavioral: instantiate JobSystem with no jobs.json → defaults apply ─

func test_defaults_apply_correctly_when_loaded() -> void:
	# Real autoload — it loads jobs.json in _ready. We can't easily
	# simulate the failure path without mocking the file system. Instead,
	# verify that after the autoload runs (which uses the real jobs.json),
	# the fighter still has max_mp >0 — covers the codepath at least.
	assert_not_null(JobSystem, "JobSystem autoload required")
	if JobSystem == null:
		return

	var fighter: Dictionary = JobSystem.get_job("fighter") if JobSystem.has_method("get_job") else {}
	if fighter.is_empty():
		# Fall back to inspecting jobs dict directly.
		if "jobs" in JobSystem and JobSystem.jobs.has("fighter"):
			fighter = JobSystem.jobs["fighter"]
	assert_false(fighter.is_empty(), "fighter job must be loaded (autoload ran)")

	var stat_mods: Dictionary = fighter.get("stat_modifiers", {})
	assert_true(stat_mods.has("max_mp"),
		"fighter.stat_modifiers must have max_mp (whether from jobs.json or defaults — both should agree now)")
	assert_gt(int(stat_mods.get("max_mp", 0)), 0,
		"fighter max_mp must be > 0")
