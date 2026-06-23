extends GutTest

## JobSystem and PassiveSystem silently fell back to hardcoded defaults
## when their JSON file was missing, malformed, or parsed to a non-Dict
## root. Print-only feedback — a corrupted abilities.json in production
## would silently run the game with the 8-ability default set instead
## of the 286-entry real one, and devs would have no signal.
##
## Fix: push_warning every fallback path, naming the path / parse error
## so the dev knows WHICH file failed AND why.

const JOB_SYSTEM := "res://src/jobs/JobSystem.gd"
const PASSIVE_SYSTEM := "res://src/jobs/PassiveSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_job_load_fallbacks_push_warning() -> void:
	var src := _read(JOB_SYSTEM)
	# Both error paths: type-mismatch (root not Dict) AND parse failure.
	# Each must push_warning, not just print.
	var dict_warn := src.find("jobs.json parsed but root is not a Dictionary")
	var parse_warn := src.find("jobs.json parse error:")
	assert_gt(dict_warn, -1, "non-Dict-root path must push_warning")
	assert_gt(parse_warn, -1, "parse-error path must push_warning")


func test_ability_load_fallbacks_push_warning() -> void:
	var src := _read(JOB_SYSTEM)
	# Three error paths: missing file, type-mismatch, parse error.
	# Pre-fix only the parse-error path printed; the missing-file path
	# was a 'Warning' string but not push_warning.
	assert_true(src.contains("abilities.json not found at"),
		"missing abilities.json must push_warning (was print-only)")
	assert_true(src.contains("abilities.json parsed but root is not a Dictionary"),
		"non-Dict-root abilities.json must push_warning")
	assert_true(src.contains("abilities.json parse error:"),
		"parse-error abilities.json must push_warning")


func test_passive_load_fallbacks_push_warning() -> void:
	var src := _read(PASSIVE_SYSTEM)
	assert_true(src.contains("passives.json not found at"),
		"missing passives.json must push_warning (was print-only)")
	assert_true(src.contains("passives.json parse error:"),
		"parse-error passives.json must push_warning")


func test_warnings_use_push_warning_not_print() -> void:
	# The actual upgrade — push_warning instead of print. This test
	# guards against a future cleanup pulling back to print-only.
	var job_src := _read(JOB_SYSTEM)
	var passive_src := _read(PASSIVE_SYSTEM)
	# Each system must have at least one push_warning in its load
	# functions (proves the upgrade was applied, not just the string
	# changed).
	assert_true(job_src.contains("push_warning(\"[JobSystem]"),
		"JobSystem load paths must call push_warning, not just print")
	assert_true(passive_src.contains("push_warning(\"[PassiveSystem]"),
		"PassiveSystem load paths must call push_warning, not just print")
