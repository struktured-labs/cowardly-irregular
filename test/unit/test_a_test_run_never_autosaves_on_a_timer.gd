extends GutTest

## The .760 gate redded "a test left corruption_level at 0.350", and only in a long-lived sandbox: its autosave slot
## held a synthetic party with corruption 0.35 and no effects, and a Continue-path test loaded it. The writer was no
## test at all: SaveSystem._process autosaves every 300s of game time inside ANY running process, so an 18-minute
## suite saved whatever a test was holding at that instant. tools/run_tests.sh now holds that timer; tests that need
## a save still call save_game / auto_save themselves.

var _saved_held := false
var _saved_since := 0.0


func before_each() -> void:
	_saved_held = SaveSystem.timer_held
	_saved_since = SaveSystem.time_since_last_auto_save


func after_each() -> void:
	SaveSystem.timer_held = _saved_held
	SaveSystem.time_since_last_auto_save = _saved_since


func test_the_runner_holds_the_timer() -> void:
	var src := FileAccess.get_file_as_string("res://tools/run_tests.sh")
	assert_true(src.contains("export COWIR_HOLD_AUTOSAVE_TIMER=1"), "the wrapper every gate runs through holds the timer")
	assert_eq(OS.get_environment("COWIR_HOLD_AUTOSAVE_TIMER"), "1", "and this run was started with it")
	assert_true(SaveSystem.timer_held, "so SaveSystem read it at startup")


func test_a_held_timer_never_counts_toward_an_autosave() -> void:
	SaveSystem.timer_held = true
	SaveSystem.time_since_last_auto_save = 0.0
	SaveSystem._process(10000.0)
	assert_eq(SaveSystem.time_since_last_auto_save, 0.0, "however long a run lasts, the timer does not advance")


func test_an_unheld_timer_still_counts_for_a_player() -> void:
	SaveSystem.timer_held = false
	SaveSystem.time_since_last_auto_save = 0.0
	SaveSystem._process(1.0)
	assert_almost_eq(SaveSystem.time_since_last_auto_save, 1.0, 0.001, "CONTROL: a real game still autosaves on its timer")
