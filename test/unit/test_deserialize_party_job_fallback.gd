extends GutTest

## tick 188 regression: GameLoop._restore_party_from_save_data now handles
## JobSystem.assign_job failure gracefully. Pre-fix the return
## value was ignored — if the save's job_id was unknown
## (Scriptweaver custom job removed from jobs.json, save-format
## drift, corrupted save data), JobSystem.assign_job would
## push_warning AND return false, leaving the character with
## NO job. Subsequent code (assign_secondary_job, equip_weapon)
## would silently no-op or crash on attribute access.
##
## Fix: primary job falls back to "fighter" on assign failure
## (so the character at least has a valid playable state).
## Secondary job stays unset on failure (secondary is optional).
##
## Audit results for tick 188 scope:
##   - SaveSystem.save_game / quick_save / auto_save callers:
##     save_failed signal listener at GameLoop._on_any_save_failed
##     already shows a Toast on failure. Callers that ignore the
##     bool return still get player-visible failure feedback via
##     the signal path. Clean ✓
##   - JobSystem.assign_job in default-party setup paths (hero/
##     mira/zack/etc.): hardcoded job IDs ("fighter", "cleric"),
##     always succeed in practice. Edge case only ✓
##   - _restore_party_from_save_data at line ~1682: HIGH-IMPACT path, fixed
##     here

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _restore_party_from_save_data_body() -> String:
	# _restore_party_from_save_data is the function around line 1672 that
	# rebuilds party from save. Find by signature.
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _restore_party_from_save_data")
	assert_gt(idx, -1, "_restore_party_from_save_data must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


# ── Primary job fallback ───────────────────────────────────────────────

func test_assign_job_failure_falls_back_to_fighter() -> void:
	var body := _restore_party_from_save_data_body()
	# Pin: the failure branch falls back to fighter.
	assert_true(body.contains("if not JobSystem.assign_job(c, job_id):"),
		"_restore_party_from_save_data must check assign_job return value")
	assert_true(body.contains("JobSystem.assign_job(c, \"fighter\")"),
		"primary job failure must fall back to 'fighter' so character has a valid state")


func test_primary_job_failure_pushes_warning() -> void:
	var body := _restore_party_from_save_data_body()
	# Pin: push_warning surfaces the cause in CI/editor.
	assert_true(body.contains("push_warning(\"[GameLoop] _restore_party_from_save_data: assign_job"),
		"primary job failure must push_warning")
	# Pin the warning message includes the failing id + character.
	assert_true(body.contains("falling back to 'fighter'"),
		"warning message must say what fallback is being applied")


# ── Secondary job graceful no-op ───────────────────────────────────────

func test_secondary_job_failure_no_fallback() -> void:
	# Secondary is optional — failure should warn but not fall
	# back to anything (leaving secondary unset is acceptable).
	var body := _restore_party_from_save_data_body()
	assert_true(body.contains("if not JobSystem.assign_secondary_job(c, sec_id):"),
		"_restore_party_from_save_data must check assign_secondary_job return")
	assert_true(body.contains("leaving secondary unset"),
		"secondary failure warning must say 'leaving secondary unset' (no fallback)")


func test_secondary_failure_does_not_fall_back_to_default() -> void:
	# Negative pin: secondary failure must NOT fall back to
	# "fighter" or any other default — secondary is optional.
	var body := _restore_party_from_save_data_body()
	# The sec_id block must not have a "JobSystem.assign_secondary_job(c, \"fighter\")"
	# fallback (or similar) anywhere.
	var sec_idx: int = body.find("if sec_id != \"\":")
	assert_gt(sec_idx, -1, "secondary job block must exist")
	# Look at the rest of the secondary block (next ~400 chars).
	var sec_block: String = body.substr(sec_idx, 500)
	# Should NOT contain a fallback assign call.
	assert_false(sec_block.contains("JobSystem.assign_secondary_job(c, \"fighter\")"),
		"secondary job failure must NOT fall back to a default — leaving unset is correct semantic")


# ── Non-regression: legacy "job" field still handled ────────────────────

func test_legacy_job_field_still_handled() -> void:
	# Pre-existing legacy-saves handling preserved.
	var body := _restore_party_from_save_data_body()
	assert_true(body.contains("if job_id == \"\" and entry.has(\"job\") and entry[\"job\"] is String:"),
		"legacy 'job' field handling preserved")


func test_empty_job_id_defaults_to_fighter() -> void:
	# Pre-existing empty-string handling preserved.
	var body := _restore_party_from_save_data_body()
	assert_true(body.contains("if job_id == \"\":\n\t\t\tjob_id = \"fighter\""),
		"empty job_id default-to-fighter preserved")


# ── Cross-pin: tick 180 assign_job warning ─────────────────────────────

func test_job_system_assign_job_warning_preserved() -> void:
	# Tick 180's JobSystem-side warning preserved — provides the
	# detailed cause that complements GameLoop's recovery action.
	var src: String = FileAccess.get_file_as_string("res://src/jobs/JobSystem.gd")
	assert_true(src.contains("push_warning(\"[JobSystem] assign_job: job_id"),
		"tick 180 JobSystem.assign_job warning preserved")
