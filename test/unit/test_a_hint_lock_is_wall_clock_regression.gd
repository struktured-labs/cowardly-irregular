extends GutTest

## Regression: TutorialHint timed its 2.0 s min-dismiss lock and 8 s auto-dismiss off _process's
## delta, which carries Engine.time_scale. Battle runs at 0.25 ("1x") to 0.375 ("1.5x"), and the
## hint swallows EVERY input while the lock holds — so spotlight_unlock, shown mid-battle, froze a
## player for 8 real seconds at 1x and the hint lingered 32 s. Same defect as MenuRepeat (.746).
## The clock is injected so each arm drives exact real seconds without waiting on wall time.

var _saved_scale := 1.0
var _t := 100.0


func before_each() -> void:
	_saved_scale = Engine.time_scale
	_t = 100.0


func after_each() -> void:
	Engine.time_scale = _saved_scale
	## show_hint marks tutorial_<id> shown in GameState; a probe must not leave flags behind.
	for k in GameState.game_constants.keys():
		if str(k).begins_with("tutorial_wall_clock_probe_"):
			GameState.game_constants.erase(k)


func _hint(min_dismiss: float) -> TutorialHint:
	var h := TutorialHint.new()
	add_child_autofree(h)
	h.clock = func() -> float: return _t
	h.show_hint("wall_clock_probe_%d" % randi(), "T", "B", min_dismiss)
	return h


## One rendered frame of `real` seconds at the current battle speed: delta is what the engine passes.
func _frame(h: TutorialHint, real: float) -> void:
	_t += real
	h._process(real * Engine.time_scale)


func _press() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_X
	e.pressed = true
	return e


func test_the_lock_ends_after_its_real_seconds_at_battle_speed() -> void:
	Engine.time_scale = 0.25
	var h := _hint(2.0)
	_frame(h, 0.016)
	_frame(h, 2.1)
	assert_eq(h._min_dismiss_timer, 0.0, "2.1 real seconds must clear a 2.0 s lock at 1x battle speed")
	h._input(_press())
	assert_false(h._active, "and the next press must dismiss it")


func test_the_lock_still_holds_inside_its_window() -> void:
	## CONTROL: the clock must not clear the lock early, or the arm above passes on a dead timer.
	Engine.time_scale = 0.25
	var h := _hint(2.0)
	_frame(h, 0.016)
	_frame(h, 1.0)
	assert_gt(h._min_dismiss_timer, 0.0, "one real second into a 2.0 s lock it must still hold")
	h._input(_press())
	assert_true(h._active, "and a press inside the window must not dismiss")


func test_auto_dismiss_is_eight_real_seconds_at_battle_speed() -> void:
	Engine.time_scale = 0.375
	var h := _hint(0.0)
	_frame(h, 0.016)
	_frame(h, 7.0)
	assert_true(h._active, "7 real seconds: still showing")
	_frame(h, 1.1)
	assert_false(h._active, "8.1 real seconds: auto-dismissed, at 1.5x battle speed as at 1.0")


func test_the_default_clock_is_the_engine_tick() -> void:
	var h := TutorialHint.new()
	add_child_autofree(h)
	var a: float = float(h.clock.call())
	var expect: float = float(Time.get_ticks_usec()) / 1000000.0
	assert_almost_eq(a, expect, 0.5, "the shipped clock must read real time, not a stub")
