extends GutTest

## Holding a menu direction must start stepping on its own, and accelerate.
## struktured 2026-08-22: "if I hold any menu button for a few seconds it should start
## moving on its own in that direction and faster".
##
## The timing lives in MenuRepeat and is tested WITHOUT a scene tree or real input: tick()
## takes delta and reads InputMap/Input, so the pure-timing arms below drive it through a
## real action press. A held gamepad d-pad emits ONE event and never echoes, which is why
## this is polled rather than event-driven — the thing the feature exists for cannot be
## tested by feeding echo events.

const ACTION := "ui_down"


func before_each() -> void:
	Input.action_release(ACTION)


func after_each() -> void:
	# A leaked press drags later physics/menu tests — documented hazard in CLAUDE.md.
	Input.action_release(ACTION)


func _held_ticks(r, seconds: float, step: float = 1.0 / 60.0) -> int:
	var fired := 0
	var t := 0.0
	while t < seconds:
		if r.tick(step) != "":
			fired += 1
		t += step
	return fired


func test_a_tap_never_repeats() -> void:
	# The menu's own _input owns the first step. If tick() fired immediately, every
	# keypress would move TWO rows.
	var r = MenuRepeat.new()
	Input.action_press(ACTION)
	assert_eq(r.tick(1.0 / 60.0), "", "one frame of hold must not repeat")
	Input.action_release(ACTION)
	assert_eq(r.tick(1.0 / 60.0), "", "release must not repeat")


func test_nothing_fires_in_the_first_tenth_of_a_second() -> void:
	# 0.10s is a normal keypress. Firing here makes every tap move TWO rows.
	# ABSOLUTE, not INITIAL_DELAY - x: a derived window goes negative under mutation
	# and the tick loop never runs, so the arm passes on a broken constant.
	var r = MenuRepeat.new()
	Input.action_press(ACTION)
	var fired := _held_ticks(r, 0.10)
	assert_eq(fired, 0, "a 0.10s tap must not auto-repeat")


func test_a_one_second_hold_is_already_stepping() -> void:
	var r = MenuRepeat.new()
	Input.action_press(ACTION)
	var fired := _held_ticks(r, 1.0)
	assert_gt(fired, 2, "1s of holding must have produced several steps, got %d" % fired)


func test_the_initial_delay_is_bounded_from_both_sides() -> void:
	# Two bounds from two DIFFERENT rationales, so no single edit satisfies both:
	# too short and a deliberate tap double-steps; too long and holding reads as broken.
	assert_gt(MenuRepeat.INITIAL_DELAY, 0.15, "shorter than a tap — taps would double-step")
	assert_lt(MenuRepeat.INITIAL_DELAY, 1.00, "longer than this reads as 'nothing happened'")
	assert_lt(MenuRepeat.FAST_INTERVAL, MenuRepeat.SLOW_INTERVAL,
		"fast must be faster than slow, or there is no acceleration to ramp toward")


func test_it_accelerates_the_longer_you_hold() -> void:
	# The behaviour struktured asked for: "and faster". Compare two EQUAL windows —
	# an absolute rate would be a coincidental-value pin.
	var r = MenuRepeat.new()
	Input.action_press(ACTION)
	_held_ticks(r, 0.45)                              # burn the delay
	var early := _held_ticks(r, 0.5)
	_held_ticks(r, 1.0)                               # ramp in
	var late := _held_ticks(r, 0.5)
	assert_gt(late, early,
		"the same window later in the hold must produce MORE steps (early=%d late=%d)" % [early, late])


func test_releasing_resets_the_ramp() -> void:
	# Otherwise a second press inherits the first hold's speed and the menu bolts.
	var r = MenuRepeat.new()
	Input.action_press(ACTION)
	_held_ticks(r, 1.4)
	Input.action_release(ACTION)
	r.tick(1.0 / 60.0)
	assert_eq(r.held_time(), 0.0, "release must clear the accumulated hold")
	Input.action_press(ACTION)
	assert_eq(_held_ticks(r, 0.10), 0,
		"a fresh press must serve its own delay, not inherit the old ramp")


func test_changing_direction_restarts_the_delay() -> void:
	# Flicking left during a long down-hold must not fire instantly.
	var r = MenuRepeat.new()
	Input.action_press("ui_down")
	_held_ticks(r, 1.4)
	Input.action_release("ui_down")
	Input.action_press("ui_up")
	var fired := _held_ticks(r, 0.10)
	Input.action_release("ui_up")
	assert_eq(fired, 0, "a new direction serves its own delay, not the old ramp")


func test_the_three_named_menus_consult_the_shared_helper() -> void:
	# Reachability: the helper existing is worthless if no menu ticks it. Enumerated by
	# the surfaces struktured named, with a control so a moved call site reds.
	var wired := {
		"res://src/ui/Win98Menu.gd": "battle command menu",
		"res://src/ui/OverworldMenu.gd": "overworld menu",
		"res://src/ui/SettingsMenu.gd": "settings menu",
	}
	for path in wired:
		var src: String = FileAccess.get_file_as_string(path)
		assert_ne(src, "", "menu must be readable: %s" % path)
		assert_true(src.contains("MenuRepeat.new("),
			"%s must construct the shared helper" % wired[path])
		assert_true(src.contains("_nav_repeat.tick("),
			"%s must TICK it — an unticked helper never fires" % wired[path])


func test_the_repeat_reuses_the_same_step_path_as_a_keypress() -> void:
	# Two implementations of "move the cursor" drift. Both paths must call _nav_step.
	for path in ["res://src/ui/OverworldMenu.gd", "res://src/ui/SettingsMenu.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_true(src.contains("func _nav_step("), "%s must extract one step path" % path)
		assert_gt(src.count("_nav_step("), 2,
			"%s must call _nav_step from BOTH _input and the repeat" % path)
