extends GutTest

## tick 347: SaveSystem.load_settings push_warns on each of 3
## post-existence failure modes (open / parse / non-Dict root)
## instead of silently returning.
##
## Pre-fix the function had:
##   if not file:
##       return
##   if json.parse(...) != OK or not json.data is Dictionary:
##       file.close()
##       return
##   file.close()
##
## Both `if not file` and the combined parse/type check returned
## silently. Players who corrupted settings.json (interrupted write
## during shutdown, hand-edit gone wrong) lost ALL their settings —
## volume, text speed, controller overlay, color blind mode, BYOK
## config — with ZERO diagnostic. They'd open the game and everything
## was back to default with no clue why.
##
## Symptom: "the game keeps resetting my settings every time I launch
## it." Sometimes load_settings doesn't even get called (file_exists
## false) which is silent by design; the loud cases here are when the
## file IS there but unreadable / corrupt.
##
## Also separates parse-error from non-Dict-root — the pre-fix
## combined check misreported a JSON syntax error as a wrong-shape
## error. Same precision class as tick 345 (BossDialogue +
## PartyPersonas).

const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: 3 push_warning calls in load_settings ───────────────

func test_loader_has_three_warnings() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func load_settings")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var warning_count: int = body.count("push_warning(")
	assert_gte(warning_count, 3,
		"load_settings must push_warning on each of 3 post-existence failure modes. Found: %d" % warning_count)


# ── Source pin: each failure mode named ─────────────────────────────

func test_each_failure_mode_named() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func load_settings")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("FileAccess.open failed"),
		"open-fail warning must identify the failure mode")
	assert_true(body.contains("parse error"),
		"parse-error warning must identify the failure mode")
	assert_true(body.contains("root is not a Dictionary"),
		"non-Dict-root warning must identify the failure mode")


# ── Source pin: parse-error and non-Dict are SEPARATE checks ────────

func test_parse_and_dict_check_separated() -> void:
	# Pre-fix: `if json.parse(...) != OK or not json.data is Dictionary`
	# combined them into one branch — the warning couldn't distinguish.
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func load_settings")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The combined-OR pattern must be gone.
	assert_false(body.contains("!= OK or not json.data is Dictionary"),
		"the combined parse/type OR check must be removed — separate branches give precise warnings")
	# Each check must stand alone.
	assert_true(body.contains("if parse_result != OK:"),
		"parse-error branch must be its own if-statement")
	assert_true(body.contains("if not (json.data is Dictionary):"),
		"non-Dict-root branch must be its own if-statement")


# ── Source pin: file-missing stays silent (intentional) ─────────────

func test_file_missing_stays_silent() -> void:
	# First-launch players never have a settings file. Warning every
	# launch would be noise.
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func load_settings")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var exists_idx: int = body.find("FileAccess.file_exists(SETTINGS_PATH)")
	assert_gt(exists_idx, -1)
	var after: String = body.substr(exists_idx, 200)
	var return_idx: int = after.find("return")
	assert_gt(return_idx, -1)
	var warn_idx: int = after.find("push_warning")
	if warn_idx > -1 and warn_idx < return_idx:
		fail_test("file-missing path should NOT push_warning — would spam every launch for new players")


# ── Source pin: parse_result captured for deterministic file.close() ─

func test_parse_result_captured() -> void:
	# Same robustness fix as tick 344 and 346 — capture parse_result
	# to a var so file.close() happens once.
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func load_settings")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("var parse_result: int"),
		"parse_result must be captured to a var so file.close() runs deterministically")
