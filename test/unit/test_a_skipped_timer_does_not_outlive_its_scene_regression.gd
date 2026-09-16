extends GutTest

## `start_timer` writes `timer_active_<flag>` into GameState.game_constants, and game_constants
## ROUND-TRIPS THROUGH THE SAVE FILE (_apply_save_data restores it). Only `stop_timer` ever wrote it
## back to false — and a skipped or aborted scene never reaches its remaining steps, because the step
## loop breaks on `_skipping`/`_aborted`. `_end_cutscene` already tore down the HUD label defensively
## for exactly that case; it left the flag true, permanently, in the player's save.
##
## The W4 orrery is the only scene with a timer today, and NOTHING in src/ reads `timer_active_*`
## (one writer, one test reader, 2026-09-16) — so this is save hygiene, not visible behaviour. It is
## worth fixing because the asymmetry is invisible: the HUD half was guarded and the state half
## looked guarded by it.

const DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"
const FLAG := "regression_skipped_timer"
const KEY := "timer_active_" + FLAG


func before_each() -> void:
	if GameState:
		GameState.game_constants.erase(KEY)


func after_each() -> void:
	if GameState:
		GameState.game_constants.erase(KEY)


func _director() -> Node:
	var d = load(DIRECTOR_PATH).new()
	add_child_autofree(d)
	return d


## The defect: the teardown path (what a skip reaches) must clear the flag, not only the HUD.
func test_the_teardown_clears_the_flag_not_only_the_hud() -> void:
	var d := _director()
	d._step_start_timer({"type": "start_timer", "duration": 300, "flag": FLAG})
	assert_true(GameState.game_constants.get(KEY, false),
		"PRECONDITION: start_timer must set %s, else this measures nothing" % KEY)
	d._clear_timer_hud()
	assert_false(GameState.game_constants.get(KEY, true),
		"a scene torn down without its stop_timer step must leave %s false — game_constants is SAVED state" % KEY)
	assert_null(d._timer_label, "and the HUD label goes with it")
	assert_eq(d._timer_remaining, 0.0, "and the countdown stops")


## The skip path reaches the teardown at all: _end_cutscene is what a broken-out step loop runs.
func test_end_cutscene_reaches_the_teardown() -> void:
	var src := FileAccess.get_file_as_string(DIRECTOR_PATH)
	var i := src.find("func _end_cutscene")
	assert_gt(i, -1, "_end_cutscene must exist")
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 2500)
	assert_true("_clear_timer_hud()" in body,
		"_end_cutscene must tear the timer down — it is the only thing a skipped scene still runs")


## CONTROL: with no timer running, the teardown must not invent a key. An empty flag wrote
## `timer_active_` into the player's save on every single cutscene end otherwise.
func test_a_scene_with_no_timer_writes_nothing() -> void:
	var d := _director()
	var before: int = GameState.game_constants.size()
	var had_empty: bool = GameState.game_constants.has("timer_active_")
	d._clear_timer_hud()
	assert_false(GameState.game_constants.has("timer_active_") and not had_empty,
		"the teardown must not write a bare `timer_active_` key when no timer was started")
	assert_eq(GameState.game_constants.size(), before,
		"and must not grow game_constants at all for a scene that never started a timer")


## stop_timer keeps working on its own terms — it names its flag, which need not be the started one.
func test_stop_timer_still_clears_its_own_flag() -> void:
	var d := _director()
	d._step_start_timer({"type": "start_timer", "duration": 60, "flag": FLAG})
	d._step_stop_timer({"type": "stop_timer", "flag": FLAG})
	assert_false(GameState.game_constants.get(KEY, true), "stop_timer must still write its flag false")
	assert_null(d._timer_label, "and clear the HUD")


## A second scene must not inherit the first one's countdown state.
func test_a_new_timer_replaces_the_last_scenes() -> void:
	var d := _director()
	d._step_start_timer({"type": "start_timer", "duration": 300, "flag": FLAG})
	d._clear_timer_hud()
	d._step_start_timer({"type": "start_timer", "duration": 45, "flag": FLAG})
	assert_true(GameState.game_constants.get(KEY, false), "the new scene's timer is running again")
	assert_eq(d._timer_remaining, 45.0, "and the countdown is the new scene's, not the old one's")
	d._clear_timer_hud()
	assert_false(GameState.game_constants.get(KEY, true), "and it clears again")
