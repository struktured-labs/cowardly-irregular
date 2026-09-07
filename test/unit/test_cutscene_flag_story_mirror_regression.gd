extends GutTest

## tick 333: cutscene set_flag and choice steps now mirror to
## story_flags as well as game_constants.
##
## Pre-fix _step_set_flag wrote ONLY to game_constants["cutscene_flag_
## <bare>"]. QuestLog (line 297) reads bare-name flags via
## GameState.get_story_flag(flag) which returns story_flags.get(flag,
## false) — no game_constants fallback. So a cutscene's set_flag step
## that flipped a quest objective flag (e.g. "talked_to_theron")
## NEVER updated story_flags, and QuestLog kept showing the objective
## as incomplete even after the relevant cutscene played.
##
## Same gap affected the choice step's _set_choice_flag (tick 332).
##
## The GameLoop helper _set_cutscene_flag_and_mirror already does this
## mirror for COMPLETION flags (fired on cutscene_finished). But
## set_flag steps DURING a cutscene bypassed it. The fix brings both
## cutscene-internal writers into the same mirror discipline.

const CUTSCENE_DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: _step_set_flag mirrors to story_flags ───────────────

func test_step_set_flag_mirrors() -> void:
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	var fn_idx: int = src.find("func _step_set_flag")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("set_story_flag(flag"),
		"_step_set_flag must mirror to GameState.set_story_flag — QuestLog reads bare names from story_flags")


# ── Source pin: _set_choice_flag mirrors to story_flags ─────────────

func test_set_choice_flag_mirrors() -> void:
	var src := _read(CUTSCENE_DIRECTOR_PATH)
	var fn_idx: int = src.find("func _set_choice_flag")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("set_story_flag(flag_name"),
		"_set_choice_flag must mirror to GameState.set_story_flag")


# ── Behavioral: set_flag step propagates to get_story_flag ──────────

func test_set_flag_propagates_to_story_flags() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	var script: GDScript = load(CUTSCENE_DIRECTOR_PATH)
	var director: Object = script.new()
	add_child_autofree(director)

	var bare_flag: String = "tick_333_test_set_flag_mirror"
	# Clean slate.
	GameState.game_constants.erase("cutscene_flag_" + bare_flag)
	GameState.story_flags.erase(bare_flag)

	# Drive the step.
	director._step_set_flag({"flag": bare_flag, "value": true})

	# Both stores must reflect the value.
	assert_true(bool(GameState.game_constants.get("cutscene_flag_" + bare_flag, false)),
		"game_constants must be updated (existing behavior)")
	assert_true(GameState.get_story_flag(bare_flag),
		"story_flags must ALSO be updated (tick 333 mirror) — QuestLog reads this path")

	# Cleanup.
	GameState.game_constants.erase("cutscene_flag_" + bare_flag)
	GameState.story_flags.erase(bare_flag)


# ── Behavioral: choice step propagates to story_flags ───────────────

func test_choice_flag_propagates_to_story_flags() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	var script: GDScript = load(CUTSCENE_DIRECTOR_PATH)
	var director: Object = script.new()
	add_child_autofree(director)

	var bare_flag: String = "tick_333_test_choice_mirror"
	GameState.game_constants.erase("cutscene_flag_" + bare_flag)
	GameState.story_flags.erase(bare_flag)

	director._set_choice_flag({"text": "Test", "flag": bare_flag})

	assert_true(bool(GameState.game_constants.get("cutscene_flag_" + bare_flag, false)),
		"game_constants must be updated (existing behavior — tick 332 added the prefix)")
	assert_true(GameState.get_story_flag(bare_flag),
		"story_flags must ALSO be updated (tick 333 mirror)")

	GameState.game_constants.erase("cutscene_flag_" + bare_flag)
	GameState.story_flags.erase(bare_flag)


# ── set_flag value=false also mirrors correctly ─────────────────────

func test_set_flag_false_value_mirrors() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	var script: GDScript = load(CUTSCENE_DIRECTOR_PATH)
	var director: Object = script.new()
	add_child_autofree(director)

	var bare_flag: String = "tick_333_test_set_flag_false"
	# Seed both stores to true, then verify the step pushes both to false.
	GameState.game_constants["cutscene_flag_" + bare_flag] = true
	GameState.story_flags[bare_flag] = true

	director._step_set_flag({"flag": bare_flag, "value": false})

	assert_false(bool(GameState.game_constants.get("cutscene_flag_" + bare_flag, true)),
		"game_constants must reflect value=false")
	assert_false(GameState.get_story_flag(bare_flag),
		"story_flags must also reflect value=false — mirror must propagate both directions, not just true")

	GameState.game_constants.erase("cutscene_flag_" + bare_flag)
	GameState.story_flags.erase(bare_flag)
