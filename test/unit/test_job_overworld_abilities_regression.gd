extends GutTest

## tick 468: jobs.json overworld_abilities field now actually
## delivers two of its three Ninja promises:
##   - movement_speed_bonus: 1.5 → OverworldPlayer base_speed × 1.5
##   - reduced_encounter_rate: 0.5 → EncounterSystem rolled chance × 0.5
##
## Pre-tick the entire overworld_abilities key was decoration —
## equipping Ninja gave the in-battle abilities (already wired)
## but NOT the overworld bonuses the data and class fantasy
## promised. can_skip_cutscenes still requires cutscene UI
## integration; deferred.

const PLAYER_PATH := "res://src/exploration/OverworldPlayer.gd"
const ENCOUNTER_PATH := "res://src/encounters/EncounterSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_movement_helper_reads_job_overworld_abilities() -> void:
	var src := _read(PLAYER_PATH)
	var fn_idx: int = src.find("func _party_movement_speed_bonus")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("overworld_abilities"),
		"_party_movement_speed_bonus must read overworld_abilities from job data")
	assert_true(body.contains("oa.get(\"movement_speed_bonus\", 1.0)"),
		"helper must extract movement_speed_bonus from the overworld_abilities dict")
	# Pin job_id + secondary_job_id checks so dual-class builds work.
	assert_true(body.contains("\"job_id\", \"secondary_job_id\""),
		"helper must scan BOTH job slots so secondary-job builds get the bonus")


func test_encounter_helper_exists() -> void:
	var src := _read(ENCOUNTER_PATH)
	assert_true(src.contains("func _party_encounter_rate_reduction"),
		"EncounterSystem must declare _party_encounter_rate_reduction helper")
	assert_true(src.contains("oa.get(\"reduced_encounter_rate\", 1.0)"),
		"helper must read reduced_encounter_rate from overworld_abilities")


func test_check_for_encounter_applies_reduction() -> void:
	var src := _read(ENCOUNTER_PATH)
	var fn_idx: int = src.find("func check_for_encounter")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_party_encounter_rate_reduction()"),
		"check_for_encounter must consult _party_encounter_rate_reduction")
	assert_true(body.contains("chance *= enc_reduction"),
		"reduction must multiplicatively scale chance before the randf roll")
	# Order: reduction must happen BEFORE the randf comparison.
	var reduction_idx: int = body.find("chance *= enc_reduction")
	var roll_idx: int = body.find("if roll < chance:")
	assert_gt(reduction_idx, -1)
	assert_gt(roll_idx, -1)
	assert_lt(reduction_idx, roll_idx,
		"reduction must apply BEFORE the rate roll")


func test_data_still_authors_ninja_overworld() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/jobs.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("ninja"), "ninja job must exist in data")
	var oa: Variant = data["ninja"].get("overworld_abilities", {})
	assert_true(oa is Dictionary)
	assert_gt(float((oa as Dictionary).get("movement_speed_bonus", 0.0)), 1.0,
		"ninja must still author movement_speed_bonus > 1.0")
	assert_lt(float((oa as Dictionary).get("reduced_encounter_rate", 2.0)), 1.0,
		"ninja must still author reduced_encounter_rate < 1.0")


func test_runtime_no_ninja_no_reduction() -> void:
	var es = Engine.get_main_loop().root.get_node_or_null("EncounterSystem")
	assert_not_null(es, "EncounterSystem autoload must be present")
	if es == null:
		return
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var party: Array[Dictionary] = []
	party.append({"name": "F", "job_id": "fighter"})
	gs.player_party = party
	assert_eq(es._party_encounter_rate_reduction(), 1.0,
		"no-Ninja party must return 1.0 (no reduction)")
	var restore: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore.append(m)
	gs.player_party = restore


func test_runtime_ninja_party_reduces_rate() -> void:
	var es = Engine.get_main_loop().root.get_node_or_null("EncounterSystem")
	assert_not_null(es, "EncounterSystem autoload must be present")
	if es == null:
		return
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		return
	if JobSystem == null or not JobSystem.jobs.has("ninja"):
		pending("ninja job required")
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var party: Array[Dictionary] = []
	party.append({"name": "N", "job_id": "ninja"})
	gs.player_party = party
	var r: float = es._party_encounter_rate_reduction()
	assert_lt(r, 1.0,
		"Ninja party member must reduce encounter rate (<1.0)")
	# Restore.
	var restore: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore.append(m)
	gs.player_party = restore


func test_runtime_ninja_secondary_job_counts() -> void:
	var es = Engine.get_main_loop().root.get_node_or_null("EncounterSystem")
	assert_not_null(es, "EncounterSystem autoload must be present")
	if es == null:
		return
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		return
	if JobSystem == null or not JobSystem.jobs.has("ninja"):
		pending("ninja job required")
		return
	var prior_party: Array = gs.player_party.duplicate(true)
	var party: Array[Dictionary] = []
	# Primary = fighter, secondary = ninja — should still grant the reduction.
	party.append({"name": "FN", "job_id": "fighter", "secondary_job_id": "ninja"})
	gs.player_party = party
	var r: float = es._party_encounter_rate_reduction()
	assert_lt(r, 1.0,
		"Ninja secondary job must also grant the reduction")
	var restore: Array[Dictionary] = []
	for m in prior_party:
		if m is Dictionary:
			restore.append(m)
	gs.player_party = restore
