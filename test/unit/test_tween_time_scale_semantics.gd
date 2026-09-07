extends GutTest

## What a tween DURATION means under Engine.time_scale — measured in-engine, not derived.
##
## Four lanes published opposite claims about this in one evening: that the compensated form runs
## 10x fast in hitlag, that it cannot be corrupted at all, and that a bare duration is 4x sluggish
## at the default rung. They rest on one fact nobody printed — whether a tween consumes ENGINE
## time continuously or latches a wall-clock target when it is created.
##
## Assertions are on RELATIONSHIPS (ratios, invariance) not on absolute milliseconds: headless
## frame pacing is noisy and an absolute pin here would be a coincidental value.

const D := 0.2
const TOL := 0.45

var _saved_scale: float = 1.0


func before_each() -> void:
	_saved_scale = Engine.time_scale


func after_each() -> void:
	## Engine.time_scale is global and leaks across GUT tests exactly like the Input singleton.
	Engine.time_scale = _saved_scale


## Runs a tween to completion, returning the engine-seconds and wall-seconds it consumed.
func _run(duration: float, scale: float, mid_flight: Callable = Callable(), ignore_scale: bool = false) -> Dictionary:
	Engine.time_scale = scale
	## Headless reports a stale multi-frame delta on the first frames of a run, which finished the
	## very first tween in 2 frames. Settle the tree before timing anything.
	for _i in 8:
		await get_tree().process_frame
	var node := Node2D.new()
	add_child_autofree(node)
	var tw := node.create_tween()
	tw.set_ignore_time_scale(ignore_scale)
	tw.tween_property(node, "position:x", 100.0, duration)
	## Terminate on the finished SIGNAL, not on is_running(): a freshly created tween polls as
	## not-running before its first process frame, which ended the loop after 2 frames.
	var done := [false]
	tw.finished.connect(func() -> void: done[0] = true)
	var engine := 0.0
	var frames := 0
	var t0 := Time.get_ticks_usec()
	while not done[0] and frames < 20000:
		await get_tree().process_frame
		engine += node.get_process_delta_time()
		frames += 1
		if frames == 3 and mid_flight.is_valid():
			mid_flight.call()
	var wall := float(Time.get_ticks_usec() - t0) / 1000000.0
	return {"engine": engine, "wall": wall, "frames": frames, "x": node.position.x}


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= b * TOL


func test_a_bare_duration_is_engine_time_so_wall_clock_tracks_the_ladder() -> void:
	var fast: Dictionary = await _run(D, 1.0)
	var slow: Dictionary = await _run(D, 0.25)
	gut.p("bare %.2fs | ts=1.00 engine %.3f wall %.3f (%d frames) | ts=0.25 engine %.3f wall %.3f (%d frames)"
		% [D, fast["engine"], fast["wall"], fast["frames"], slow["engine"], slow["wall"], slow["frames"]])
	assert_gt(int(fast["frames"]), 1, "CONTROL: the tween must actually have run frames, or every number below is noise")
	assert_almost_eq(float(fast["x"]), 100.0, 0.5, "CONTROL: and reached its target value")
	assert_true(_near(float(fast["engine"]), D), "engine-time consumed must equal the authored duration at ts=1.0")
	assert_true(_near(float(slow["engine"]), D), "and the SAME at ts=0.25 — the duration is denominated in engine time")
	assert_true(float(slow["wall"]) > float(fast["wall"]) * 2.0,
		"so wall-clock stretches as time_scale falls: %.3fs at ts=0.25 vs %.3fs at ts=1.0" % [slow["wall"], fast["wall"]])


func test_the_compensated_form_holds_wall_clock_constant_across_the_ladder() -> void:
	## D * time_scale, then consumed at time_scale, cancels — this is Win98Menu's construction.
	var fast: Dictionary = await _run(D * 1.0, 1.0)
	var slow: Dictionary = await _run(D * 0.25, 0.25)
	gut.p("compensated | ts=1.00 wall %.3f | ts=0.25 wall %.3f" % [fast["wall"], slow["wall"]])
	assert_gt(int(slow["frames"]), 1, "CONTROL: the ts=0.25 tween must have run frames")
	assert_true(_near(float(slow["wall"]), float(fast["wall"])),
		"wall-clock must be invariant across rungs: %.3fs vs %.3fs" % [slow["wall"], fast["wall"]])


func test_a_running_tween_integrates_a_mid_flight_scale_change_rather_than_latching() -> void:
	## The fact that bounds hitlag's blast radius: a tween already in flight keeps consuming engine
	## time, so a brief window stretches it by the window's length — not by the window's ratio.
	var dipped: Dictionary = await _run(D, 1.0, func() -> void: Engine.time_scale = 0.1)
	gut.p("mid-flight dip to ts=0.1 | engine %.3f wall %.3f" % [dipped["engine"], dipped["wall"]])
	assert_gt(int(dipped["frames"]), 3, "CONTROL: the tween must outlive the frame the dip was applied on")
	assert_true(_near(float(dipped["engine"]), D),
		"engine-time consumed is still the authored duration — the tween did not latch a wall-clock target")


func test_the_compensated_form_IS_sampled_once_so_it_is_not_hitlag_immune() -> void:
	## Creating a compensated tween DURING a dip samples the dipped scale, then finishes at the
	## ladder rate — so it lands short. Mild, bounded, and not zero.
	var in_window: Dictionary = await _run(D * 0.1, 0.1, func() -> void: Engine.time_scale = 1.0)
	var nominal: Dictionary = await _run(D * 1.0, 1.0)
	gut.p("compensated sampled at ts=0.1 then restored | wall %.3f vs nominal %.3f" % [in_window["wall"], nominal["wall"]])
	assert_gt(int(in_window["frames"]), 1, "CONTROL: the in-window tween must have run frames")
	assert_true(float(in_window["wall"]) < float(nominal["wall"]),
		"a compensated duration sampled mid-dip finishes EARLY (%.3fs vs %.3fs) — 'immune' is too strong"
			% [in_window["wall"], nominal["wall"]])


func test_ignore_time_scale_is_immune_at_BOTH_ends_unlike_the_compensated_form() -> void:
	## The third arm. An audio envelope rides the MIXER clock, which does not slow with battle
	## speed, so it must opt out of game time entirely rather than compensate for it.
	## This is the property cowir-sfx's duck fix depends on, so it is pinned rather than assumed.
	var fast: Dictionary = await _run(D, 1.0, Callable(), true)
	var slow: Dictionary = await _run(D, 0.25, Callable(), true)
	var dipped: Dictionary = await _run(D, 1.0, func() -> void: Engine.time_scale = 0.1, true)
	gut.p("ignore_time_scale | ts=1.00 wall %.3f | ts=0.25 wall %.3f | mid-flight dip wall %.3f"
		% [fast["wall"], slow["wall"], dipped["wall"]])
	assert_gt(int(slow["frames"]), 1, "CONTROL: the ts=0.25 tween must have run frames")
	assert_true(_near(float(slow["wall"]), D),
		"wall-clock must hold at the ladder's slow end: %.3fs vs %.3fs authored" % [slow["wall"], D])
	assert_true(_near(float(fast["wall"]), D), "and at ts=1.0: %.3fs" % [fast["wall"]])
	## The discriminator: D*ts survives the ladder but NOT a dip at creation; this survives both.
	assert_true(_near(float(dipped["wall"]), D),
		"and through a mid-flight dip to 0.1: %.3fs — a variable read at neither end cannot be corrupted"
			% [dipped["wall"]])
