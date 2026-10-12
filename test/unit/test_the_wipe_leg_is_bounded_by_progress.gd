extends GutTest

## The render smoke's wipe leg was bounded by ABSOLUTE PROCESS AGE and reported two different
## outcomes with one message.
##
## Measured 2026-10-12 at load 23.84 on 24 cpus: the leg reached its wait at process age 87.3s,
## spent the remaining 192.7s of the 280s deadline with rounds advancing the whole time, produced no
## game over, and printed `game_over screen never appeared by 280s process age`. That reads as a
## game-over REGRESSION and it was a slow box — the same substitution CLAUDE.md records for exit
## 124, where a WEDGE and a RED are both non-zero and the wrong one sends you to fix the tree.
##
## 🔑 THE ORDER OF THE CHECKS IS THE SEMANTICS, which is why this guard exists rather than a
## comment. A frozen battle and a slow box both end the leg without a screen; only `stalled` before
## `budget` keeps a frozen battle from being excused as slowness. Reverse the two and the smoke
## reports a real stall as "a slow box, not a missing game over" — green-looking prose over a bug.
##
## 📌 NO FLOOR ARM HERE, DELIBERATELY. Every call below goes through a preloaded const
## (`GameLoopScript.smoke_wipe_verdict`), which GDScript resolves at PARSE time — renaming the
## static does not make an arm vacuous, it drops the whole script and `run_tests.sh` exits 3,
## NOT ALL TEST FILES RAN. That is louder than a floor, so a floor would be dead code; CLAUDE.md's
## call-shape table says exactly this, and I confirmed it by hitting the parse error twice while
## trying to write the floor against a class you cannot call instance methods on.
##
## `smoke_wipe_verdict` is STATIC and pure for one reason: no test can instantiate GameLoop (three
## existing files assert `get_tree().root.get_node_or_null("GameLoop")` is null), so a decision left
## inside the await loop would be unreachable from here and provable only by running the whole smoke.

const GameLoopScript := preload("res://src/GameLoop.gd")

const BUDGET := 90000
const STALL := 25000


func _verdict(elapsed_ms: int, since_progress_ms: int, fighting: bool) -> String:
	return GameLoopScript.smoke_wipe_verdict(elapsed_ms, since_progress_ms, fighting, BUDGET, STALL)


func test_a_running_battle_making_progress_keeps_waiting() -> void:
	assert_eq(_verdict(1000, 0, true), "",
		"CONTROL: a fresh, advancing battle must not trip any bound, or every arm below is free")
	assert_eq(_verdict(BUDGET - 1, STALL - 1, true), "",
		"one millisecond inside both bounds is still waiting — the leg may not end early")


func test_a_battle_that_ended_without_a_screen_is_a_real_bug() -> void:
	assert_eq(_verdict(1000, 0, false), "ended_without_game_over",
		"the battle finished and no GameOverScreen came up; that is the defect the leg exists to catch")
	assert_eq(_verdict(BUDGET + 9999, STALL + 9999, false), "ended_without_game_over",
		"an ended battle outranks both clocks — reporting it as a slow box would hide a real bug")


func test_a_frozen_battle_reports_stalled() -> void:
	assert_eq(_verdict(1000, STALL, true), "stalled",
		"no round advanced for the stall window while the battle is live — progress stopped")


## The arm that pins the ORDER. Both bounds are tripped at once; `stalled` must win.
func test_a_frozen_battle_is_never_excused_as_a_slow_box() -> void:
	var both: String = _verdict(BUDGET + 1, STALL + 1, true)
	assert_eq(both, "stalled",
		"with BOTH bounds tripped the verdict must be 'stalled': a frozen battle reported as " +
		"'budget' tells the reader their box is slow when the game is wedged")


func test_a_slow_box_is_not_reported_as_a_missing_game_over() -> void:
	assert_eq(_verdict(BUDGET, STALL - 1, true), "budget",
		"rounds still advancing and the leg outran its budget — that is a slow box, and saying so " +
		"is the whole point of the change")


## The bounds must be RELATIVE to the leg, not an absolute process age: the old form shrank by every
## second any upstream leg spent, so adding a world leg silently stole from this one.
func test_the_bounds_are_relative_to_the_leg_not_the_process() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_ne(src, "", "CONTROL: GameLoop.gd must be readable or this arm proves nothing")
	assert_false(src.contains("SMOKE_WIPE_DEADLINE_MS"),
		"the absolute-process-age deadline is back; it cannot bound a leg whose start time varies")
	assert_true(src.contains("var leg_start: int = Time.get_ticks_msec()"),
		"the wait must timestamp its own start, so its budget is its own")
	assert_true(src.contains("SMOKE_VERDICT_FLOOR_MS"),
		"the verdict must still be clamped to print before deploy_web.sh's outer timeout 300")
