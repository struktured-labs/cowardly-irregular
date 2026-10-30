extends GutTest

## Regression: struktured reported battle menu navigation as "sluggish... it's subtle" while
## playing v3.33.745-alpha. MenuRepeat timed its ramp off _process's delta, which carries
## Engine.time_scale -- 0.25 for battle "1x" -- so INITIAL_DELAY 0.40 took 1.60 s of real time.
## Subtle because a TAP is unaffected: only a held direction drags.

const SCALE := 0.25   ## Engine.time_scale at battle speed "1x" (the v3 scale)
const FRAME := 0.016

var _r: MenuRepeat


func before_each() -> void:
	_r = MenuRepeat.new(PackedStringArray(["ui_down"]))
	_r.focused_check = func() -> bool: return true


func after_each() -> void:
	## Input leaks across GUT tests (CLAUDE.md): a stuck ui_down drags later physics tests.
	Input.action_release("ui_down")


## Advance `real_secs` of wall clock while handing tick() the SCALED delta a battle _process
## would pass. Returns how many auto-steps fired.
func _run(real_secs: float, scale: float) -> int:
	var t := [0.0]
	_r.clock = func() -> float: return t[0]
	Input.action_press("ui_down")
	_r.tick(FRAME * scale)          # first frame only adopts the direction
	var steps := 0
	var elapsed := 0.0
	while elapsed < real_secs:
		t[0] += FRAME
		elapsed += FRAME
		if _r.tick(FRAME * scale) != "":
			steps += 1
	return steps


func test_the_file_reaches_every_symbol_it_names() -> void:
	## Floor: these are lane-local, so nothing else in the corpus reds on a rename.
	for m in ["tick", "reset", "held_time", "current_action"]:
		assert_true(_r.has_method(m), "MenuRepeat lost method %s" % m)
	assert_true(_r.clock is Callable, "MenuRepeat.clock is not an injectable Callable")
	assert_true(_r.focused_check is Callable, "MenuRepeat.focused_check is not a Callable")


func test_a_held_direction_repeats_on_wall_clock_not_battle_time() -> void:
	## THE DEFECT: at battle 1x this needed 1.60 s of real holding to produce one step.
	var want := MenuRepeat.INITIAL_DELAY + MenuRepeat.SLOW_INTERVAL + 0.05
	assert_gt(_run(want, SCALE), 0,
		"held %.2fs real at time_scale %.2f and the menu never auto-stepped" % [want, SCALE])


func test_the_initial_delay_is_still_respected() -> void:
	## THE CONTROL. Without it the arm above passes for a ramp that fires instantly, which
	## would be a different defect wearing this fix's clothes.
	assert_eq(_run(MenuRepeat.INITIAL_DELAY * 0.5, SCALE), 0,
		"auto-stepped before INITIAL_DELAY had elapsed in real time")


func test_battle_speed_no_longer_changes_how_fast_the_menu_feels() -> void:
	## The tell that it was time_scale: nav was FOUR TIMES faster at 4x than at 1x, so every
	## lane testing at speed saw the designed behaviour. Same real hold, both scales, same steps.
	var want := MenuRepeat.INITIAL_DELAY + MenuRepeat.SLOW_INTERVAL * 3.0
	var at_1x := _run(want, SCALE)
	before_each()
	var at_4x := _run(want, 1.0)
	assert_eq(at_1x, at_4x,
		"same real hold gave %d steps at 1x and %d at 4x -- still reading scaled time" % [at_1x, at_4x])


func test_reopening_a_menu_does_not_inherit_a_stale_clock() -> void:
	## reset() must drop the baseline, or a menu closed for ten seconds reopens with a ten-second
	## gap on its first held frame and ramps to full speed instantly.
	var t := [0.0]
	_r.clock = func() -> float: return t[0]
	Input.action_press("ui_down")
	_r.tick(FRAME * SCALE)
	t[0] += FRAME
	_r.tick(FRAME * SCALE)
	_r.reset()
	t[0] += 10.0                     # menu was closed for ten seconds
	_r.tick(FRAME * SCALE)           # re-adopts the direction
	assert_eq(_r.tick(FRAME * SCALE), "",
		"a reopened menu auto-stepped on its first frame from a stale clock baseline")
	assert_lt(_r.held_time(), MenuRepeat.INITIAL_DELAY,
		"reset() left %.2fs of held time behind" % _r.held_time())


func test_the_default_clock_is_the_real_one() -> void:
	## Agreement arm, matching focused_check's precedent: driving an injected clock while the
	## shipped default reads something else would test the workaround's policy, not the source.
	var fresh := MenuRepeat.new(PackedStringArray(["ui_down"]))
	var a: float = float(fresh.clock.call())
	var b: float = float(fresh.clock.call())
	assert_gt(a, 0.0, "default clock returned %f -- not wired to a real time source" % a)
	assert_gte(b, a, "default clock went backwards: %f then %f" % [a, b])
