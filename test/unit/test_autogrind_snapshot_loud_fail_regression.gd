extends GutTest

## tick 344: AutogrindSystem.load_grind_snapshot push_warns on every
## post-existence failure mode instead of silently returning {}.
##
## Pre-fix the function had 4 silent failure paths:
##   - FileAccess.open returns null → silent {}
##   - JSON.parse != OK → silent {}
##   - parse OK but root is not a Dictionary → silent {}
##   - version mismatch (game-version bump) → silent {}
##
## All 4 returned {} with zero diagnostic. The player's resume button
## vanished after a corrupted save (interrupted write, hand-edit) with
## no clue why. Same loud-fail pattern as ticks 322 (load_monsters_
## data) and 323 (load_custom_presets).
##
## The file-missing case stays silent — most players never have a
## snapshot.

const AUTOGRIND_SYSTEM_PATH := "res://src/autogrind/AutogrindSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: 4 push_warning calls in load_grind_snapshot ─────────

func test_loader_has_four_warnings() -> void:
	var src := _read(AUTOGRIND_SYSTEM_PATH)
	var fn_idx: int = src.find("func load_grind_snapshot")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var warning_count: int = body.count("push_warning(")
	assert_gte(warning_count, 4,
		"load_grind_snapshot must push_warning on each of 4 post-existence failure modes. Found: %d" % warning_count)


# ── Source pin: each failure mode named ─────────────────────────────

func test_each_failure_mode_named() -> void:
	var src := _read(AUTOGRIND_SYSTEM_PATH)
	var fn_idx: int = src.find("func load_grind_snapshot")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("FileAccess.open failed"),
		"open-fail warning must identify the cause")
	assert_true(body.contains("parse error"),
		"parse-error warning must identify the cause")
	assert_true(body.contains("root is not a Dictionary"),
		"non-Dict-root warning must identify the cause")
	assert_true(body.contains("version mismatch"),
		"version-mismatch warning must identify the cause (new in this tick — pre-fix the version check silently returned {})")


# ── Source pin: file-missing stays silent (intentional) ─────────────

func test_file_missing_stays_silent() -> void:
	# Most players never have a snapshot. Warning every game-start
	# would be noise. The first if (file_exists check) should NOT
	# have a push_warning.
	var src := _read(AUTOGRIND_SYSTEM_PATH)
	var fn_idx: int = src.find("func load_grind_snapshot")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)

	var exists_idx: int = body.find("FileAccess.file_exists(SNAPSHOT_PATH)")
	assert_gt(exists_idx, -1)
	# Walk forward to the next return statement.
	var after_exists: String = body.substr(exists_idx, 200)
	var return_idx: int = after_exists.find("return")
	assert_gt(return_idx, -1)
	# Verify no push_warning between file_exists and that return.
	var warn_idx: int = after_exists.find("push_warning")
	if warn_idx > -1 and warn_idx < return_idx:
		fail_test("file-missing path should NOT push_warning — would spam every launch for new players")


# ── Source pin: parse_result captured before file.close() ───────────

func test_parse_result_captured_before_close() -> void:
	# Subtle robustness — the prior version was:
	#   if json.parse(file.get_as_text()) != OK:
	#       file.close()
	#       return {}
	#   file.close()
	# The post-fix layout extracts parse_result to a var so the file
	# closes ONCE (not in two arms). Pin the new pattern.
	var src := _read(AUTOGRIND_SYSTEM_PATH)
	var fn_idx: int = src.find("func load_grind_snapshot")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("var parse_result: int"),
		"parse_result must be captured to a var so file.close() runs exactly once")
