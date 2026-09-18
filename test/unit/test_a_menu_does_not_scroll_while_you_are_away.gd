extends GutTest

## `MenuRepeat` is POLLED — by design, because a held gamepad d-pad emits one press event and
## never echoes. Polling means it asks `Input.is_action_pressed` every frame and does not care why
## the answer is true.
##
## ⛔ A HELD ACTION SURVIVES FOCUS LOSS, so the menu kept stepping while the player was in another
## window — and FASTER than while they were watching, because the ramp had reached full speed.
## Measured before the fix, on a real MenuRepeat:
##     2.0s of holding, focused        21 steps  (ramping SLOW -> FAST)
##     FOCUS_OUT, still held           true
##     the NEXT 2.0s, unfocused        40 steps  (fully ramped, every tick)
##     held_time accumulated           3.95s
## The player alt-tabs with Down held and comes back to a cursor that has raced the menu.
##
## 🔑 `reset()`'s own docstring already asked for this — "Call when the menu closes or loses focus"
## — and no caller existed. Every one of the twelve `reset()` call sites is on a menu-CLOSE path,
## and the only `_notification` handler in all of `src/ui/` is the virtual gamepad's.
##
## 📌 FIXED IN `MenuRepeat`, NOT IN THE TWELVE MENUS THAT OWN ONE. A polled guard belongs beside
## the poll; twelve call sites is the wrong layer, and each would be a place to forget.

const HELD := "ui_down"


## Headless reports the window as FOCUSED, so the unfocused branch is unreachable through the real
## query and the predicate is injected. These arms therefore ALSO pin that the shipped default is
## the real query — see `test_the_default_predicate_is_the_real_window_query`.
func _repeat(focused: bool) -> MenuRepeat:
	var r := MenuRepeat.new()
	r.focused_check = func() -> bool: return focused
	return r


func _steps(r: MenuRepeat, seconds: float) -> int:
	var n := 0
	var t := 0.0
	while t < seconds:
		if r.tick(0.05) != "":
			n += 1
		t += 0.05
	return n


func before_each() -> void:
	Input.action_press(HELD)
	Input.flush_buffered_events()


func after_each() -> void:
	for a in InputMap.get_actions():
		Input.action_release(a)
	Input.flush_buffered_events()


## ⛔ THE CONTROL, and it has to come first: if a held direction does not repeat while FOCUSED,
## the arm below is satisfied by a class that never repeats at all.
func test_a_held_direction_repeats_while_the_window_is_focused() -> void:
	assert_true(Input.is_action_pressed(HELD), "CONTROL: the direction must actually be held")
	var r := _repeat(true)
	var n := _steps(r, 2.0)
	assert_gt(n, 5,
		"CONTROL: holding a direction for 2s in a focused window must auto-repeat, got %d step(s)" % n)
	assert_eq(r.current_action(), HELD, "CONTROL: …and it must be repeating the held action")


## ⛔ THE DEFECT.
func test_a_held_direction_does_not_repeat_while_the_window_is_not() -> void:
	var r := _repeat(false)
	var n := _steps(r, 2.0)
	assert_eq(n, 0,
		"the window is not focused and the player is elsewhere, but a held direction still stepped "
		+ "%d time(s) — this is polled, so the hold survives focus loss and the menu scrolls on "
			% n
		+ "without them, at the full ramped rate")


## ⛔ THE RAMP MUST BE DROPPED, NOT PAUSED, and nothing else here catches the difference. A fix that
## merely skipped the step while unfocused would pass the arm above and then resume at FULL SPEED
## the instant focus returned — the cursor still races, just one frame later.
func test_returning_starts_from_a_fresh_delay_rather_than_full_speed() -> void:
	var r := MenuRepeat.new()
	## ⚠️ AN ARRAY, NOT A LOCAL BOOL. GDScript lambdas capture locals BY VALUE at creation, so
	## reassigning a captured `bool` never reaches the closure — the predicate stays stuck on its
	## initial answer and this arm silently becomes "focused the whole time". Measured: it failed
	## with held_time 2.95s against a source that resets correctly. An Array is a reference type,
	## so the closure sees the change.
	var focused := [true]
	r.focused_check = func() -> bool: return focused[0]

	_steps(r, 2.0)
	assert_gt(r.held_time(), MenuRepeat.INITIAL_DELAY,
		"CONTROL: the ramp must be built up before we test that it is discarded")

	focused[0] = false
	_steps(r, 1.0)
	assert_eq(r.held_time(), 0.0,
		"losing focus must DROP the hold, not pause it — held_time %.2fs survived" % r.held_time())

	focused[0] = true
	var first := r.tick(0.05)
	assert_eq(first, "",
		"…so the very first tick after returning must not step: the player is owed the full "
		+ "initial delay again, exactly as they are when a menu reopens")


## ⛔ THE WIRING. Every arm above drives an INJECTED predicate, so without this one they would all
## pass with the shipped default pointing anywhere at all — the shape that tests a workaround's
## policy and never the source.
##
## ⚠️ VALUE AGREEMENT ALONE DOES NOT CATCH A STUB, AND I MEASURED THAT RATHER THAN ASSUMING IT.
## This arm was `assert_eq(focused_check.call(), DisplayServer.window_is_focused())`, and defaulting
## the predicate to `func(): return true` left it GREEN — headless the real query is also true, so
## it compared true to true. `is_custom()` is the discriminator: `false` for a bound method, `true`
## for a lambda. It pins the SHAPE of the wiring without pinning the method's NAME, so a rename —
## a correct refactor — stays green.
##
## 📌 THE LIMIT, STATED: a bound method that hardcoded `true` is still indistinguishable here,
## because nothing headless can make the real window unfocused. That is irreducible without a
## source scan, and a source scan is the spelling pin this lane has spent the day removing.
func test_the_default_predicate_is_the_real_window_query() -> void:
	var r := MenuRepeat.new()
	assert_true(r.focused_check.is_valid(), "a fresh MenuRepeat must have its predicate wired")
	assert_false(r.focused_check.is_custom(),
		"the default must be a bound METHOD on the instance, not a lambda or a constant — a stubbed "
		+ "`func(): return true` agrees with the real query on every headless run and every arm "
		+ "above would still pass")
	assert_eq(r.focused_check.get_object(), r,
		"…and it must be bound to this MenuRepeat, so the shipped object is the one being asked")
	assert_eq(r.focused_check.call(), DisplayServer.window_is_focused(),
		"…and its answer must agree with the real window query")
	assert_true(DisplayServer.window_is_focused(),
		"CONTROL: headless reports the window as focused — which is why the arms above inject, and "
		+ "why a suite run cannot accidentally take the unfocused branch")
