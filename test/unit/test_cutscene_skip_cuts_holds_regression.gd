extends GutTest

## Regression: every timed hold in the Director — wait, emote, say, the crowd-scatter
## longest-walk, the chapter-title hold, the boss-intro hold — awaited a SceneTree timer to
## completion. A skip only stopped the NEXT step, so after holding B for 1.5s the player sat
## through whatever remained of the current hold before anything happened. That reads as an
## ignored press. Holds now go through _sleep, which a skip cuts short the same frame.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")

var _d: Node


func before_each() -> void:
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_d._skipping = false


func _run_wait(duration: float, done: Array) -> void:
	await _d._step_wait({"type": "wait", "duration": duration})
	done[0] = true


func test_a_skip_cuts_an_in_flight_wait_short() -> void:
	var done := [false]
	_run_wait(30.0, done)
	await get_tree().process_frame
	assert_false(done[0], "control: a 30s wait must still be in flight after one frame")
	_d._skipping = true
	for i in 4:
		await get_tree().process_frame
	assert_true(done[0], "a skip must release the wait within a few frames, not after 30s")


func test_a_wait_without_a_skip_really_waits() -> void:
	# ARM+ for the test above: a _sleep that returned immediately would pass it vacuously.
	var done := [false]
	_run_wait(30.0, done)
	for i in 6:
		await get_tree().process_frame
	assert_false(done[0], "control: without a skip the wait must still be holding")
	_d._skipping = true  # release it so the coroutine does not outlive the test
	await get_tree().process_frame


func test_sleep_is_a_no_op_when_already_skipping() -> void:
	_d._skipping = true
	var done := [false]
	_run_wait(30.0, done)
	await get_tree().process_frame
	assert_true(done[0], "an already-skipping director must not start a hold at all")


func test_every_timed_hold_goes_through_sleep() -> void:
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	for fn in ["_step_wait", "_step_emote", "_step_say", "_step_nearby_scatter", "_step_chapter_title", "_step_boss_intro"]:
		var at := src.find("func %s(" % fn)
		assert_true(at >= 0, "%s must exist" % fn)
		var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
		assert_true(body.contains("_sleep("), "%s must hold via _sleep so a skip can cut it" % fn)
		assert_eq(body.find("create_timer("), -1, "%s must not await a raw SceneTree timer for its hold" % fn)
