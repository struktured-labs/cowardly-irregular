extends GutTest

## tick 274: CutsceneGallery's cutscene-file scanner now uses the same
## 4-stage loud-fail pattern as BestiarySystem._load_json. Pre-fix
## every error path silently `continue`'d — a malformed cutscene file
## simply vanished from the gallery with no diagnostic surface.
##
## Symptom pre-fix: an author would write a new cutscene, miss the
## gallery during play, and have no signal that the JSON failed to
## parse. Symptom looked identical to "not authored yet" / "not yet
## unlocked".

const CUTSCENE_GALLERY := "res://src/ui/CutsceneGallery.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── All 3 error paths emit push_warning ────────────────────────────

func test_file_open_failure_pushes_warning() -> void:
	var src := _read(CUTSCENE_GALLERY)
	# Locate the _scan_cutscenes function body to avoid false matches
	# elsewhere in the file.
	var fn_idx: int = src.find("func _scan_cutscenes")
	assert_gt(fn_idx, -1, "_scan_cutscenes must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("push_warning(\"[CutsceneGallery]") and body.contains("FileAccess.open failed"),
		"file-open failure must push_warning naming the path")


func test_parse_error_pushes_warning() -> void:
	var src := _read(CUTSCENE_GALLERY)
	var fn_idx: int = src.find("func _scan_cutscenes")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("parse error"),
		"JSON parse failure must push_warning with the path + error message")


func test_root_not_dict_pushes_warning() -> void:
	var src := _read(CUTSCENE_GALLERY)
	var fn_idx: int = src.find("func _scan_cutscenes")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("root is not a Dictionary"),
		"root-not-Dictionary failure must push_warning (matches BestiarySystem._load_json wording)")


# ── continue still happens (defensive — gallery must skip, not crash) ─

func test_continue_still_skips_bad_entries() -> void:
	# Defensive pin: each error path still ends with `continue`. Without
	# this a malformed entry could later crash a downstream `data.get(...)`.
	var src := _read(CUTSCENE_GALLERY)
	var fn_idx: int = src.find("func _scan_cutscenes")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Count `continue` occurrences inside the 4-stage block. Expect ≥3
	# (one per failure mode), plus possibly more elsewhere in the body.
	var continue_count: int = body.count("continue")
	assert_gte(continue_count, 3,
		"each of the 3 loud-fail paths must still end with `continue` (defensive skip)")
