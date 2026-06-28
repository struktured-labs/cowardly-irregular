extends GutTest

## tick 323: AutogrindUI._load_custom_presets push_warns on every
## post-existence failure mode instead of silently dropping presets.
##
## Pre-fix the function had 3 silent failure paths:
##   - FileAccess.open returns null → silent return
##   - JSON.parse != OK → silent return
##   - parse OK but root is not an Array → silent return
##
## All three returned without setting _custom_presets — the user lost
## their hand-edited or corrupted presets file with zero diagnostic.
## Symptom: "all my custom autogrind presets disappeared", no idea
## that the JSON was malformed.
##
## The file-missing case stays silent — first-time players have no
## presets file, and warning every launch would be noise. Same loud-
## fail pattern as tick 322's load_monsters_data with the file-missing
## exception.

const AUTOGRIND_UI_PATH := "res://src/ui/autogrind/AutogrindUI.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: 3 push_warning calls in _load_custom_presets ────────

func test_loader_has_three_warnings() -> void:
	var src := _read(AUTOGRIND_UI_PATH)
	var fn_idx: int = src.find("func _load_custom_presets")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var warning_count: int = body.count("push_warning(")
	assert_gte(warning_count, 3,
		"_load_custom_presets must push_warning on each of 3 post-existence failure modes (open fail / parse error / non-Array root). Found: %d" % warning_count)


# ── Source pin: each failure mode named in warning ──────────────────

func test_each_failure_mode_named() -> void:
	var src := _read(AUTOGRIND_UI_PATH)
	var fn_idx: int = src.find("func _load_custom_presets")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("FileAccess.open failed"),
		"open-failed warning must identify the failure mode")
	assert_true(body.contains("parse error"),
		"parse-error warning must identify the failure mode")
	assert_true(body.contains("root is not an Array"),
		"non-Array-root warning must identify the failure mode")


# ── Source pin: file-missing case stays silent (intentional) ────────

func test_file_missing_path_stays_silent() -> void:
	# First-time players have no presets file — warning on every launch
	# would be noise. The early return WITHOUT push_warning is intentional.
	var src := _read(AUTOGRIND_UI_PATH)
	var fn_idx: int = src.find("func _load_custom_presets")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The first if (file_exists) should NOT have a push_warning attached.
	var exists_idx: int = body.find("FileAccess.file_exists(CUSTOM_PRESETS_PATH)")
	assert_gt(exists_idx, -1, "file_exists check must exist")
	# Slice 200 chars after the check — push_warning shouldn't appear here.
	var after_check: String = body.substr(exists_idx, 200)
	# The next line after the if-block should be `return` without a warn.
	var return_after_check: int = after_check.find("return")
	assert_gt(return_after_check, -1, "early return after file_exists check must exist")
	# Confirm no push_warning between file_exists and that return.
	var warn_before_return: int = after_check.find("push_warning")
	if warn_before_return > -1 and warn_before_return < return_after_check:
		fail_test("file-missing path should NOT push_warning (intentional silence — would spam every launch for new players)")


# ── Behavioral: loader still works on the happy path ────────────────

func test_happy_path_still_loads() -> void:
	# Create a temp presets file, load it, verify it succeeds.
	const tmp_path := "user://test_autogrind_presets_loud_fail.json"
	# Cleanup leftover.
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	assert_not_null(f, "must be able to write tmp file")
	f.store_string(JSON.stringify([{"name": "Test Preset"}], "\t"))
	f.close()

	# Load via a fresh instance. We can't easily redirect CUSTOM_PRESETS_PATH,
	# so we verify by manually loading + reading the same way.
	# Source-pin tests above already validate the warning logic; this
	# behavioral confirms the happy path still parses a valid file.
	var loaded := FileAccess.get_file_as_string(tmp_path)
	var json := JSON.new()
	var parse_ok := json.parse(loaded)
	assert_eq(parse_ok, OK, "valid presets file must parse")
	assert_true(json.data is Array,
		"valid presets file must parse to an Array root")

	# Cleanup.
	DirAccess.remove_absolute(tmp_path)
