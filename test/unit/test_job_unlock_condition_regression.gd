extends GutTest

## tick 467: jobs.json unlock_condition field now actually gates
## advanced + meta jobs in the JobMenu (and any other caller via
## the new JobSystem.is_job_unlocked helper).
##
## Pre-tick jobs.json authored:
##   guardian: {type:"story", chapter:2, quest:"protectors_oath"}
##   ninja: {type:"achievement", id:"speed_demon"}
##   summoner: {type:"story", chapter:3, quest:"pact_of_eidolons"}
##   bossbinder: {type:"boss_defeat", boss_count:10}
##   skiptrotter: {type:"completion", requirement:"beat_game_once"}
##   speculator: {type:"story", chapter:2, quest:"market_crash"}
## but no code path read the field. JobMenu gated advanced+meta jobs
## purely on debug_log_enabled — either ALL were shown or none, with
## no progression in between.

const JOB_SYSTEM_PATH := "res://src/jobs/JobSystem.gd"
const JOB_MENU_PATH := "res://src/ui/JobMenu.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_helper_exists() -> void:
	var src := _read(JOB_SYSTEM_PATH)
	assert_true(src.contains("func is_job_unlocked"),
		"JobSystem must declare is_job_unlocked helper")
	# Pin all four condition types are handled.
	for ctype in ["story", "boss_defeat", "completion", "achievement"]:
		assert_true(src.contains("\"" + ctype + "\":"),
			"is_job_unlocked must handle unlock_condition type '%s'" % ctype)


func test_starter_jobs_unconditional() -> void:
	var src := _read(JOB_SYSTEM_PATH)
	var fn_idx: int = src.find("func is_job_unlocked")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Type 0 (starter) returns true unconditionally.
	assert_true(body.contains("if job_type == 0:") and body.contains("return true"),
		"is_job_unlocked must short-circuit true for type=0 starter jobs")


func test_debug_mode_unlocks_everything() -> void:
	var src := _read(JOB_SYSTEM_PATH)
	var fn_idx: int = src.find("func is_job_unlocked")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Pin the debug mode shortcut so dev workflow stays intact.
	assert_true(body.contains("debug_log_enabled") and body.contains("return true"),
		"is_job_unlocked must short-circuit true when GameState.debug_log_enabled is true (dev shortcut)")


func test_job_menu_consults_helper() -> void:
	var src := _read(JOB_MENU_PATH)
	var fn_idx: int = src.find("func _get_available_jobs")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("JobSystem.is_job_unlocked(job_id)"),
		"_get_available_jobs must consult JobSystem.is_job_unlocked")


func test_data_still_authors_unlock_conditions() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/jobs.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	# Pin that AT LEAST ONE advanced/meta job still authors
	# unlock_condition (some meta jobs intentionally have no story
	# unlock and stay debug-only).
	var found_with_cond: bool = false
	for jid in data.keys():
		var entry: Dictionary = data[jid]
		if int(entry.get("type", 0)) > 0:
			var cond: Variant = entry.get("unlock_condition", null)
			if cond is Dictionary and (cond as Dictionary).has("type"):
				found_with_cond = true
				break
	assert_true(found_with_cond,
		"jobs.json must still author at least one unlock_condition.type on a non-starter job")


func test_runtime_starter_always_unlocked() -> void:
	if JobSystem == null:
		pending("JobSystem autoload required")
		return
	# Find a starter job (type 0) — fighter is canonical.
	if not JobSystem.jobs.has("fighter"):
		pending("fighter job not in JobSystem.jobs")
		return
	assert_true(JobSystem.is_job_unlocked("fighter"),
		"fighter (starter) must always report unlocked")


func test_runtime_locked_advanced_when_debug_off() -> void:
	# A clean-save advanced job (e.g. guardian, chapter 2 required)
	# must report locked when:
	# - debug is OFF
	# - chapter2 cutscene flag is NOT set
	if JobSystem == null:
		pending("JobSystem autoload required")
		return
	if GameState == null:
		pending("GameState autoload required")
		return
	if not JobSystem.jobs.has("guardian"):
		pending("guardian job not in JobSystem.jobs")
		return
	# Snapshot & restore.
	var prior_debug: bool = bool(GameState.debug_log_enabled)
	var prior_constants: Dictionary = GameState.game_constants.duplicate(true)
	GameState.debug_log_enabled = false
	if GameState.game_constants.has("cutscene_flag_chapter2_complete"):
		GameState.game_constants["cutscene_flag_chapter2_complete"] = false
	assert_false(JobSystem.is_job_unlocked("guardian"),
		"guardian must be locked when chapter2 flag is unset AND debug mode is off")
	# Setting the flag should unlock it.
	GameState.game_constants["cutscene_flag_chapter2_complete"] = true
	assert_true(JobSystem.is_job_unlocked("guardian"),
		"guardian must unlock once cutscene_flag_chapter2_complete is true")
	# Restore.
	GameState.debug_log_enabled = prior_debug
	GameState.game_constants = prior_constants


func test_runtime_bossbinder_gated_on_count() -> void:
	if JobSystem == null:
		pending("JobSystem autoload required")
		return
	if GameState == null:
		pending("GameState autoload required")
		return
	if not JobSystem.jobs.has("bossbinder"):
		pending("bossbinder job not in JobSystem.jobs")
		return
	var prior_debug: bool = bool(GameState.debug_log_enabled)
	var prior_bosses: Array[String] = []
	for b in GameState.previously_fought_bosses:
		prior_bosses.append(str(b))
	GameState.debug_log_enabled = false
	GameState.previously_fought_bosses = []
	assert_false(JobSystem.is_job_unlocked("bossbinder"),
		"bossbinder must be locked at 0 boss defeats")
	# Cram 10 fake boss ids.
	for i in range(10):
		GameState.previously_fought_bosses.append("fake_boss_%d" % i)
	assert_true(JobSystem.is_job_unlocked("bossbinder"),
		"bossbinder must unlock at 10 boss defeats")
	# Restore.
	GameState.debug_log_enabled = prior_debug
	GameState.previously_fought_bosses = prior_bosses
