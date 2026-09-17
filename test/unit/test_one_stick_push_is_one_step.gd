extends GutTest

## One stick push must move a cursor exactly as far as one d-pad press — asked of each SURFACE.
##
## ⛔ ui_up/ui_down bind the left stick's Y axis as well as the d-pad, and an AXIS CARRIES NO ECHO
## FLAG, so every step of an analog ramp reads as a fresh press. Measured on the shipped build
## before this branch, one push of the stick:
##
##     BossSelectorMenu  selected_index 0 -> 5      ControlsMenu  selected_index 0 -> 5
##     FormationsMenu    _selected      0 -> 5      LensMenu      _selected      0 -> 3
##
## QuestLog also reads the stick raw, but see the note below — its defect is not observable here.
##
## ControlsMenu and LensMenu are the worse two: left/right there CYCLE A SETTING, so one nudge
## cycled the input profile five times and the lens holder three.
##
## 🔑 THE ARM DERIVES THE STEP SIZE RATHER THAN ASSERTING IT. A d-pad press moves each surface by
## whatever that surface's step is — 1 row here, 3 lines in QuestLog — and the stick must match it.
## Pinning "1" would have been a coincidental-value ratchet: correct for five surfaces and wrong
## for the sixth, and it would have gone red on a correct change to a step size.
##
## 🔑 THE SINGLE-PRESS DELTA IS ALSO THE LIVENESS CONTROL, and it is measured rather than
## ceremonial. My first probe of these fifteen surfaces reported "none moved" for ALL of them
## INCLUDING a known-good control — I had pushed UP from index 0, into the clamp. A zero delta
## cannot tell "the stick is fixed" from "the cursor had nowhere to go", so a non-zero press delta
## has to answer first.
##
## ⚠️ QuestLog IS CONVERTED ON THIS BRANCH BUT IS DELIBERATELY NOT LISTED HERE, because no arm I
## could write saw its defect. Headless it holds too few lines to scroll, and `_build_ui()`
## recomputes BOTH `_total_lines` and `_max_visible_lines` from the real quest data — so a
## fabricated line count survives exactly one step and the arm is identical on the converted and
## unconverted file. MEASURED, not assumed: reverting QuestLog leaves this file green. Its
## conversion rests on the migration ledger (structural) and on the same transform proven
## behaviourally on the four siblings below. An arm that cannot fail is worse than a named gap.

const RAMP := [0.55, 0.65, 0.75, 0.85, 0.95]

const SURFACES := [
	{"name": "SettingsMenu", "path": "res://src/ui/SettingsMenu.gd", "cursor": "selected_index",
		"setup": {}},
	{"name": "BossSelectorMenu", "path": "res://src/ui/BossSelectorMenu.gd", "cursor": "selected_index",
		"setup": {}},
	{"name": "ControlsMenu", "path": "res://src/ui/ControlsMenu.gd", "cursor": "selected_index",
		"setup": {}},
	{"name": "FormationsMenu", "path": "res://src/ui/FormationsMenu.gd", "cursor": "_selected",
		"setup": {}},
	{"name": "LensMenu", "path": "res://src/ui/LensMenu.gd", "cursor": "_selected",
		"setup": {}},
]


func after_each() -> void:
	_release()


func _motion(value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_Y
	e.axis_value = value
	return e


## Clear the engine action state AND MenuNav's static latch, which outlives any one surface.
func _release() -> void:
	Input.action_release("ui_down")
	Input.action_release("ui_up")
	MenuNav.step(_motion(0.0))


## ⛔ The handler is RESOLVED, not assumed. LensMenu defines `_unhandled_input`, not `_input`, and
## calling the wrong one aborts the whole test function — see the header.
func _handler(m: Node) -> String:
	for h in ["_input", "_unhandled_input", "_gui_input"]:
		if m.has_method(h):
			return h
	return ""


func _send(m: Node, ev: InputEvent) -> void:
	m.call(_handler(m), ev)


func _open(spec: Dictionary) -> Node:
	_release()
	var m: Node = load(spec["path"]).new()
	add_child_autofree(m)
	await get_tree().process_frame
	for k in spec["setup"]:
		m.set(k, spec["setup"][k])
	return m


func test_one_stick_push_moves_exactly_one_press_worth() -> void:
	var checked := 0
	for spec in SURFACES:
		# One d-pad press: establishes this surface's own step size AND that its handler is live.
		var m: Node = await _open(spec)
		assert_ne(_handler(m), "",
			"%s defines no input handler this arm can call — calling a nonexistent method ABORTS "
			% spec["name"] + "the test function, and every assert already run still reports green")
		var start: int = int(m.get(spec["cursor"]))
		var e := InputEventJoypadButton.new()
		e.button_index = JOY_BUTTON_DPAD_DOWN
		e.pressed = true
		Input.action_press("ui_down", 1.0)
		_send(m, e)
		Input.action_release("ui_down")
		var one_press: int = int(m.get(spec["cursor"])) - start
		assert_ne(one_press, 0,
			"LIVENESS: %s did not move on a single d-pad press — its handler early-returned or its "
			% spec["name"] + "cursor is against a clamp, and a still cursor below would not mean what it says")
		if one_press == 0:
			continue

		# One stick push, ramped. It must land in the same place the single press did.
		var m2: Node = await _open(spec)
		var start2: int = int(m2.get(spec["cursor"]))
		Input.action_press("ui_down", 1.0)
		for v in RAMP:
			_send(m2, _motion(v))
		Input.action_release("ui_down")
		var ramped: int = int(m2.get(spec["cursor"])) - start2
		assert_eq(ramped, one_press,
			"%s moved %d on one stick push but %d on one d-pad press — an axis carries no echo flag, "
			% [spec["name"], ramped, one_press] + "so every ramp step reads as a fresh press")
		checked += 1
	assert_eq(checked, SURFACES.size(),
		"every listed surface must reach the stick assertion; %d of %d did" % [checked, SURFACES.size()])


## The latch must not outlive the push: a second, separate push has to move the cursor again.
func test_a_second_push_still_moves_after_the_stick_returns_to_centre() -> void:
	for spec in SURFACES:
		var m: Node = await _open(spec)
		Input.action_press("ui_down", 1.0)
		for v in RAMP:
			_send(m, _motion(v))
		Input.action_release("ui_down")
		_send(m, _motion(0.0))
		var mid: int = int(m.get(spec["cursor"]))
		Input.action_press("ui_down", 1.0)
		for v in RAMP:
			_send(m, _motion(v))
		Input.action_release("ui_down")
		assert_ne(int(m.get(spec["cursor"])), mid,
			"%s ignored a SECOND stick push — the latch stranded and swallowed it, which is a "
			% spec["name"] + "worse bug than the one it was added to fix")
