extends GutTest

## ⛔ ONE FLICK OF THE LEFT STICK CLAIMED SIX CONTROLS.
##
## The mapping walk filtered button press/release (`not event.pressed -> return`) but had no
## equivalent for AXES, and an axis does not fire once — a stick push emits every sample on the
## way up and on the way back down. `binding_token` gates at 0.5, so a single flick delivers
## several qualifying events in a row, and `record()` took each one as the answer to whatever
## control it happened to be asking for next. Measured before the fix, feeding the ramp the
## engine actually emits:
##
##     at step 'leftx', one push of axis 0  ->  advanced 6 steps, landing on 'dpleft'
##     leftx a0 · lefty a0 · rightx a0 · righty a0   (+ dpup, dpdown)
##
## 🔑 AND IT BUILT. `missing_required()` was satisfied — every name was present, just wrong — so
## the walk emitted a complete-looking SDL string, `Input.add_joy_mapping` registered it LIVE,
## and `_append_user_mapping` persisted it to user://. A player whose left stick now drives X, Y,
## both right-stick axes and two d-pad directions at once, written on the screen they opened to
## FIX their pad, surviving the next launch.
##
## The fix is a duplicate-token refusal rather than an axis rest-gate, because it covers the
## other reachable way in as well: a player pressing the same BUTTON for two prompts. One
## physical input serving two SDL controls is malformed either way, so the walk now waits for a
## genuinely different control instead of burning the step.
##
## Behavioural throughout — ControllerMappingCapture is deliberately free of UI and of Input
## polling, so none of this needs to read source.

const CAPTURE := "res://src/input/ControllerMappingCapture.gd"
const GUID := "03000000123456789abcdef012345678"


func _cap():
	return load(CAPTURE).new(GUID, "Probe Pad", "Linux")


