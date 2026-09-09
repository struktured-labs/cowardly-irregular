extends GutTest

## Completes the hold-confirm fast-forward: the dialogue box already runs ahead while confirm
## is held, but the Director's waits / emotes / say / title holds between lines ran at full
## length, so a player holding A through a scene still stalled at every beat. _sleep now
## advances FAST_FORWARD_RATE times faster while ui_accept is held — one hold, one meaning.
## Hold-B skip is untouched and still cuts a hold short the same frame.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")

var _d: Node


func before_each() -> void:
	Input.action_release("ui_accept")
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_d._skipping = false


func after_each() -> void:
	Input.action_release("ui_accept")  # the Input singleton leaks across tests


## Runs a wait step and returns how much ENGINE time passed before it released (2s budget).
func _time_a_wait(duration: float) -> float:
	var done := [false]
	var runner := func() -> void:
		await _d._step_wait({"type": "wait", "duration": duration})
		done[0] = true
	runner.call()
	var elapsed := 0.0
	while not done[0] and elapsed < 2.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return elapsed


func test_held_confirm_runs_a_wait_faster() -> void:
	Input.action_press("ui_accept")
	var t := await _time_a_wait(0.5)
	assert_lt(t, 0.3, "a 0.5s wait under held confirm must release in ~0.125s of engine time, took %s" % t)
	assert_gt(t, 0.0, "control: it must still take SOME time — a zero-length wait is the skip path, not fast-forward")


func test_a_wait_without_the_hold_runs_at_full_length() -> void:
	# ARM+: a _sleep that always ran fast would pass the test above.
	var t := await _time_a_wait(0.5)
	assert_gte(t, 0.45, "without the hold a 0.5s wait must take ~0.5s of engine time, took %s" % t)


func test_the_rate_is_what_the_constant_says() -> void:
	# Pins the RATIO, not a magic number: unheld/held ≈ FAST_FORWARD_RATE within frame granularity.
	var slow := await _time_a_wait(0.4)
	Input.action_press("ui_accept")
	var fast := await _time_a_wait(0.4)
	Input.action_release("ui_accept")
	assert_gt(fast, 0.0)
	var ratio := slow / fast
	# LITERAL floor first: an expectation derived only from the constant moves with a mutation
	# of that constant (rate 1.0 scored green here on the first arm — ratio 1 "matched" 1).
	assert_gt(ratio, 2.5, "held confirm must run holds at least 2.5x faster, measured %.2fx" % ratio)
	var expected: float = DirectorScript.FAST_FORWARD_RATE
	assert_true(ratio > expected * 0.6 and ratio < expected * 1.6,
		"unheld/held ratio %.2f should sit near FAST_FORWARD_RATE %.1f" % [ratio, expected])


func test_skip_still_cuts_a_held_wait_short() -> void:
	Input.action_press("ui_accept")
	var done := [false]
	var runner := func() -> void:
		await _d._step_wait({"type": "wait", "duration": 30.0})
		done[0] = true
	runner.call()
	await get_tree().process_frame
	assert_false(done[0], "control: even at 4x a 30s wait is in flight after one frame")
	_d._skipping = true
	for i in 4:
		await get_tree().process_frame
	assert_true(done[0], "hold-B skip must still release a held wait within a few frames")
