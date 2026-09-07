extends GutTest

## tick 282: OverworldNPC._load_persona_cache now uses the canonical
## 4-stage loud-fail pattern matching ticks 274/275/276 (Cutscene
## Gallery / JobSystem / SoundManager music_manifest).
##
## Pre-fix the parse-error and non-Dict-root paths conflated under
## a single "did not parse to Dictionary" warning — devs couldn't
## tell whether the JSON was malformed or whether it parsed cleanly
## to a non-Dict root. Now each surfaces distinctly.
##
## All 4 stages:
##   1. file missing       → "persona data missing at <path>"
##   2. file-open failed   → "<path> exists but FileAccess.open failed"
##   3. parse error        → "<path> parse error: <message>"
##   4. non-Dict root      → "<path> parsed but root is not a Dictionary"

const OVERWORLD_NPC := "res://src/exploration/OverworldNPC.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _function_body(src: String, fname: String) -> String:
	var fn_idx: int = src.find("func " + fname)
	assert_gt(fn_idx, -1, "function %s must exist" % fname)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	return src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)


# ── 4 distinct warning paths ───────────────────────────────────────

func test_missing_file_warns_with_path() -> void:
	var body := _function_body(_read(OVERWORLD_NPC), "_load_persona_cache")
	assert_true(body.contains("persona data missing at"),
		"missing-file path must push_warning naming the path")


func test_open_fail_warns_with_path() -> void:
	var body := _function_body(_read(OVERWORLD_NPC), "_load_persona_cache")
	assert_true(body.contains("exists but FileAccess.open failed"),
		"file-open-fail path must push_warning naming the path")


func test_parse_error_warns() -> void:
	var body := _function_body(_read(OVERWORLD_NPC), "_load_persona_cache")
	assert_true(body.contains("parse error"),
		"JSON parse failure must push_warning distinctly from non-Dict root")


func test_non_dict_root_warns() -> void:
	var body := _function_body(_read(OVERWORLD_NPC), "_load_persona_cache")
	assert_true(body.contains("parsed but root is not a Dictionary"),
		"non-Dict root must push_warning distinctly from parse error")


# ── Negative pin: pre-fix conflated warning is gone ───────────────

func test_no_conflated_did_not_parse_warning() -> void:
	var body := _function_body(_read(OVERWORLD_NPC), "_load_persona_cache")
	assert_false(body.contains("persona JSON did not parse to Dictionary"),
		"conflated pre-tick-282 warning must be replaced with the split forms")


# ── Defensive: each failure mode early-returns ─────────────────────

func test_each_failure_mode_early_returns() -> void:
	var body := _function_body(_read(OVERWORLD_NPC), "_load_persona_cache")
	# Count `return`s — should be ≥4 (one per failure mode) before
	# the final for-loop body.
	var return_count: int = body.count("return")
	assert_gte(return_count, 4,
		"each of the 4 failure modes must early-return before populating the cache")
