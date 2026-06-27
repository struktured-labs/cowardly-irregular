extends GutTest

## tick 276: SoundManager._load_music_manifest now uses the same
## 5-stage loud-fail shape as _load_sfx_manifest (tick 166):
##
##   1. file missing       → "[MUSIC] music_manifest.json not found at X"
##   2. file-open failed   → "[MUSIC] music_manifest.json exists but FileAccess.open failed"
##   3. parse error        → "[MUSIC] music_manifest.json parse error"
##   4. non-Dict root      → "[MUSIC] music_manifest.json parsed but root is not a Dictionary"
##   5. missing tracks key → "[MUSIC] music_manifest.json parsed but missing 'tracks' key"
##
## Pre-fix the missing-file case had no file_exists pre-check —
## it conflated under the single "Cannot open" warning with no path
## printed, so a deleted/moved music_manifest.json looked identical
## to a permission issue.

const SOUND_MANAGER := "res://src/audio/SoundManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _function_body(src: String, fname: String) -> String:
	var fn_idx: int = src.find("func " + fname)
	assert_gt(fn_idx, -1, "function %s must exist" % fname)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	return src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)


# ── All 5 stages warn ───────────────────────────────────────────────

func test_missing_file_warns_with_path() -> void:
	var body := _function_body(_read(SOUND_MANAGER), "_load_music_manifest")
	assert_true(body.contains("FileAccess.file_exists(file_path)"),
		"_load_music_manifest must check file_exists BEFORE opening (was missing pre-tick-276)")
	assert_true(body.contains("[MUSIC] music_manifest.json not found"),
		"missing-file path must push_warning naming the path")


func test_open_fail_warns_with_path() -> void:
	var body := _function_body(_read(SOUND_MANAGER), "_load_music_manifest")
	assert_true(body.contains("FileAccess.open failed at"),
		"open-fail path must push_warning naming the path (pre-tick-276 said 'Cannot open' without path)")


func test_parse_error_warns() -> void:
	var body := _function_body(_read(SOUND_MANAGER), "_load_music_manifest")
	assert_true(body.contains("music_manifest.json parse error"),
		"parse-error path must push_warning")


func test_non_dict_root_warns() -> void:
	var body := _function_body(_read(SOUND_MANAGER), "_load_music_manifest")
	assert_true(body.contains("root is not a Dictionary"),
		"non-Dict root must push_warning")


func test_missing_tracks_key_warns() -> void:
	var body := _function_body(_read(SOUND_MANAGER), "_load_music_manifest")
	assert_true(body.contains("missing 'tracks' key"),
		"missing 'tracks' key must push_warning")


# ── _manifest_loaded only set on success (retry semantics preserved) ─

func test_manifest_loaded_set_only_on_success() -> void:
	# The retry-on-PCK-not-ready semantic depends on NOT setting
	# _manifest_loaded until the happy path. Pin: every error path
	# `return`s before _manifest_loaded = true.
	var body := _function_body(_read(SOUND_MANAGER), "_load_music_manifest")
	# Find the `_manifest_loaded = true` line.
	var set_idx: int = body.find("_manifest_loaded = true")
	assert_gt(set_idx, -1, "_manifest_loaded must be set somewhere in the function")
	# Find the last `return` BEFORE that set line.
	var before: String = body.substr(0, set_idx)
	# Count returns in the pre-success body — should be 5 (one per failure mode).
	var return_count: int = before.count("\treturn")
	assert_gte(return_count, 5,
		"each of the 5 failure modes must `return` before _manifest_loaded = true (got %d returns)" % return_count)


# ── Parity with sfx_manifest pattern (tick 166) ──────────────────

func test_parity_with_sfx_manifest_shape() -> void:
	# Both loaders should use the same 5-stage structure. If sfx
	# loader pattern drifts, this catches the asymmetry.
	var sfx_body := _function_body(_read(SOUND_MANAGER), "_load_sfx_manifest")
	var music_body := _function_body(_read(SOUND_MANAGER), "_load_music_manifest")
	# Both must have file_exists check.
	assert_true(sfx_body.contains("FileAccess.file_exists"),
		"sfx loader must use file_exists check")
	assert_true(music_body.contains("FileAccess.file_exists"),
		"music loader must use file_exists check (parity with sfx)")
