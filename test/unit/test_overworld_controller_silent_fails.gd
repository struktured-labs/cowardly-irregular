extends GutTest

## tick 232: silent-fail audit of OverworldController.
##
## Two surfaces fixed:
##
## 1. _load_enemy_pools (4-stage loud-fail). Pre-fix each error
##    path silently returned {} so set_enemy_pool's downstream
##    "pool not found" warning fired but the ROOT CAUSE (file
##    missing, parse error, etc.) was invisible. Mirrors
##    BestiarySystem._load_json's pattern.
##
##    Stages now surfaced:
##      - File missing on disk
##      - FileAccess.open returns null
##      - JSON.parse != OK
##      - Parsed root is not a Dictionary
##
## 2. _on_interaction_requested player-null guard. Pre-fix the
##    @export var player being unassigned (forgotten in a new
##    village scene, broken signal binding) silently dropped
##    every interact press — player tapped Z, nothing happened,
##    no editor log.

const OVERWORLD_CONTROLLER := "res://src/exploration/OverworldController.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── _load_enemy_pools: 4-stage loud-fail ─────────────────────────────

func test_file_missing_warns() -> void:
	var src := _read(OVERWORLD_CONTROLLER)
	assert_true(src.contains("[OverworldController] enemy_pools.json missing at %s"),
		"file-missing branch must push_warning naming the path")
	assert_true(src.contains("no encounter pools available"),
		"warning must state the consequence (no encounter pools)")


func test_open_fail_warns() -> void:
	var src := _read(OVERWORLD_CONTROLLER)
	assert_true(src.contains("[OverworldController] enemy_pools.json exists but FileAccess.open failed"),
		"open-fail branch must push_warning")
	assert_true(src.contains("FileAccess.get_open_error()"),
		"warning must include the open-error code for diagnosis")


func test_parse_error_warns() -> void:
	var src := _read(OVERWORLD_CONTROLLER)
	assert_true(src.contains("[OverworldController] enemy_pools.json parse error: %s"),
		"parse-error branch must push_warning")
	assert_true(src.contains("json.get_error_message()"),
		"warning must include json.get_error_message() for diagnosis")


func test_non_dictionary_root_warns() -> void:
	# Pin: a JSON file that parses but whose root is an Array or
	# scalar should also warn (the file is structurally wrong).
	var src := _read(OVERWORLD_CONTROLLER)
	assert_true(src.contains("[OverworldController] enemy_pools.json parsed but root is not a Dictionary"),
		"non-Dictionary root must push_warning")


func test_all_failure_branches_return_empty_dict() -> void:
	# Pin: defensive {} return preserved on each failure path —
	# callers get a consistent empty value rather than null/crash.
	var src := _read(OVERWORLD_CONTROLLER)
	var fn_idx: int = src.find("func _load_enemy_pools")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# 4 `return {}` should exist (one per failure branch).
	var count: int = 0
	var idx: int = 0
	while true:
		var next: int = body.find("return {}", idx)
		if next < 0:
			break
		count += 1
		idx = next + 1
	assert_eq(count, 4,
		"_load_enemy_pools must have 4 `return {}` defensive fallbacks (one per failure stage)")


# ── Success path still returns parsed data ───────────────────────────

func test_success_path_returns_json_data() -> void:
	var src := _read(OVERWORLD_CONTROLLER)
	var fn_idx: int = src.find("func _load_enemy_pools")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# Final return at function end is the data.
	assert_true(body.contains("return json.data"),
		"success path must return json.data")


# ── _on_interaction_requested player-null surface ────────────────────

func test_interaction_player_null_warns() -> void:
	var src := _read(OVERWORLD_CONTROLLER)
	var fn_idx: int = src.find("func _on_interaction_requested")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("push_warning("),
		"_on_interaction_requested null-player branch must push_warning")
	assert_true(body.contains("@export var player likely unwired"),
		"warning must hint at the wiring cause (so devs check the scene setup)")


# ── Live runtime check: live data file actually parses ───────────────

func test_live_enemy_pools_json_parses_without_warnings() -> void:
	# Sanity: the live data file IS a valid JSON Dictionary so the
	# new warnings shouldn't fire in normal play. Catches a future
	# data edit that introduces a parse error.
	var path := "res://data/enemy_pools.json"
	assert_true(FileAccess.file_exists(path),
		"live enemy_pools.json must exist at the expected path")
	var f := FileAccess.open(path, FileAccess.READ)
	assert_ne(f, null, "live enemy_pools.json must be openable")
	var s := f.get_as_text()
	f.close()
	var j := JSON.new()
	assert_eq(j.parse(s), OK,
		"live enemy_pools.json must parse without error")
	assert_true(j.data is Dictionary,
		"live enemy_pools.json root must be a Dictionary")
	assert_gt((j.data as Dictionary).size(), 5,
		"live enemy_pools.json must have > 5 pool entries (sanity)")


# ── Cross-pin: existing tick 183 downstream warning preserved ────────

func test_tick_183_set_enemy_pool_warning_preserved() -> void:
	# Don't regress the downstream warning that surfaces "pool id
	# not found" — tick 232 makes the FILE-loading failures loud
	# too, but the per-pool warning is still useful when the file
	# loads but a specific pool id is missing.
	var src := _read(OVERWORLD_CONTROLLER)
	assert_true(src.contains("[OverworldController] enemy pool '%s' not found in enemy_pools.json"),
		"tick 183 per-pool-id warning preserved")


# ── Cross-pin: tick 231 BattleManager helper preserved ───────────────

func test_tick_231_player_state_guard_helper_preserved() -> void:
	# Same silent-fail-audit theme across BattleManager + OverworldController.
	var bm: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(bm.contains("func _check_player_selecting_state(action_name: String) -> bool:"),
		"tick 231 BattleManager helper preserved")
