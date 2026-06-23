extends GutTest

## tick 59: starter jobs gain abilities_at_level data so tick 58's
## plumbing actually fires for player characters. Without populated
## data the unlock system was just plumbing — this tick makes it
## visible in the player's combat menu as they level up.
##
## Assertions also pin save-compat retroactive grant in JobSystem.
## assign_job so a save loaded after this data change unlocks any
## already-eligible abilities instead of waiting for the next level.

const JOB_SYSTEM := "res://src/jobs/JobSystem.gd"
const JOBS_JSON := "res://data/jobs.json"
const ABILITIES_JSON := "res://data/abilities.json"


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, path + " must be readable")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Dictionary, path + " must parse as Dictionary")
	return parsed as Dictionary


func test_fighter_has_abilities_at_level() -> void:
	var jobs := _load_json(JOBS_JSON)
	assert_true(jobs.has("fighter"), "fighter job must exist")
	var fighter: Dictionary = jobs["fighter"]
	assert_true(fighter.has("abilities_at_level"),
		"fighter must declare abilities_at_level — exercises tick 58's plumbing")
	var unlocks: Dictionary = fighter["abilities_at_level"]
	# Pin two thresholds so the system is testable.
	assert_gte(unlocks.size(), 2,
		"fighter must have at least 2 level thresholds (low + mid) so the unlock arc is felt across leveling")


func test_cleric_has_abilities_at_level() -> void:
	var jobs := _load_json(JOBS_JSON)
	assert_true(jobs.has("cleric"), "cleric job must exist")
	var cleric: Dictionary = jobs["cleric"]
	assert_true(cleric.has("abilities_at_level"),
		"cleric must declare abilities_at_level")


func test_starter_job_unlock_abilities_actually_exist() -> void:
	# Critical: every ability referenced in abilities_at_level must
	# resolve in abilities.json. A typo there would silently grant
	# nothing.
	var jobs := _load_json(JOBS_JSON)
	var abilities := _load_json(ABILITIES_JSON)
	for jid in ["fighter", "cleric"]:
		var unlocks: Dictionary = jobs.get(jid, {}).get("abilities_at_level", {})
		for level_key in unlocks.keys():
			var ids: Array = unlocks[level_key]
			for ability_id in ids:
				assert_true(abilities.has(str(ability_id)),
					"%s level-%s unlock '%s' must resolve in abilities.json" % [jid, str(level_key), str(ability_id)])


func test_starter_job_unlocks_not_already_in_base_list() -> void:
	# Pin the design intent: level unlocks are ADDITIONS, not
	# duplicates of the base list. A duplicate would still work
	# (learn_ability dedupes) but signals data drift.
	var jobs := _load_json(JOBS_JSON)
	for jid in ["fighter", "cleric"]:
		var job: Dictionary = jobs[jid]
		var base: Array = job.get("abilities", [])
		var unlocks: Dictionary = job.get("abilities_at_level", {})
		for level_key in unlocks.keys():
			var ids: Array = unlocks[level_key]
			for ability_id in ids:
				assert_false(str(ability_id) in base,
					"%s level-%s unlock '%s' must NOT also appear in the base abilities[] list — data drift" % [jid, str(level_key), str(ability_id)])


func test_assign_job_retroactively_grants() -> void:
	# Save-compat: loading a save at level N must grant any
	# abilities_at_level entries up to N, not wait for the next
	# level-up.
	var src := FileAccess.get_file_as_string(JOB_SYSTEM)
	var idx := src.find("func assign_job")
	assert_gt(idx, -1, "assign_job must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	var body := src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("learn_abilities_for_level(combatant, combatant.job_level)"),
		"assign_job must retroactively call learn_abilities_for_level so save-compat doesn't soft-break the unlock system")
	# Guard against re-running for fresh level-1 combatants (no-op
	# but still a function call — cleaner to skip).
	assert_true(body.contains("combatant.job_level > 1"),
		"assign_job should skip the retroactive call when job_level == 1 (nothing to grant)")
