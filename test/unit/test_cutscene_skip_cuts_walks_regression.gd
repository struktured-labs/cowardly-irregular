extends GutTest

## Regression (sibling of test_cutscene_skip_cuts_holds): move_actor awaited the walk tween
## and both camera steps awaited the pan tween. A skip pressed MID-walk or MID-pan therefore
## waited out the whole motion (authored walks run 80-160 px/s over hundreds of px — seconds)
## before the snap contract applied to the NEXT step. Walks and pans now yield to a skip the
## same frame: the actor lands on its mark, the camera lands on its offset.

const DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"

var _d: Node
var _stage: Node2D


func before_each() -> void:
	_stage = Node2D.new()
	add_child_autofree(_stage)
	MapSystem.current_map = _stage
	_d = load(DIRECTOR_PATH).new()
	add_child_autofree(_d)
	_d._skipping = false


func _run_move(done: Array) -> void:
	await _d._step_move_actor({"id": "hero", "to": [400, 0], "speed": 80})
	done[0] = true


func test_a_skip_mid_walk_lands_the_actor_on_its_mark_now() -> void:
	_d._step_spawn_actor({"id": "hero", "kind": "party", "job": "fighter", "at": [0, 0]})
	var a = _d._actors["hero"]
	var done := [false]
	_run_move(done)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(done[0], "control: a 5s walk must still be in flight after two frames")
	assert_true(a.global_position.x < 400.0, "control: the actor must not have arrived yet")
	_d._skipping = true
	for i in 4:
		await get_tree().process_frame
	assert_true(done[0], "the move step must release within a few frames of a skip")
	assert_eq(a.global_position, Vector2(400, 0), "the actor must land on its mark when skipped")
	assert_false(a._walking, "the actor must be standing after the snap")


func test_a_walk_without_a_skip_really_walks() -> void:
	# ARM+: a move step that returned immediately would pass the test above vacuously.
	_d._step_spawn_actor({"id": "hero", "kind": "party", "job": "fighter", "at": [0, 0]})
	var a = _d._actors["hero"]
	var done := [false]
	_run_move(done)
	for i in 6:
		await get_tree().process_frame
	assert_false(done[0], "control: without a skip the walk must still be in progress")
	assert_true(a.global_position.x > 0.0 and a.global_position.x < 400.0,
		"control: the actor must be tweening between the marks, got x=%s" % a.global_position.x)
	_d._skipping = true
	await get_tree().process_frame
	await get_tree().process_frame


func _run_focus(done: Array) -> void:
	await _d._step_camera_focus({"target": "hero", "duration": 5.0})
	done[0] = true


func test_a_skip_mid_pan_lands_the_camera_now() -> void:
	var cam := Camera2D.new()
	_stage.add_child(cam)
	cam.make_current()
	await get_tree().process_frame
	_d._step_spawn_actor({"id": "hero", "kind": "party", "job": "fighter", "at": [600, 400]})
	var start_offset := cam.offset
	var done := [false]
	_run_focus(done)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(done[0], "control: a 5s pan must still be in flight after two frames")
	_d._skipping = true
	for i in 4:
		await get_tree().process_frame
	assert_true(done[0], "camera_focus must release within a few frames of a skip")
	assert_ne(cam.offset, start_offset, "the camera must have snapped to the focus offset, not stayed put")
	assert_false(is_instance_valid(_d._last_camera_tween) and _d._last_camera_tween.is_valid() and _d._last_camera_tween.is_running(),
		"the pan tween must be dead after the snap")


func test_walk_and_pan_no_longer_await_raw_tween_signals() -> void:
	var src := FileAccess.get_file_as_string(DIRECTOR_PATH)
	assert_eq(src.find("await _last_camera_tween.finished"), -1, "camera steps must go through _await_pan")
	var at := src.find("func _step_move_actor(")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_eq(body.find("await a.walk_to("), -1, "move_actor must poll the walk so a skip can cut it")
	assert_true(body.contains("snap_walk()"), "move_actor must snap the actor on skip")
	var actor_src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneActor.gd")
	# Statement form (tab-prefixed) — a comment that merely NAMES the old pattern must not trip this.
	assert_eq(actor_src.find("\tawait tween.finished"), -1, "the actor must not await a raw tween signal (hangs when the target is freed)")
	assert_eq(actor_src.find("\tawait _walk_tween.finished"), -1, "walk_to must poll its tween, not await its signal")
