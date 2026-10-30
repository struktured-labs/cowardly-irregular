extends GutTest

## Regression: struktured reported battle menu navigation as "sluggish... it's subtle" while
## playing v3.33.745-alpha. MenuRepeat accumulated its ramp from _process's delta, which carries
## Engine.time_scale -- 0.25 for battle "1x" (the v3 scale) -- so INITIAL_DELAY 0.40 took 1.60 s
## of real holding. Subtle because a TAP is unaffected: only a held direction drags.

const BATTLE_1X := 0.25   ## Engine.time_scale at battle speed "1x"
const FRAME := 0.016

var _r: MenuRepeat
var _scale_before: float


func before_each() -> void:
	_scale_before = Engine.time_scale
	_r = MenuRepeat.new(PackedStringArray(["ui_down"]))
	_r.focused_check = func() -> bool: return true


func after_each() -> void:
	## Both of these leak across GUT tests: a stuck ui_down drags later physics tests
	## (CLAUDE.md), and a left-behind time_scale would silently retune every later await.
	Input.action_release("ui_down")
	Engine.time_scale = _scale_before


## Hold the direction for `real_secs` of REAL time at the given engine time_scale, feeding tick()
## exactly the scaled delta a battle _process hands it. Returns how many auto-steps fired.
func _steps_over(real_secs: float, scale: float) -> int:
	Engine.time_scale = scale
	Input.action_press("ui_down")
	_r.tick(FRAME * scale)          # the first frame only adopts the direction
	var steps := 0
	var elapsed := 0.0
	while elapsed < real_secs:
		elapsed += FRAME
		if _r.tick(FRAME * scale) != "":
			steps += 1
	return steps


func test_the_file_reaches_every_symbol_it_names() -> void:
	## Floor: these are lane-local, so nothing else in the corpus reds on a rename.
	for m in ["tick", "reset", "held_time", "current_action"]:
		assert_true(_r.has_method(m), "MenuRepeat lost method %s" % m)
	assert_true(_r.focused_check is Callable, "MenuRepeat.focused_check is not a Callable")


func test_a_held_direction_repeats_on_real_time_not_battle_time() -> void:
	## THE DEFECT: at battle 1x this took 1.60 s of real holding to produce one step.
	var want := MenuRepeat.INITIAL_DELAY + MenuRepeat.SLOW_INTERVAL + 0.05
	assert_gt(_steps_over(want, BATTLE_1X), 0,
		"held %.2fs real at time_scale %.2f and the menu never auto-stepped" % [want, BATTLE_1X])


func test_the_initial_delay_is_still_respected() -> void:
	## THE CONTROL. Without it the arm above passes for a ramp that fires instantly, which is a
	## different defect wearing this fix's clothes.
	assert_eq(_steps_over(MenuRepeat.INITIAL_DELAY * 0.5, BATTLE_1X), 0,
		"auto-stepped before INITIAL_DELAY had elapsed in real time")


func test_battle_speed_no_longer_changes_how_fast_the_menu_feels() -> void:
	## The tell that it was time_scale: the same real hold stepped FOUR TIMES faster at 4x, so
	## every lane testing at speed saw the designed behaviour and nobody saw his 1x.
	var want := MenuRepeat.INITIAL_DELAY + MenuRepeat.SLOW_INTERVAL * 3.0
	var at_1x := _steps_over(want, BATTLE_1X)
	before_each()
	var at_4x := _steps_over(want, 1.0)
	assert_eq(at_1x, at_4x,
		"same real hold gave %d steps at 1x and %d at 4x -- still reading scaled time" % [at_1x, at_4x])


func test_a_hard_pause_neither_ramps_nor_divides_by_zero() -> void:
	## time_scale 0 is the one value that could make the unscaling explode. Delta is 0 there too,
	## so the quotient stays 0: a paused menu holds its place rather than ramping or crashing.
	Engine.time_scale = 0.0
	Input.action_press("ui_down")
	_r.tick(0.0)
	for _i in range(200):
		assert_eq(_r.tick(0.0), "", "a menu auto-stepped while the game was hard-paused")
		if _r.held_time() > 0.0:
			break
	assert_eq(_r.held_time(), 0.0, "held time advanced %.4fs under a hard pause" % _r.held_time())
