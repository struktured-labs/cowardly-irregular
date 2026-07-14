extends GutTest

## tick 364: SaveSystem._apply_save_data type-guards the
## automation block, one_shot_records, and autobattle_records.
##
## Pre-fix the code did:
##   var automation_data = data["automation"]
##   if automation_data.has("region_crack_levels") and AutogrindSystem:
##     AutogrindSystem.region_crack_levels = automation_data["region_crack_levels"]
##   ...
##   one_shot_records = data["one_shot_records"]
##   autobattle_records = data["autobattle_records"]
##
## A corrupted save with any of these slots non-Dict (null / int / str)
## crashed:
##   - `automation_data.has(...)` → Invalid call .has on Nil
##   - `AutogrindSystem.region_crack_levels = X` → typed Dictionary
##     assignment fails when X is null/int/str
##   - `one_shot_records = X` / `autobattle_records = X` → same
##
## Same defensive shape as tick 362's player.position guard.

const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: automation type guard exists ────────────────────────

func test_apply_save_data_guards_automation_block() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func _apply_save_data")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("automation_data is Dictionary"),
		"automation block must be type-guarded before .has() — pre-fix crashed on non-Dict")
	assert_true(body.contains("rcl is Dictionary"),
		"region_crack_levels must be type-guarded before typed-field assignment")
	assert_true(body.contains("lp is Dictionary"),
		"learned_patterns must be type-guarded before typed-field assignment")
	assert_true(body.contains("osr is Dictionary"),
		"one_shot_records must be type-guarded before typed-field assignment")
	assert_true(body.contains("ar is Dictionary"),
		"autobattle_records must be type-guarded before typed-field assignment")


# ── Behavioral: null automation block does not crash ────────────────

func test_null_automation_does_not_crash() -> void:
	var script: GDScript = load(SAVE_SYSTEM_PATH)
	var ss: Object = script.new()
	add_child_autofree(ss)
	# Pre-fix this crashed on `automation_data.has(...)` against Nil.
	ss._apply_save_data({"automation": null})
	# Survive: ss didn't blow up. (Nothing to assert about state since
	# AutogrindSystem is the autoload, not ss — the point is the call
	# didn't raise.)
	assert_true(true, "null automation must not crash the load")


# ── Behavioral: int automation block does not crash ─────────────────

func test_int_automation_does_not_crash() -> void:
	var script: GDScript = load(SAVE_SYSTEM_PATH)
	var ss: Object = script.new()
	add_child_autofree(ss)
	ss._apply_save_data({"automation": 42})
	assert_true(true, "int automation must not crash the load")


# ── Behavioral: null one_shot_records / autobattle_records keep prior

func test_null_records_keep_prior_state() -> void:
	var script: GDScript = load(SAVE_SYSTEM_PATH)
	var ss: Object = script.new()
	add_child_autofree(ss)
	# Seed prior state so we can verify it survives the malformed load.
	ss.one_shot_records = {"slime": {"count": 1, "best_rank": "A", "best_setup": 2}}
	ss.autobattle_records = {"goblin": {"count": 3, "best_turns": 4, "best_multiplier": 1.5}}

	ss._apply_save_data({
		"one_shot_records": null,
		"autobattle_records": null,
	})

	# Pre-fix the direct typed-Dictionary assignment from Nil crashed.
	# Post-fix the prior records survive unchanged.
	assert_eq(ss.one_shot_records.get("slime", {}).get("count", -1), 1,
		"prior one_shot_records must survive a malformed-load")
	assert_eq(ss.autobattle_records.get("goblin", {}).get("count", -1), 3,
		"prior autobattle_records must survive a malformed-load")


# ── Behavioral: valid records still load ────────────────────────────

func test_valid_records_still_apply() -> void:
	var script: GDScript = load(SAVE_SYSTEM_PATH)
	var ss: Object = script.new()
	add_child_autofree(ss)
	ss._apply_save_data({
		"one_shot_records": {"bat": {"count": 7, "best_rank": "S", "best_setup": 0}},
		"autobattle_records": {"rat_king": {"count": 2, "best_turns": 5, "best_multiplier": 2.0}},
	})
	assert_eq(ss.one_shot_records.get("bat", {}).get("count", -1), 7,
		"well-formed one_shot_records must still be loaded")
	assert_eq(ss.autobattle_records.get("rat_king", {}).get("count", -1), 2,
		"well-formed autobattle_records must still be loaded")
