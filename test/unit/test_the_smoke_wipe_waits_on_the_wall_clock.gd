extends GutTest

## cowir-deploy, .498 web publish (2026-09-25): the render smoke went RED twice at its wipe stage,
## "game_over screen never appeared within 30s", while the party was still taking turns. Re-run
## locally the same build PASSED three times (73-95 s wall, dragon spawn to game over). The wait was
## 30 seconds of GAME time (0.5 s create_timer ticks), and a loaded box stretched the battle past it.
## The wipe waits on the process's wall clock, which must stay inside the outer `timeout`
## deploy_web.sh gives the whole smoke, or the kill lands first and the smoke's own diagnostic line
## is never printed.
##
## 📌 UPDATED 2026-10-12, and the ORIGINAL INTENT IS WHY THIS FILE SURVIVED THE REWRITE rather than
## being deleted with the constant it pinned. `SMOKE_WIPE_DEADLINE_MS` is gone: the absolute
## process-age form it named shrank by every second any upstream leg spent, and at load 23.84/24 it
## gave the wipe 192.7s, advanced rounds throughout, produced no game over and printed
## `game_over screen never appeared` — a slow box wearing a regression's words. That is the same
## failure this file was written about, one layer along, so its last arm's demand — *"a timeout must
## say whether the battle was still going, so slow and hung stay distinguishable"* — is now the
## whole design rather than a parenthetical: three named reasons, `stalled` before `budget`.
## The arms below are retargeted to the structure that replaced the constant; nothing here was
## dropped, and `test_the_wipe_leg_is_bounded_by_progress` drives the decision's branches.

const GameLoopScript := preload("res://src/GameLoop.gd")


func _outer_timeout_s() -> int:
	var src := FileAccess.get_file_as_string("res://tools/deploy_web.sh")
	assert_ne(src, "", "CONTROL: deploy_web.sh must be readable")
	var re := RegEx.new()
	re.compile("timeout (\\d+) godot[^\\n]*--render-smoke")
	var m := re.search(src)
	assert_not_null(m, "CONTROL: deploy_web.sh must launch the render smoke under `timeout N godot ... --render-smoke`")
	return int(m.get_string(1)) if m != null else 0


func test_the_verdict_floor_sits_inside_the_outer_timeout() -> void:
	var outer_ms := _outer_timeout_s() * 1000
	assert_gt(outer_ms, 0, "CONTROL: an outer timeout was found")
	assert_lt(GameLoopScript.SMOKE_VERDICT_FLOOR_MS, outer_ms,
		"the verdict floor must trip before deploy_web.sh's timeout kills the smoke, or its reason is lost")
	assert_gte(GameLoopScript.SMOKE_VERDICT_FLOOR_MS, outer_ms - 60000,
		"the floor should use most of the outer budget; a loaded box needs it")


## The leg's own budget must be shorter than the floor, or the floor is the only bound that ever
## fires and the leg is back to being paced by the process rather than by itself.
func test_the_leg_budget_is_shorter_than_the_floor() -> void:
	assert_gt(GameLoopScript.SMOKE_WIPE_BUDGET_MS, 0, "CONTROL: the leg has a budget of its own")
	assert_lt(GameLoopScript.SMOKE_WIPE_BUDGET_MS, GameLoopScript.SMOKE_VERDICT_FLOOR_MS,
		"the leg's own budget must be the binding bound in a normal run")
	assert_lt(GameLoopScript.SMOKE_WIPE_STALL_MS, GameLoopScript.SMOKE_WIPE_BUDGET_MS,
		"a stall must be detectable before the budget expires, or every freeze reports as a slow box")


func test_the_wipe_waits_on_wall_clock_not_game_time() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var at := src.find("func _smoke_await_wipe")
	assert_gt(at, -1, "the render smoke's wipe wait must exist")
	var end := src.find("\nfunc ", at + 10)
	assert_gt(end, at, "CONTROL: the wait function ends before the next one")
	var block := src.substr(at, end - at)
	assert_true(block.contains("Time.get_ticks_msec()"),
		"the wipe wait must be bounded by wall clock, not by summed create_timer ticks")
	assert_false(block.contains("< 30.0"), "the fixed 30 game-second budget that flaked .498 is back")
	assert_false(src.contains("SMOKE_WIPE_DEADLINE_MS"),
		"the absolute process-age deadline is back; it shrinks by whatever upstream legs spend")


## The .498 demand, now structural: a run that gave up must say WHICH bound tripped, because a slow
## box and a hung battle want opposite responses — re-run, versus fix the tree.
##
## ⛔ THE PATTERN CARRIES THE COLON ON PURPOSE. This arm first read `contains('"stalled"')`, which the
## verdict function satisfies all by itself with `return "stalled"` — so renaming the MATCH ARM that
## prints the stall message left this green. Measured: with the bare string, renaming `"stalled":`
## passed 12/12 across both guard files; with the colon it reds and names this arm. The arm this
## replaced in .498 was scoped to the wipe BLOCK, and the file-scoped version I shipped in .658 was
## weaker than what it replaced while reading as stronger — @cowir-battle's rule, that a guard you
## edit to go green must prove it still catches what it was written for, is what surfaced it.
## `":"` is the whole difference between "this token appears somewhere" and "this branch exists".
func test_slow_and_hung_stay_distinguishable() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	for reason in ["stalled", "budget", "ended_without_game_over"]:
		assert_true(src.contains('"%s":' % reason),
			"the wipe must be able to report '%s'; collapsing the reasons is what made a slow box read as a regression" % reason)
	assert_true(src.contains("a slow box, not a missing game over"),
		"the budget message must say in words that this is not a game-over defect")
	assert_true(src.contains("wipe STALLED"),
		"a frozen battle must announce itself as a stall rather than as elapsed time")