func _motion(axis: int, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	return e


func _button(idx: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = idx
	e.pressed = true
	return e


## Walk the capture up to the first axis prompt using distinct buttons.
## ⛔ BOUNDED, like both walk loops. Every loop here waits on the SUBJECT advancing, so any
## mutation that stops it advancing spins forever — and a hung test does not fail, it gets
## killed, which on a shared 5-10 minute gate is far worse than a red. Learned by hanging two
## godot processes on one arm; the second outlived its own sweep and left a mutation in the tree.
func _to_first_axis(cap) -> void:
	var i := 0
	while cap.current_control() != "leftx" and not cap.is_complete() and i < 200:
		cap.record(_button(i))
		i += 1
	assert_lt(i, 200, "BOUND: the walk must reach the stick prompt, not spin")
	assert_eq(cap.current_control(), "leftx",
		"precondition: the walk must reach the first stick prompt")


## ⛔ THE DEFECT. One push of one axis may claim exactly one control.
func test_one_stick_flick_claims_exactly_one_control() -> void:
	var cap = _cap()
	_to_first_axis(cap)
	var advanced := 0
	# the ramp an engine really emits for a push and release, not a single idealised event
	for v in [0.12, 0.31, 0.55, 0.74, 0.91, 1.0, 0.88, 0.61, 0.44, 0.10, 0.0]:
		if cap.record(_motion(0, v)):
			advanced += 1
	assert_eq(advanced, 1,
		"one flick of ONE axis must advance ONE step — before 2026-09-12 it advanced 6, binding " +
		"a0 to leftx, lefty, rightx, righty and two d-pad directions from a single push")
	assert_eq(str(cap.bindings.get("leftx", "")), "a0", "…and the one it claimed is the one asked for")
	assert_false(cap.bindings.has("lefty"),
		"the NEXT control must still be waiting — a stick that streams must not answer for it")


## The same input cannot serve two controls, whichever way it arrives.
func test_a_repeated_button_is_refused_too() -> void:
	var cap = _cap()
	assert_true(cap.record(_button(0)), "the first press must record")
	var claimed: String = cap.current_control()
	assert_false(cap.record(_button(0)),
		"pressing the SAME button for the next prompt must be refused — SDL accepts the duplicate " +
		"and then reports the wrong physical control")
	assert_eq(cap.current_control(), claimed, "…and the walk must not have advanced")


## The refusal must NAME what already owns the input, or the walk is a screen that ignores you.
func test_the_refusal_names_the_control_that_owns_it() -> void:
	var cap = _cap()
	cap.record(_button(3))
	assert_eq(cap.control_using("b3"), "a",
		"the token's owner must be reportable, so the overlay can say why it refused")
	assert_eq(cap.control_using("b9"), "",
		"CONTROL: an unused token must have no owner — otherwise every event reads as a duplicate")


## ⛔ THE OTHER DIRECTION, so the refusal cannot become "nothing records". A correct walk, with
## every push STREAMING exactly as the engine emits it, must still complete and build.
func test_a_correct_walk_still_completes_and_builds() -> void:
	var cap = _cap()
	var axis_next := 0
	var btn_next := 0
	var steps := 0
	var spins := 0
	while not cap.is_complete() and spins < 200:
		spins += 1
		var ctl: String = cap.current_control()
		var ok := false
		if ctl in ["leftx", "lefty", "rightx", "righty"]:
			for v in [0.6, 0.85, 1.0, 0.7]:
				if cap.record(_motion(axis_next, v)):
					ok = true
			axis_next += 1
		else:
			ok = cap.record(_button(btn_next))
			btn_next += 1
		assert_true(ok, "a distinct control must still register — stuck at '%s'" % ctl)
		if not ok:
			return
		steps += 1
	assert_lt(spins, 200, "BOUND: the walk must terminate, not spin — see the note on the other loop")
	assert_eq(steps, cap.CONTROLS.size(), "every control in the walk must have been answered")
	assert_eq(cap.missing_required(), [] as Array[String], "a full walk leaves nothing required outstanding")
	assert_gt(cap.build().length(), 0, "…and it must still emit a mapping")


## The finished mapping must carry no duplicate token — the property the defect violated.
func test_a_finished_mapping_binds_each_input_once() -> void:
	var cap = _cap()
	var axis_next := 0
	var btn_next := 0
	## ⛔ BOUNDED, and this cost a killed suite run to learn. The first version looped on
	## `not is_complete()` with no escape when `record()` refused. Mutating `control_using` to
	## refuse EVERYTHING — an ordinary arm — made it spin forever: the runner timed out, and the
	## sweep died before its restore line, leaving the mutation in the tree. A guard that can hang
	## is worse than one that is wrong, because the fleet gate is 5-10 minutes and shared.
	var spins := 0
	while not cap.is_complete() and spins < 200:
		spins += 1
		if cap.current_control() in ["leftx", "lefty", "rightx", "righty"]:
			for v in [0.6, 0.9]:
				cap.record(_motion(axis_next, v))
			axis_next += 1
		else:
			cap.record(_button(btn_next))
			btn_next += 1
	assert_lt(spins, 200, "BOUND: the walk must terminate even when every record is refused")
	var seen := {}
	for name in cap.bindings:
		var tok: String = str(cap.bindings[name])
		assert_false(seen.has(tok),
			"'%s' and '%s' both bound %s — one physical input cannot serve two SDL controls" % [
				seen.get(tok, ""), name, tok])
		seen[tok] = name
	assert_gt(seen.size(), 15, "CONTROL: the walk must really have bound a full pad, not two rows")


## The OTHER half of the same defence, and nothing else here asserts it: the 0.5 gate. Without
## it a resting stick's drift claims a control, and the duplicate refusal would NOT catch that —
## the first noise sample records, and every later one is refused as a duplicate, so the flick
## arm above still reads "advanced 1". Pinned separately because one mutation must not satisfy
## two independent claims.
func test_a_resting_stick_claims_nothing() -> void:
	var cap = _cap()
	_to_first_axis(cap)
	for v in [0.0, 0.04, 0.19, -0.3, 0.49]:
		assert_false(cap.record(_motion(0, v)),
			"axis %.2f is rest or drift and must not claim a control" % v)
	assert_false(cap.bindings.has("leftx"),
		"…so the stick prompt must still be waiting for a decisive push")
