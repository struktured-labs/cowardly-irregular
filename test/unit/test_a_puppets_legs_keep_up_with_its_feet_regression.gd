extends GutTest

## `CutsceneActor._process` advanced the walk cycle on a FIXED 0.12 s frame time, so the STRIDE — the
## px a puppet travels per animation frame, which is what makes feet look planted — tracked the
## authored walk speed. Measured 2026-09-16:
##
##   this actor, fixed 0.12s    default 120 -> 14.4 px   ·   authored 160 -> 19.2 px
##   OverworldPlayer, the SAME sheets and the same 4-frame cycle -> 19.2 px at ANY speed, because it
##                                                                 divides its frame time by speed
##
## Two gaits for one character, and the 12 authored walks split 10 (default) / 2 (160) across them.
## Neither looked broken — both are plausible gaits — which is why this sat.
##
## 📌 The invariant is anchored at DEFAULT_WALK_SPEED, so the 10 default walks are untouched and only
## the two authored-160 walks change. Anchoring at the player's 19.2 instead would do the opposite:
## same mechanism, opposite subset. That is a look call and it is struktured's.
## ⚠️ The anchor is therefore pinned in EXACTLY ONE arm — test_a_default_speed_walk_is_untouched —
## and every other arm measures in units of `frame_time_for()` so it is anchor-agnostic. If he moves
## the anchor, one arm reds and it is the one whose sentence stopped being true. Verified by mutating
## the anchor to 19.2: 1 red, that arm, not three.

const ActorScript = preload("res://src/cutscene/CutsceneActor.gd")


## Travel per animation frame at a given speed — the quantity the eye reads as planted or skating.
func _stride(speed: float) -> float:
	return speed * ActorScript.frame_time_for(speed)


func test_the_stride_does_not_change_with_speed() -> void:
	var base: float = _stride(ActorScript.DEFAULT_WALK_SPEED)
	for speed in [40.0, 70.0, 120.0, 160.0, 240.0, 400.0]:
		assert_almost_eq(_stride(float(speed)), base, 0.01,
			"at %.0f px/s a frame must still cover %.1f px — a stride that grows with speed IS the skate" % [speed, base])


## CONTROL: the old rule fails this, or the arm above is not measuring anything.
func test_control_a_fixed_frame_time_would_fail_that() -> void:
	var fixed_stride_at_160: float = 160.0 * ActorScript.ANIM_SPEED
	var fixed_stride_at_120: float = 120.0 * ActorScript.ANIM_SPEED
	assert_gt(absf(fixed_stride_at_160 - fixed_stride_at_120), 4.0,
		"the fixed 0.12s rule spread the stride by %.1f px between the two authored speeds" % absf(fixed_stride_at_160 - fixed_stride_at_120))


## The anchor: a default-speed walk is UNCHANGED, which is 10 of the 12 authored walks.
func test_a_default_speed_walk_is_untouched() -> void:
	assert_almost_eq(ActorScript.frame_time_for(ActorScript.DEFAULT_WALK_SPEED), ActorScript.ANIM_SPEED, 0.0001,
		"at the default speed the frame time must be exactly what it has always been")


## A faster walk gets a FASTER cycle, not the same one.
func test_a_faster_walk_cycles_faster() -> void:
	var slow: float = ActorScript.frame_time_for(ActorScript.DEFAULT_WALK_SPEED)
	var fast: float = ActorScript.frame_time_for(160.0)
	assert_lt(fast, slow, "160 px/s must advance frames sooner than 120 px/s")
	assert_almost_eq(fast, slow * (ActorScript.DEFAULT_WALK_SPEED / 160.0), 0.0001,
		"and by the speed ratio exactly — that is what keeps the stride fixed")


## A zero or negative speed must not divide: it keeps the anchor.
func test_a_stopped_actor_keeps_the_anchor() -> void:
	assert_eq(ActorScript.frame_time_for(0.0), ActorScript.ANIM_SPEED, "zero speed keeps the anchor")
	assert_eq(ActorScript.frame_time_for(-50.0), ActorScript.ANIM_SPEED, "and so does a negative one")


## BEHAVIOURAL: the running actor must USE it. A correct helper nobody calls looks identical from a
## source arm (cowir-sprites' mutation 7, three lanes over).
func test_the_walking_actor_uses_the_speed_it_was_given() -> void:
	var a = ActorScript.new()
	add_child_autofree(a)
	a._walking = true
	a._walk_speed = 240.0
	var before: int = a._anim_frame
	# Measured in THIS speed's own frame time, so the arm does not care where the anchor sits.
	var ft: float = ActorScript.frame_time_for(240.0)
	a._process(ft * 1.01)
	var mid: int = a._anim_frame
	a._process(ft * 1.01)
	assert_ne(mid, before, "one frame time at 240 px/s must advance a frame")
	assert_ne(a._anim_frame, mid, "and the next must advance another")
	assert_lt(ft, ActorScript.frame_time_for(ActorScript.DEFAULT_WALK_SPEED),
		"and 240 px/s must have a SHORTER frame time than the default, whatever the anchor is")


## And a default-speed walker advances on the anchor, not sooner.
func test_a_default_speed_walker_advances_on_the_anchor() -> void:
	var a = ActorScript.new()
	add_child_autofree(a)
	a._walking = true
	a._walk_speed = ActorScript.DEFAULT_WALK_SPEED
	var before: int = a._anim_frame
	var ft: float = ActorScript.frame_time_for(ActorScript.DEFAULT_WALK_SPEED)
	a._process(ft * 0.6)
	assert_eq(a._anim_frame, before, "60%% of a frame time is not a frame yet")
	a._process(ft * 0.6)
	assert_ne(a._anim_frame, before, "and 120%% of it is")


## walk_to must record the speed it is running at, or the cycle divides by a stale one.
func test_walk_to_records_its_speed() -> void:
	var a = ActorScript.new()
	add_child_autofree(a)
	a.global_position = Vector2.ZERO
	a.walk_to(Vector2(400, 0), 160.0)
	assert_almost_eq(a._walk_speed, 160.0, 0.01,
		"the animation reads _walk_speed; a walk that does not set it animates at the last walk's cadence")
