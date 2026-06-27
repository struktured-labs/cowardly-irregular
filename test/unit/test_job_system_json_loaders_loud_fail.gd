extends GutTest

## tick 275: JobSystem._load_job_data and _load_ability_data now
## emit push_warning on every failure mode (file missing / open
## failed / parse error / non-Dictionary root) before falling back
## to hardcoded defaults.
##
## Pre-fix the silent paths were:
##   _load_job_data: file-missing used print() (invisible in Godot
##     debug output), file-open-fail had NO warning at all.
##   _load_ability_data: file-open-fail had NO warning.
##
## Impact pre-fix: a missing/unreadable jobs.json replaced the 14
## jobs with the ~5 hardcoded fallback — every advanced/meta job
## silently lost. abilities.json same shape: 286 → handful of
## hardcoded defaults.

const JOB_SYSTEM := "res://src/jobs/JobSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _function_body(src: String, fname: String) -> String:
	var fn_idx: int = src.find("func " + fname)
	assert_gt(fn_idx, -1, "function %s must exist" % fname)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	return src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)


# ── _load_job_data: all 4 stages warn ──────────────────────────────

func test_load_job_data_warns_on_missing_file() -> void:
	var body := _function_body(_read(JOB_SYSTEM), "_load_job_data")
	assert_true(body.contains("push_warning(\"[JobSystem] jobs.json not found"),
		"_load_job_data must push_warning on missing file (was using print, invisible in debug output)")


func test_load_job_data_warns_on_open_fail() -> void:
	var body := _function_body(_read(JOB_SYSTEM), "_load_job_data")
	assert_true(body.contains("push_warning(\"[JobSystem] jobs.json exists but FileAccess.open failed"),
		"_load_job_data must push_warning when file exists but open fails (was silent)")


func test_load_job_data_warns_on_parse_error() -> void:
	var body := _function_body(_read(JOB_SYSTEM), "_load_job_data")
	assert_true(body.contains("push_warning(\"[JobSystem] jobs.json parse error"),
		"_load_job_data must push_warning on JSON parse error")


func test_load_job_data_warns_on_non_dict_root() -> void:
	var body := _function_body(_read(JOB_SYSTEM), "_load_job_data")
	assert_true(body.contains("push_warning(\"[JobSystem] jobs.json parsed but root is not a Dictionary"),
		"_load_job_data must push_warning when JSON root is not a Dictionary")


# ── _load_ability_data: all 4 stages warn ──────────────────────────

func test_load_ability_data_warns_on_missing_file() -> void:
	var body := _function_body(_read(JOB_SYSTEM), "_load_ability_data")
	assert_true(body.contains("push_warning(\"[JobSystem] abilities.json not found"),
		"_load_ability_data must push_warning on missing file")


func test_load_ability_data_warns_on_open_fail() -> void:
	var body := _function_body(_read(JOB_SYSTEM), "_load_ability_data")
	assert_true(body.contains("push_warning(\"[JobSystem] abilities.json exists but FileAccess.open failed"),
		"_load_ability_data must push_warning when file exists but open fails (was silent)")


func test_load_ability_data_warns_on_parse_error() -> void:
	var body := _function_body(_read(JOB_SYSTEM), "_load_ability_data")
	assert_true(body.contains("push_warning(\"[JobSystem] abilities.json parse error"),
		"_load_ability_data must push_warning on JSON parse error")


func test_load_ability_data_warns_on_non_dict_root() -> void:
	var body := _function_body(_read(JOB_SYSTEM), "_load_ability_data")
	assert_true(body.contains("push_warning(\"[JobSystem] abilities.json parsed but root is not a Dictionary"),
		"_load_ability_data must push_warning when JSON root is not a Dictionary")


# ── Negative pin: the old silent print() is gone ───────────────────

func test_no_silent_print_warning() -> void:
	# Pre-fix: print("Warning: jobs.json not found, using default jobs").
	# That string must be gone.
	var src := _read(JOB_SYSTEM)
	assert_false(src.contains("print(\"Warning: jobs.json not found"),
		"silent print() Warning prefix must be replaced with push_warning")


# ── Defaults path still wired (no crash from removed fallback) ────

func test_defaults_still_called_on_failure() -> void:
	# Defensive: every error path must still call the fallback so the
	# game can boot with reasonable defaults even if data files break.
	var jd_body := _function_body(_read(JOB_SYSTEM), "_load_job_data")
	var ad_body := _function_body(_read(JOB_SYSTEM), "_load_ability_data")
	assert_gte(jd_body.count("_create_default_jobs()"), 4,
		"_load_job_data must fall back to _create_default_jobs in all 4 failure modes")
	assert_gte(ad_body.count("_create_default_abilities()"), 4,
		"_load_ability_data must fall back to _create_default_abilities in all 4 failure modes")
