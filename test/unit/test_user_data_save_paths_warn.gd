extends GutTest

## tick 168 regression: user-data WRITE paths now push_warning on
## failure. Tick 167 covered LOAD paths; this round covers the
## symmetric save paths where silent failure is even worse — the
## player ACTIVELY triggered the save (rebind a key, export a
## script) and gets no indication the write actually landed.
##
## Loaders fixed:
##   - ScriptShareManager.import_file — print() everywhere
##     (5 failure modes silent in editor warnings panel)
##   - ScriptShareManager._write_export — print() on file-open
##     failure (silent in editor warnings panel)
##   - InputProfileManager.save_config — silent if file-open
##     fails. Player's custom rebinds revert to defaults next
##     launch with zero hint why.

const SCRIPT_SHARE := "res://src/autobattle/ScriptShareManager.gd"
const INPUT_PROFILE := "res://src/input/InputProfileManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── ScriptShareManager.import_file — 5 failure modes ────────────────────

func test_share_import_warns_on_file_missing() -> void:
	var src := _read(SCRIPT_SHARE)
	assert_true(src.contains("push_warning(\"[SHARE] Import file not found:"),
		"import_file must push_warning when file is missing — pre-fix used print()")


func test_share_import_warns_on_file_open_fail() -> void:
	var src := _read(SCRIPT_SHARE)
	assert_true(src.contains("push_warning(\"[SHARE] Import file exists but FileAccess.open failed:"),
		"import_file must push_warning on FileAccess.open failure")


func test_share_import_warns_on_parse_fail() -> void:
	var src := _read(SCRIPT_SHARE)
	# Must include the parser's error message (was silently dropped pre-fix).
	assert_true(src.contains("push_warning(\"[SHARE] Import file '%s' JSON parse error: %s\""),
		"import_file must push_warning with json.get_error_message() — pre-fix the error detail was dropped")


func test_share_import_warns_on_non_dict_root() -> void:
	# Pre-fix this case would crash on `var data: Dictionary =
	# json.data` when the parsed root was a non-Dict — the typed
	# assignment errors at runtime.
	var src := _read(SCRIPT_SHARE)
	assert_true(src.contains("push_warning(\"[SHARE] Import file '%s' parsed but root is not a Dictionary"),
		"import_file must check Dictionary root before the typed assignment — pre-fix this crashed silently")
	# Also pin the check exists in the code path.
	assert_true(src.contains("if not (json.data is Dictionary):"),
		"import_file must guard the Dictionary type check")


func test_share_import_warns_on_missing_required_fields() -> void:
	var src := _read(SCRIPT_SHARE)
	assert_true(src.contains("push_warning(\"[SHARE] Import file '%s' missing required 'type' or 'version' fields"),
		"import_file must push_warning when type/version fields are missing")


# ── ScriptShareManager._write_export ────────────────────────────────────

func test_share_export_warns_on_write_fail() -> void:
	var src := _read(SCRIPT_SHARE)
	assert_true(src.contains("push_warning(\"[SHARE] Could not open %s for write"),
		"_write_export must push_warning on FileAccess.open(WRITE) failure")
	# Include error code so devs can diagnose perms vs disk-full vs RO.
	assert_true(src.contains("FileAccess.get_open_error()"),
		"_write_export warning must include the FileAccess error code")


# ── InputProfileManager.save_config ─────────────────────────────────────

func test_input_save_config_warns_on_write_fail() -> void:
	var src := _read(INPUT_PROFILE)
	assert_true(src.contains("push_warning(\"[InputProfileManager] Could not open %s for write"),
		"save_config must push_warning when FileAccess.open(WRITE) fails — silent failure breaks rebind workflow")
	assert_true(src.contains("custom input bindings will NOT persist"),
		"save_config warning must explain user-visible consequence (bindings won't survive next launch)")
	assert_true(src.contains("FileAccess.get_open_error()"),
		"save_config warning must include FileAccess error code")


# ── Negative regressions: print() statements gone ───────────────────────

func test_share_import_no_longer_uses_print_for_failures() -> void:
	# Pin: the 4 failure-path `print(...)` calls from pre-fix must
	# be gone (replaced with push_warning).
	var src := _read(SCRIPT_SHARE)
	for fragment in [
		"print(\"[SHARE] File not found:",
		"print(\"[SHARE] Cannot open:",
		"print(\"[SHARE] Invalid JSON in",
		"print(\"[SHARE] Missing type/version",
	]:
		assert_false(src.contains(fragment),
			"old print() failure-path fragment must be gone: %s" % fragment)


func test_share_export_print_replaced_with_warning() -> void:
	var src := _read(SCRIPT_SHARE)
	assert_false(src.contains("print(\"[SHARE] Cannot write to"),
		"export's `Cannot write` print must be replaced with push_warning")


# ── Non-regression: success-path print preserved ────────────────────────

func test_share_success_prints_still_present() -> void:
	# Successful import/export still uses print (low-noise success
	# logging) — not converted to push_warning.
	var src := _read(SCRIPT_SHARE)
	assert_true(src.contains("print(\"[SHARE] Exported to %s\""),
		"successful export print preserved — not a failure mode")
	assert_true(src.contains("print(\"[SHARE] Applied script to %s\""),
		"successful apply print preserved")
