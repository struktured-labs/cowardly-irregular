extends GutTest

## Regression (2026-11-18): Reduce Flashes gated battle's full-screen flashes but not the cutscene's. The screen_flash
## step (50 cutscene files, white up to full opacity) and the Spotlight retry sting's red peak played with the setting on.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")

var _d: Node
var _saved := false


func before_each() -> void:
	_saved = bool(GameState.reduce_flashes)
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_d._skipping = false


func after_each() -> void:
	GameState.reduce_flashes = _saved


func _start_flash() -> Array:
	var done := [false]
	var runner := func() -> void:
		await _d._execute_step({"type": "screen_flash", "duration": 30.0})
		done[0] = true
	runner.call()
	return done


## Waits for the sting to finish (it hides its rect), bounded so a stuck tween reds instead of hanging.
func _until_hidden() -> void:
	for i in 20000:
		if not _d._effects_rect.visible:
			return
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func test_the_flash_step_draws_nothing_with_reduce_flashes_on() -> void:
	GameState.reduce_flashes = false
	var lit := _start_flash()
	await _frames(2)
	assert_true(_d._effects_rect.visible, "CONTROL: with the setting off, the flash covers the screen")
	assert_gt(_d._effects_rect.color.a, 0.5, "CONTROL: and it is bright enough to be a flash")
	assert_false(lit[0], "CONTROL: a 30 s flash is still in flight")
	_d._skipping = true
	await _frames(4)
	_d._skipping = false
	GameState.reduce_flashes = true
	var dark := _start_flash()
	await _frames(2)
	assert_false(_d._effects_rect.visible, "with Reduce Flashes on, a screen_flash step draws no full-screen colour")
	assert_true(dark[0], "and it does not hold the scene for a flash nobody sees")


func test_the_retry_sting_keeps_its_fade_but_loses_its_red_peak() -> void:
	GameState.reduce_flashes = false
	_d._play_spotlight_retry_sting()
	await _frames(3)
	assert_gt(_d._effects_rect.color.r, 0.5, "CONTROL: with the setting off, the sting peaks red")
	assert_gt(_d._effects_rect.color.a, 0.0, "CONTROL: and the red is on screen")
	await _until_hidden()
	assert_false(_d._effects_rect.visible, "CONTROL: the first sting finished and hid its rect")
	GameState.reduce_flashes = true
	_d._play_spotlight_retry_sting()
	var reds := 0.0
	var peak_a := 0.0
	for i in 20000:
		await get_tree().process_frame
		reds = maxf(reds, _d._effects_rect.color.r * _d._effects_rect.color.a)
		peak_a = maxf(peak_a, _d._effects_rect.color.a)
		if not _d._effects_rect.visible:
			break
	assert_eq(reds, 0.0, "with Reduce Flashes on, the sting draws no red at any frame")
	assert_gt(peak_a, 0.0, "but it still fades the screen toward black, so the retry still reads")
