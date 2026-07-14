extends GutTest

## Regression: when a cutscene is skipped, every remaining set_flag step
## MUST still fire — otherwise the cutscene's completion flag isn't set
## and the cutscene replays forever on every save load / area re-enter.
## This is a silent failure mode (no error, just bad UX), so the test
## guards both:
##   1. The helper exists and is called from the skip path
##   2. It correctly walks the remaining steps and fires set_flag entries
##      while skipping non-flag entries
##
## Behavioral test exercises the extracted helper directly so it doesn't
## depend on driving the full UI / async cutscene flow.

const DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"


const _TOUCHED_FLAGS := [
	"cutscene_flag_test_flag_a",
	"cutscene_flag_test_flag_b",
	"cutscene_flag_test_flag_c",
	"cutscene_flag_test_flag_d",
]
var _saved_flags: Dictionary = {}


func before_each() -> void:
	_saved_flags.clear()
	if GameState:
		for f in _TOUCHED_FLAGS:
			_saved_flags[f] = GameState.game_constants.get(f, null)
			GameState.game_constants.erase(f)


func after_each() -> void:
	if GameState:
		for f in _TOUCHED_FLAGS:
			GameState.game_constants.erase(f)
			if _saved_flags.get(f) != null:
				GameState.game_constants[f] = _saved_flags[f]


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_skip_path_calls_apply_remaining_set_flag_steps() -> void:
	# Source-level: the skip branch in _start_cutscene must call the
	# extracted helper (not be inlined). Catches anyone re-inlining the
	# loop, which is fine logically but loses the unit-test surface and
	# makes future refactors riskier.
	# 2026-07-02 abort semantics: the guard is now
	# `if _skipping and not _aborted:` — player skips still apply the
	# remaining flags; ABORTED runs apply nothing (an aborted spotlight
	# must replay, so its flags must not set).
	var text = _read(DIRECTOR_PATH)
	var skip_idx = text.find("if _skipping and not _aborted:")
	assert_true(skip_idx > -1, "step loop must apply remaining flags on skip but NOT on abort")
	while skip_idx > -1:
		var window = text.substr(skip_idx, 200)
		if window.find("_apply_remaining_set_flag_steps(steps") > -1:
			return
		skip_idx = text.find("if _skipping and not _aborted:", skip_idx + 1)
	assert_true(false,
		"No skip-not-abort block calls _apply_remaining_set_flag_steps(steps, ...) — helper is orphaned")


func test_helper_fires_set_flag_for_each_remaining_set_flag_step() -> void:
	# Behavioral: a steps array with mixed types from index N onwards,
	# helper fires _step_set_flag for each set_flag entry.
	var script = load(DIRECTOR_PATH)
	var d = script.new()
	add_child_autofree(d)

	var steps: Array = [
		{"type": "dialogue", "speaker": "Hero", "text": "Hello"},
		{"type": "dialogue", "speaker": "Hero", "text": "World"},
		{"type": "set_flag", "flag": "test_flag_a", "value": true},
		{"type": "play_music", "track": "battle"},
		{"type": "set_flag", "flag": "test_flag_b", "value": true},
		{"type": "set_flag", "flag": "test_flag_c", "value": true},
	]
	# Skip the first 2 dialogue steps (already executed before the skip
	# triggered). The remaining 4 contain 3 set_flag entries.
	d._apply_remaining_set_flag_steps(steps, 2)
	assert_true(GameState.game_constants.get("cutscene_flag_test_flag_a", false),
		"set_flag at index 2 must fire (helper starts at from_index)")
	assert_true(GameState.game_constants.get("cutscene_flag_test_flag_b", false),
		"set_flag at index 4 must fire (helper walks past non-set_flag entries)")
	assert_true(GameState.game_constants.get("cutscene_flag_test_flag_c", false),
		"set_flag at index 5 must fire (helper continues to end of array)")


func test_helper_skips_set_flag_entries_before_from_index() -> void:
	# Set_flag at index 0 should NOT fire when from_index=2.
	var script = load(DIRECTOR_PATH)
	var d = script.new()
	add_child_autofree(d)

	var steps: Array = [
		{"type": "set_flag", "flag": "test_flag_a", "value": true},  # skipped (already-executed)
		{"type": "dialogue", "speaker": "Hero", "text": "ok"},
		{"type": "set_flag", "flag": "test_flag_b", "value": true},  # should fire
	]
	d._apply_remaining_set_flag_steps(steps, 2)
	assert_false(GameState.game_constants.has("cutscene_flag_test_flag_a"),
		"set_flag before from_index must NOT fire — already executed in pre-skip phase")
	assert_true(GameState.game_constants.get("cutscene_flag_test_flag_b", false),
		"set_flag at from_index must fire")


func test_helper_handles_empty_remaining_steps() -> void:
	# Edge case: from_index >= steps.size() — no remaining steps. Must
	# not crash, must not flip any flags.
	var script = load(DIRECTOR_PATH)
	var d = script.new()
	add_child_autofree(d)

	var steps: Array = [{"type": "set_flag", "flag": "test_flag_d", "value": true}]
	d._apply_remaining_set_flag_steps(steps, 1)  # past the end
	assert_false(GameState.game_constants.has("cutscene_flag_test_flag_d"),
		"from_index past end must be a clean no-op — no flag fires")

	# Empty steps array entirely
	d._apply_remaining_set_flag_steps([], 0)
	# No crash → pass


func test_skip_path_still_arms_five_marks_finale_gate() -> void:
	# Orrery finale-gate interaction (v3.33.49): the five-marks emitter
	# lives inside _step_set_flag, and the skip path routes through the
	# same function — so a player who SKIPS an orrery cinematic must
	# still arm quest_wiring_fool_card_five_marks when marks hit 5.
	# Without this pin, a refactor that moves the emitter out of
	# _step_set_flag (e.g. into the cutscene-finished handler) would
	# silently break skipped-cutscene chain progression.
	var prev_marks = GameState.game_constants.get("cutscene_flag_fool_card_marks", null)
	var prev_gate: bool = GameState.get_story_flag("quest_wiring_fool_card_five_marks")

	GameState.game_constants.erase("cutscene_flag_fool_card_marks")
	GameState.set_story_flag("quest_wiring_fool_card_five_marks", false)

	var script = load(DIRECTOR_PATH)
	var d = script.new()
	add_child_autofree(d)

	# Simulate skipping mid-cutscene with the marks-5 set_flag still ahead.
	var steps: Array = [
		{"type": "dialogue", "speaker": "Orrery", "text": "The fifth mark."},
		{"type": "set_flag", "flag": "fool_card_marks", "value": 5},
	]
	d._apply_remaining_set_flag_steps(steps, 1)

	assert_true(GameState.get_story_flag("quest_wiring_fool_card_five_marks"),
		"Skipping the finale-adjacent orrery cinematic must still arm the five-marks gate — marks landed via the skip path")

	# Restore
	GameState.game_constants.erase("cutscene_flag_fool_card_marks")
	if prev_marks != null:
		GameState.game_constants["cutscene_flag_fool_card_marks"] = prev_marks
	GameState.set_story_flag("quest_wiring_fool_card_five_marks", prev_gate)
