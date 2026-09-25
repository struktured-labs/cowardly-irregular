extends GutTest

## cowir-deploy, .498 web publish (2026-09-25): the render smoke went RED twice at its wipe stage,
## "game_over screen never appeared within 30s", while the party was still taking turns. Re-run
## locally the same build PASSED three times (73-95 s wall, dragon spawn to game over). The wait was
## 30 seconds of GAME time (0.5 s create_timer ticks), and a loaded box stretched the battle past it.
## The wipe now waits on the process's wall clock up to SMOKE_WIPE_DEADLINE_MS, which must stay inside
## the outer `timeout` deploy_web.sh gives the whole smoke, or the kill lands first and the smoke's own
## diagnostic line is never printed.

const GameLoopScript := preload("res://src/GameLoop.gd")


func _outer_timeout_s() -> int:
	var src := FileAccess.get_file_as_string("res://tools/deploy_web.sh")
	assert_ne(src, "", "CONTROL: deploy_web.sh must be readable")
	var re := RegEx.new()
	re.compile("timeout (\\d+) godot[^\\n]*--render-smoke")
	var m := re.search(src)
	assert_not_null(m, "CONTROL: deploy_web.sh must launch the render smoke under `timeout N godot ... --render-smoke`")
	return int(m.get_string(1)) if m != null else 0


func test_the_deadline_sits_inside_the_outer_timeout() -> void:
	var outer_ms := _outer_timeout_s() * 1000
	assert_gt(outer_ms, 0, "CONTROL: an outer timeout was found")
	assert_lt(GameLoopScript.SMOKE_WIPE_DEADLINE_MS, outer_ms,
		"the wipe deadline must expire before deploy_web.sh's timeout kills the smoke, or its reason is lost")
	assert_gte(GameLoopScript.SMOKE_WIPE_DEADLINE_MS, outer_ms - 60000,
		"the wipe deadline should use most of the outer budget; a loaded box needs it")


func test_the_wipe_waits_on_wall_clock_not_game_time() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var at := src.find('await _start_battle_async(["shadow_dragon"], true)')
	assert_gt(at, -1, "the render smoke's wipe stage must exist")
	var end := src.find("[SMOKE] VERDICT", at)
	assert_gt(end, at, "CONTROL: the wipe block ends before the verdict")
	var block := src.substr(at, end - at)
	assert_true(block.contains("Time.get_ticks_msec() < SMOKE_WIPE_DEADLINE_MS"),
		"the wipe wait must be bounded by wall clock, not by summed create_timer ticks")
	assert_false(block.contains("< 30.0"), "the fixed 30 game-second budget that flaked .498 is back")
	assert_true(block.contains("battle still running"),
		"a timeout must say whether the battle was still going, so slow and hung stay distinguishable")
