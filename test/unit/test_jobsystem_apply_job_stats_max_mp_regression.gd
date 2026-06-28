extends GutTest

## tick 328: JobSystem._apply_job_stats now sets max_mp from the job's
## stat_modifiers.
##
## Pre-fix the 5-stat copy (max_hp / attack / defense / magic / speed)
## was MISSING max_mp. A freshly-assigned job left max_mp at
## Combatant.base_max_mp (50) instead of the job's canonical value:
##
##   Cleric: should be 70 → was 50  (−20 MP, 29% off)
##   Mage:   should be 80 → was 50  (−30 MP, 38% off)
##   Bard:   should be 65 → was 50  (−15 MP, 23% off)
##
## The gap only closed when something ELSE triggered recalculate_stats
## — level-up, equip/unequip, or passive change. So a brand-new Mage
## at level 1 with no equipment changes saw the wrong MP capacity until
## the first equip call later in GameLoop._create_party fired the recalc.
## In test contexts where _apply_job_stats is exercised directly without
## a subsequent recalc, max_mp is permanently wrong.
##
## Same omission class as ticks 287 / 316 / 317 / 318 — every 5-stat
## tuple in the codebase needs to be 6 to include max_mp.

const JOB_SYSTEM_PATH := "res://src/jobs/JobSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: max_mp arm exists in _apply_job_stats ───────────────

func test_apply_job_stats_has_max_mp_arm() -> void:
	var src := _read(JOB_SYSTEM_PATH)
	var fn_idx: int = src.find("func _apply_job_stats")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if mods.has(\"max_mp\"):"),
		"_apply_job_stats must check for max_mp in the job stat_modifiers")
	assert_true(body.contains("combatant.max_mp = mods[\"max_mp\"]"),
		"_apply_job_stats must set combatant.max_mp from the job mods")
	assert_true(body.contains("combatant.current_mp = combatant.max_mp"),
		"_apply_job_stats must reset current_mp to the new max (matches the max_hp pattern above)")


# ── Behavioral: assigning a job sets max_mp without a recalc ────────

func test_assign_job_sets_max_mp_immediately() -> void:
	assert_not_null(JobSystem, "JobSystem autoload required")
	if JobSystem == null:
		return

	# Create a bare Combatant — default max_mp=50, default base_max_mp=50.
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var c: Object = combatant_script.new()
	add_child_autofree(c)
	# Pre-state: default max_mp.
	assert_eq(c.max_mp, 50,
		"Combatant default max_mp must be 50 (pre-condition for the bug)")

	# Assign Mage — canonical max_mp is 80.
	assert_true(JobSystem.assign_job(c, "mage"),
		"assign_job('mage') must succeed")
	assert_eq(c.max_mp, 80,
		"after assign_job('mage'), max_mp must be 80 immediately (pre-fix: stayed at 50 until next recalc)")
	# current_mp must also reset to the new max (matches max_hp pattern).
	assert_eq(c.current_mp, 80,
		"current_mp must be reset to the new max_mp on job assignment")


# ── Behavioral: switching jobs updates max_mp again ─────────────────

func test_switching_job_updates_max_mp() -> void:
	assert_not_null(JobSystem, "JobSystem autoload required")
	if JobSystem == null:
		return

	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var c: Object = combatant_script.new()
	add_child_autofree(c)

	JobSystem.assign_job(c, "mage")
	assert_eq(c.max_mp, 80, "mage seeds max_mp=80")

	JobSystem.assign_job(c, "fighter")
	assert_eq(c.max_mp, 30,
		"switching to fighter (max_mp=30) must drop max_mp from 80 to 30 — pre-fix max_mp stayed at 80 because the assign didn't touch max_mp")

	JobSystem.assign_job(c, "cleric")
	assert_eq(c.max_mp, 70,
		"switching to cleric must raise max_mp to 70")


# ── Behavioral: jobs without max_mp don't crash ─────────────────────

func test_job_without_max_mp_field_leaves_existing() -> void:
	# Some jobs (e.g., minimal test fixtures or custom Scriptweaver creations)
	# might omit max_mp from stat_modifiers. The guard `if mods.has("max_mp")`
	# must skip the assignment, leaving the prior value intact.
	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var c: Object = combatant_script.new()
	add_child_autofree(c)
	c.max_mp = 999
	c.current_mp = 999

	# Call _apply_job_stats directly with a stat_modifiers dict that has NO max_mp.
	var stub_job: Dictionary = {
		"stat_modifiers": {"max_hp": 100, "attack": 10},
	}
	JobSystem._apply_job_stats(c, stub_job)
	assert_eq(c.max_mp, 999,
		"job without max_mp in stat_modifiers must leave existing max_mp untouched (no clobber to 0 or default)")
