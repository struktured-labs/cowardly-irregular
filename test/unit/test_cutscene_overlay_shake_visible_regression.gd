extends GutTest

## Regression: screen_shake moved the MAP CAMERA. An overlay cutscene paints its backdrop
## inside the Director's own CanvasLayer, which does not follow the camera — so 49 of the 50
## authored shakes (every boss intro, every chapter beat) jittered something the player could
## not see, and scenes with no Camera2D at all shook nothing. The one case that worked (a
## staged scene on a live map) certified the rest. Overlay scenes now shake the layer.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")

var _d: Node
var _cam: Camera2D
var _shake_was: bool


func before_each() -> void:
	_shake_was = GameState.screen_shake_enabled
	GameState.screen_shake_enabled = true
	_cam = Camera2D.new()
	add_child_autofree(_cam)
	_cam.make_current()
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_d._skipping = false


func after_each() -> void:
	GameState.screen_shake_enabled = _shake_was


## Samples both the layer offset and the camera offset over a few frames while a shake runs.
func _observe(step: Dictionary) -> Dictionary:
	var done := [false]
	var runner := func() -> void:
		await _d._step_screen_shake(step)
		done[0] = true
	runner.call()
	var layer_moved := false
	var cam_moved := false
	var cam_start: Vector2 = _cam.offset
	for i in 8:
		await get_tree().process_frame
		if _d.offset != Vector2.ZERO:
			layer_moved = true
		if _cam.offset != cam_start:
			cam_moved = true
	# let the shake finish — budgeted in ENGINE time, not frames (headless frames are far shorter than 1/60s)
	var waited := 0.0
	while not done[0] and waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return {"layer": layer_moved, "camera": cam_moved, "done": done[0]}


func test_overlay_scene_shakes_the_layer_not_the_hidden_camera() -> void:
	_d._staged = false
	var r := await _observe({"duration": 0.3, "intensity": 6.0})
	assert_true(r["layer"], "an overlay scene must jitter the Director layer — that is what the player sees")
	assert_false(r["camera"], "the camera is behind an opaque backdrop in overlay mode; moving it is invisible")
	assert_true(r["done"], "the step must complete")
	assert_eq(_d.offset, Vector2.ZERO, "the layer must return to rest")


func test_staged_scene_keeps_the_camera_shake() -> void:
	_d._staged = true
	var r := await _observe({"duration": 0.3, "intensity": 6.0})
	assert_true(r["camera"], "a staged scene plays on the live map — the camera shake is the visible one")
	assert_false(r["layer"], "staged scenes must not also jitter the layer (letterbox bars would wobble)")
	assert_true(r["done"], "the camera shake must complete within the 2s budget")


func test_overlay_scene_with_no_camera_still_shakes() -> void:
	_cam.enabled = false
	_cam.queue_free()
	await get_tree().process_frame
	_cam = Camera2D.new()  # dummy so _observe can read an offset; in the tree but never made current
	add_child_autofree(_cam)
	_d._staged = false
	var r := await _observe({"duration": 0.3, "intensity": 6.0})
	assert_true(r["layer"], "with no Camera2D the old code silently did nothing; the layer shake must still play")


func test_settings_gate_still_silences_both() -> void:
	GameState.screen_shake_enabled = false
	_d._staged = false
	var r := await _observe({"duration": 0.3, "intensity": 6.0})
	assert_false(r["layer"], "screen_shake_enabled=false must suppress the layer shake")
	assert_false(r["camera"], "screen_shake_enabled=false must suppress the camera shake")


## Runs a staged shake to the end; `mid` (if valid) is called a few frames in, as another offset writer would.
func _staged_shake_from(start: Vector2, mid: Callable = Callable()) -> Vector2:
	_d._staged = true
	_cam.offset = start
	var done := [false]
	var runner := func() -> void:
		await _d._step_screen_shake({"duration": 0.3, "intensity": 6.0})
		done[0] = true
	runner.call()
	for i in 4:
		await get_tree().process_frame
	if mid.is_valid():
		mid.call()
	var waited := 0.0
	while not done[0] and waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	assert_true(done[0], "CONTROL: the staged shake finished inside its budget")
	return _cam.offset


func test_a_staged_shake_hands_back_the_offset_it_found() -> void:
	var end := await _staged_shake_from(Vector2(0, -40))
	assert_almost_eq(end.x, 0.0, 0.01, "a shake leaves the camera where it found it: %s" % end)
	assert_almost_eq(end.y, -40.0, 0.01, "including an offset someone else had already set: %s" % end)


## Regression: the shake restored a SNAPSHOT, so an offset another writer moved mid-shake (the shop's entry framing easing home) was put back afterwards.
func test_an_offset_moved_during_a_shake_survives_it() -> void:
	var end := await _staged_shake_from(Vector2(0, -40), func() -> void: _cam.offset += Vector2(0, 40))
	assert_almost_eq(end.x, 0.0, 0.01, "the shake takes back only its own jitter: %s" % end)
	assert_almost_eq(end.y, 0.0, 0.01, "so the other writer's move from -40 to 0 stands, not the -40 the shake found: %s" % end)
