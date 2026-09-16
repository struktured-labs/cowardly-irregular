extends GutTest

## The director's fast-forward contract — a held confirm runs a hold FAST_FORWARD_RATE (4x) faster —
## is honoured by `_sleep`, by `_await_tween_hold` (fades, flashes, shakes) and by the dialogue box's
## own typewriter. It was NOT honoured by a staged WALK: `_step_move_actor` polls `a._walking`
## directly, so everything around a walk sped up 4x and the walk itself ran full length. Its own
## docstring claims the fades were "the last holds that ignored both"; the walks were still ignoring it.
##
## 🔑 The rate scales the tween AND the animation cadence together. Scaling only the tween would
## reintroduce the skate this branch's parent just removed — 4x the ground per second with the same
## leg cycle — so `_process` divides by `speed * rate`, which is why they cannot come apart.
##
## And `nearby_scatter` needed it on both halves: its WAIT already honoured the confirm (it is a
## `_sleep`), so without the walks the wait ended 4x sooner than the crowd arrived and the scene moved
## on over puppets still walking.

const ActorScript = preload("res://src/cutscene/CutsceneActor.gd")
const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")


func after_each() -> void:
	Input.action_release("ui_accept")


func _walker(speed: float = ActorScript.DEFAULT_WALK_SPEED) -> Node:
	var a = ActorScript.new()
	add_child_autofree(a)
	a.global_position = Vector2.ZERO
	a.walk_to(Vector2(600, 0), speed)
	return a


## A new walk starts at normal rate — a button held through the LAST walk must not carry into it.
func test_a_fresh_walk_starts_at_normal_rate() -> void:
	var a := _walker()
	assert_eq(a._walk_rate, 1.0, "walk_to must reset the rate")
	a.set_walk_rate(4.0)
	a.walk_to(Vector2(1200, 0), ActorScript.DEFAULT_WALK_SPEED)
	assert_eq(a._walk_rate, 1.0, "and the next walk_to must reset it again")


## The rate reaches the tween, measured by DISTANCE COVERED rather than by asking the tween.
## ⛔ The first version of this arm read `Tween.get_speed_scale()`, which does not exist in Godot 4:
## the call errored, the GDScript error ABORTED the test function, and GUT scored it PASSED. It was
## vacuous on the clean tree and stayed green under the mutation that removed the speed-scale
## entirely. Only the mutation exposed it. Drive the thing; do not interview it.
func test_the_rate_reaches_the_walk_tween() -> void:
	var slow := _walker()
	var fast := _walker()
	assert_true(fast._walk_tween != null and fast._walk_tween.is_valid(),
		"PRECONDITION: a walk tween must exist")
	fast.set_walk_rate(DirectorScript.FAST_FORWARD_RATE)
	for i in 6:
		await get_tree().process_frame
	assert_gt(slow.global_position.x, 0.0, "control: the un-hurried walk must be moving at all")
	assert_gt(fast.global_position.x, slow.global_position.x * 1.5,
		"a hurried walk must cover more ground: %.1f px vs %.1f px" % [fast.global_position.x, slow.global_position.x])


## ⛔ THE COUPLING: the stride must stay put at 4x, or fast-forward reintroduces the skate.
func test_the_stride_survives_the_fast_forward() -> void:
	var base: float = ActorScript.DEFAULT_WALK_SPEED * ActorScript.frame_time_for(ActorScript.DEFAULT_WALK_SPEED)
	for rate in [1.0, 2.0, DirectorScript.FAST_FORWARD_RATE]:
		var effective: float = ActorScript.DEFAULT_WALK_SPEED * float(rate)
		assert_almost_eq(effective * ActorScript.frame_time_for(effective), base, 0.01,
			"at rate %.0fx a frame must still cover %.1f px — a tween-only speed-up IS the skate" % [rate, base])


## BEHAVIOURAL: a hurried walker really does advance its cycle faster.
func test_a_hurried_walker_cycles_faster() -> void:
	var a := _walker()
	a.set_walk_rate(DirectorScript.FAST_FORWARD_RATE)
	var before: int = a._anim_frame
	# A quarter of a normal frame time is a whole one at 4x.
	a._process(ActorScript.frame_time_for(ActorScript.DEFAULT_WALK_SPEED) * 0.3)
	assert_ne(a._anim_frame, before,
		"at 4x, 30%% of a normal frame time must already have advanced a frame")


## CONTROL: the same slice of time at normal rate must NOT advance it, else the arm above is free.
func test_control_the_same_slice_does_nothing_at_normal_rate() -> void:
	var a := _walker()
	var before: int = a._anim_frame
	a._process(ActorScript.frame_time_for(ActorScript.DEFAULT_WALK_SPEED) * 0.3)
	assert_eq(a._anim_frame, before, "30%% of a frame time is not a frame at normal rate")


## A nonsense rate must not divide by zero or freeze the legs.
func test_a_zero_rate_is_clamped() -> void:
	var a := _walker()
	a.set_walk_rate(0.0)
	assert_gt(a._walk_rate, 0.0, "a zero rate must be clamped, not stored")
	a.set_walk_rate(-4.0)
	assert_gt(a._walk_rate, 0.0, "and so must a negative one")


## The DIRECTOR must apply it on BOTH walk paths — by different structures, deliberately:
## move_actor polls its own walk so it reads the confirm itself; the scatter's hold is a `_sleep`,
## which already owns the contract, so it rides `_sleep`'s rate through the hook instead of reading
## the input a second time. Two rates would be two things to keep in step.
func test_both_director_walk_paths_hurry_their_walks() -> void:
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	for fn in ["_step_move_actor", "_step_nearby_scatter"]:
		var i := src.find("func %s" % fn)
		assert_gt(i, -1, "%s must exist" % fn)
		var next: int = src.find("\nfunc ", i + 1)
		var body := src.substr(i, (next - i) if next > -1 else 2000)
		assert_true("set_walk_rate(" in body,
			"%s must hurry its walk like every other hold" % fn)
	var mi := src.find("func _step_move_actor")
	var mbody := src.substr(mi, src.find("\nfunc ", mi + 1) - mi)
	assert_true("FAST_FORWARD_RATE" in mbody and "is_action_pressed(\"ui_accept\")" in mbody,
		"move_actor polls its own walk, so it reads the same held confirm the rest of the contract reads")
	var si := src.find("func _step_nearby_scatter")
	var sbody := src.substr(si, src.find("\nfunc ", si + 1) - si)
	assert_true("_sleep(longest, func(rate: float)" in sbody,
		"the scatter must ride _sleep's rate rather than read the input again — one rate, one place")


## The scatter's WAIT and its WALKS must hurry together — that pairing is the whole bug there.
func test_the_scatter_wait_and_its_walks_hurry_together() -> void:
	var src := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	var i := src.find("func _step_nearby_scatter")
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 2000)
	assert_true("_sleep(longest, func(rate: float)" in body,
		"the wait must STILL be _sleep — it owns the hold contract and an existing guard pins that — with a hook that hurries the walkers on the same rate")
	assert_true("set_walk_rate(rate)" in body,
		"and the hook must actually hurry them, or the wait ends 4x sooner than the crowd arrives")
	var sl := FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	var si := sl.find("func _sleep(")
	var snext: int = sl.find("\nfunc ", si + 1)
	var sbody := sl.substr(si, (snext - si) if snext > -1 else 900)
	assert_true("on_tick.call(rate)" in sbody and "elapsed += get_process_delta_time() * rate" in sbody,
		"the hook must ride the rate the hold itself advances at — two separate rates is how they come apart")
