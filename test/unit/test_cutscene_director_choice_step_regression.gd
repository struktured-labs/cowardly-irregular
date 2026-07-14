extends GutTest

## tick 331: CutsceneDirector handles the "choice" step type.
##
## Pre-fix world6_orrery.json line 85 used {"type": "choice", "prompt":
## "...", "options": [{"text": "...", "flag": "..."}, ...]} but
## CutsceneDirector had NO handler for "choice" — every play of that
## cutscene hit the unknown-step-type push_warning at line ~356 and
## silently skipped the prompt. None of the world6_orrery_response_*
## flags ever got set, so any downstream branch keyed on those flags
## never fired and the player's choice was meaningless.
##
## Fix adds _step_choice that:
##   1. Shows the prompt as a narration line.
##   2. Presents options via DialogueChoiceMenu.
##   3. Awaits selection and sets the matched option's flag in
##      GameState.game_constants.
##
## Skip-resilient: if the player held skip, sets the first option's
## flag deterministically so the state machine doesn't wait on input
## that won't arrive.

const CUTSCENE_DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: "choice" arm exists in the step match ───────────────

func test_choice_arm_in_step_dispatch() -> void:
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	# Need to find the dispatch — look for a match where "roll_credits"
	# precedes "choice".
	var rc_idx: int = src.find("\"roll_credits\":")
	var choice_idx: int = src.find("\"choice\":")
	assert_gt(rc_idx, -1, "roll_credits arm must exist (sanity)")
	assert_gt(choice_idx, -1, "choice arm must exist in the step dispatch")
	# choice should appear close to roll_credits in the dispatch (not in
	# a JSON-loading helper or comment) — within 200 chars.
	assert_lt(abs(choice_idx - rc_idx), 200,
		"choice arm should be near roll_credits in the dispatch — keeps the match together")


# ── Source pin: _step_choice function exists ────────────────────────

func test_step_choice_function_exists() -> void:
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	assert_true(src.contains("func _step_choice(step: Dictionary)"),
		"_step_choice must be defined")


# ── Source pin: flag-setting helper exists ──────────────────────────

func test_set_choice_flag_helper_exists() -> void:
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	assert_true(src.contains("func _set_choice_flag(option: Variant)"),
		"_set_choice_flag helper must exist — the canonical flag-write path")
	# Helper must write to game_constants.
	var fn_idx: int = src.find("func _set_choice_flag")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("game_constants[\"cutscene_flag_\" + flag_name] = true"),
		"_set_choice_flag must write the flag PREFIXED with cutscene_flag_ (tick 332 — matches _step_set_flag and _step_branch conventions)")


# ── Source pin: skip path sets first option deterministically ───────

func test_skip_path_sets_first_option() -> void:
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	var fn_idx: int = src.find("func _step_choice")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if _skipping:"),
		"_step_choice must check _skipping for the skip-resilient path")
	# In the skip path, set the first option's flag.
	var skip_idx: int = body.find("if _skipping:")
	assert_gt(skip_idx, -1)
	var skip_body: String = body.substr(skip_idx, 200)
	assert_true(skip_body.contains("_set_choice_flag(options[0])"),
		"skip path must set the first option's flag and return")


# ── Behavioral: _set_choice_flag writes to game_constants ───────────

func test_set_choice_flag_writes_to_game_constants() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	var script: GDScript = load(CUTSCENE_DIRECTOR_PATH)
	var director: Object = script.new()
	add_child_autofree(director)

	# Snapshot the test flag.
	var test_flag: String = "world6_orrery_response_tick_331_test"
	var prior: bool = bool(GameState.game_constants.get(test_flag, false))

	director._set_choice_flag({"text": "Test", "flag": test_flag})
	# Tick 332: flag is now prefixed with "cutscene_flag_" so it lives
	# in the same namespace as _step_set_flag and is readable by
	# _step_branch.
	var prefixed_key: String = "cutscene_flag_" + test_flag
	assert_eq(bool(GameState.game_constants.get(prefixed_key, false)), true,
		"_set_choice_flag must set the PREFIXED flag (cutscene_flag_<name>) to true in game_constants")

	# Cleanup.
	GameState.game_constants.erase(prefixed_key)
	if prior:
		GameState.game_constants[prefixed_key] = true


# ── Behavioral: empty/missing flag is a no-op (no crash) ────────────

func test_set_choice_flag_no_flag_field_is_noop() -> void:
	var script: GDScript = load(CUTSCENE_DIRECTOR_PATH)
	var director: Object = script.new()
	add_child_autofree(director)
	# Option without "flag" key — should not crash.
	director._set_choice_flag({"text": "Just text"})
	director._set_choice_flag({"text": "Empty flag", "flag": ""})
	director._set_choice_flag(null)
	director._set_choice_flag("not a dict")
	# If we got here, all 4 calls handled gracefully.
	assert_true(true, "_set_choice_flag must tolerate missing flag / null / non-Dict")
