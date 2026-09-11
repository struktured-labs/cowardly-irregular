extends GutTest

## The fades, the flash, both shakes, the letterbox slides and the title / boss-intro tweens were
## the last holds in the Director that awaited a raw tween: a skip pressed mid-fade sat through the
## rest (authored fade_to_black runs to 3.0s; 25 of 32 fades are >= 1s) and a held confirm ran them
## at 1x while every other hold ran FAST_FORWARD_RATE. _await_tween_hold gives them _sleep's
## contract, and each caller snaps its end state so a cut fade still leaves the screen where the
## next step expects it.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")

var _d: Node


func before_each() -> void:
	Input.action_release("ui_accept")
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_d._skipping = false


func after_each() -> void:
	Input.action_release("ui_accept")  # the Input singleton leaks across tests


## Starts `step` unawaited; the returned one-slot array flips when it releases.
func _start(step: Dictionary) -> Array:
	var done := [false]
	var runner := func() -> void:
		await _d._execute_step(step)
		done[0] = true
	runner.call()
	return done


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Engine seconds until `done` flips, capped at `budget`.
func _wait_done(done: Array, budget: float) -> float:
	var elapsed := 0.0
	while not done[0] and elapsed < budget:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return elapsed


func test_skip_cuts_a_long_fade_to_black_and_lands_it_black() -> void:
	var done := _start({"type": "fade_to_black", "duration": 30.0})
	await _frames(2)
	assert_false(done[0], "control: a 30s fade is in flight after two frames")
	_d._skipping = true
	await _frames(4)
	assert_true(done[0], "a skip must release a fade within a few frames, not after 30s")
	assert_eq(_d._effects_rect.color, Color(0, 0, 0, 1), "a cut fade_to_black still lands on black")
	assert_true(_d._effects_rect.visible)


func test_skip_cuts_a_long_fade_from_black_and_clears_it() -> void:
	var done := _start({"type": "fade_from_black", "duration": 30.0})
	await _frames(2)
	assert_false(done[0], "control: in flight")
	_d._skipping = true
	await _frames(4)
	assert_true(done[0], "a skip must release fade_from_black within a few frames")
	assert_eq(_d._effects_rect.color.a, 0.0, "a cut fade_from_black lands fully clear")
	assert_false(_d._effects_rect.visible)


func test_skip_cuts_a_flash_and_hides_the_rect() -> void:
	var done := _start({"type": "screen_flash", "duration": 30.0})
	await _frames(2)
	assert_false(done[0], "control: in flight")
	_d._skipping = true
	await _frames(4)
	assert_true(done[0], "a skip must release a flash within a few frames")
	assert_false(_d._effects_rect.visible, "a cut flash does not leave a white rect over the map")


func test_skip_cuts_a_letterbox_slide_and_lands_the_bars() -> void:
	var done := _start({"type": "letterbox_in", "duration": 30.0})
	await _frames(2)
	assert_false(done[0], "control: in flight")
	_d._skipping = true
	await _frames(4)
	assert_true(done[0], "a skip must release letterbox_in within a few frames")
	assert_eq(_d._letterbox_top.position.y, 0.0, "a cut letterbox_in lands the top bar")
	assert_true(_d._letterbox_visible)


func test_skip_cuts_a_staged_camera_shake_and_restores_the_offset() -> void:
	var cam := Camera2D.new()
	add_child_autofree(cam)
	cam.make_current()
	cam.offset = Vector2(40, -12)
	_d._staged = true
	var done := _start({"type": "screen_shake", "duration": 30.0, "intensity": 9.0})
	await _frames(2)
	assert_false(done[0], "control: a 30s staged shake is in flight")
	_d._skipping = true
	await _frames(4)
	assert_true(done[0], "a skip must release a staged shake within a few frames")
	assert_eq(cam.offset, Vector2(40, -12), "a cut shake puts the camera back where the pan left it")


func test_skip_cuts_the_chapter_title_fade_in() -> void:
	var done := _start({"type": "chapter_title", "title": "Chapter X", "duration": 30.0})
	await _frames(2)
	assert_false(done[0], "control: the title is in flight")
	_d._skipping = true
	await _frames(6)
	assert_true(done[0], "a skip during the title's 0.6s fade-in must not sit through it and the hold")


func test_held_confirm_runs_a_fade_faster() -> void:
	Input.action_press("ui_accept")
	var t := await _wait_done(_start({"type": "fade_from_black", "duration": 1.0}), 3.0)
	assert_lt(t, 0.6, "a 1.0s fade under held confirm must release in ~0.25s of engine time, took %s" % t)
	assert_gt(t, 0.0, "control: it still takes SOME time — zero is the skip path, not fast-forward")
	assert_eq(_d._effects_rect.color.a, 0.0, "the fast-forwarded fade still ends fully clear")


func test_a_fade_without_the_hold_runs_at_full_length() -> void:
	# ARM+: a fade that always ran fast would pass the test above.
	var t := await _wait_done(_start({"type": "fade_from_black", "duration": 0.5}), 3.0)
	assert_gte(t, 0.45, "without the hold a 0.5s fade takes ~0.5s of engine time, took %s" % t)


func test_no_step_path_awaits_a_raw_tween() -> void:
	# The class, not the instance: a raw `await x.finished` on a step path is a hold that ignores skip and hold-A. Only the spotlight retry sting (a battle-aftermath beat, not a step) keeps one.
	var lines := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd").split("\n")
	var current_func := ""
	var raw: Array[String] = []
	var funcs_seen := 0
	for i in lines.size():
		var l: String = lines[i].strip_edges()
		if l.begins_with("func ") or l.begins_with("static func "):
			current_func = l
			funcs_seen += 1
		elif l.begins_with("await ") and l.ends_with(".finished") and not current_func.begins_with("func _play_spotlight_retry_sting"):
			raw.append("%d: %s  (in %s)" % [i + 1, l, current_func])
	assert_gt(funcs_seen, 50, "control: the scan saw the Director's functions")
	assert_eq(raw, [], "raw tween awaits on step paths — route them through _await_tween_hold")
