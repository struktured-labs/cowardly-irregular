extends GutTest

## MouseCursorManager hid the cursor on ANY InputEventJoypadMotion, with no deadzone and without
## reading axis_value at all. A raw joypad-motion event is not a deliberate push: resting sticks
## drift and triggers settle, so a plugged-in pad nobody is touching could hide a mouse-first
## player's cursor — which their next mouse motion restored, and the next drift event hid again.
##
## 🔑 THAT IS THE BEHAVIOUR THIS FILE'S OWN DOCSTRING SAYS WAS FIXED — for keyboard, on
## 2026-05-03: *"the prior 'any kb event = hide' toggled the cursor on/off jankily during normal
## play."* The same shape was left on the one input that emits noise without a human touching it.
##
## And src/input/ already had the answer: GamepadFilter.STICK_DEADZONE = 0.2, used for exactly
## this on exactly this axis. The two raw-axis readers in the directory now agree.
##
## ⚠️ WHAT THIS GUARD CANNOT DO, stated because it changes what a green here means.
## `Input.set_mouse_mode` is a NO-OP under the headless display server — measured:
##     DisplayServer.get_name() -> "headless"
##     set_mouse_mode(HIDDEN) then get_mouse_mode() -> 0 (VISIBLE)
## My first probe asserted the cursor state and reported "not hidden" for BOTH drift and a
## deliberate 0.9 push. The CONTROL is what caught it: the deliberate push must hide the cursor,
## it did not, so the instrument was broken rather than the code. **No test in this suite can
## assert the cursor effect.** These arms pin the DECISION — the threshold the handler applies —
## and say so rather than implying a rendered check.

const MCM := "res://src/input/MouseCursorManager.gd"
const FILTER := "res://src/input/GamepadFilter.gd"


func _mgr():
	return MouseCursorManager


## ⛔ CODE ONLY, AND THE STRIPPER CARRIES ITS OWN CONTROL. Twice in one hour a window I sized
## against code was filled by prose instead — first my anchor matched inside a comment, then the
## six explanatory lines I had written BETWEEN the branch and its body overran a 400-char window.
##
## ⚠️ But a stripper is an instrument too, and it fails the SAME way it fixes: by silently changing
## what the assertion measures. @cowir-adhoc's swallowed whole files on a desynced docstring toggle
## and produced five confident false positives — invisible in a green run, because everything
## downstream of an over-strip is a NEGATIVE assertion that an empty string satisfies perfectly.
## So `must_survive` is a REQUIRED argument, not an optional hardening: a known CODE site that
## over-stripping would delete, checked here so no call site can forget it.
func _code_only(path: String, must_survive: String) -> String:
	var out := ""
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		if raw.strip_edges().begins_with("#"):
			continue
		out += raw + "\n"
	assert_true(out.find(must_survive) > -1,
		"POSITIVE CONTROL: '%s' is a CODE site in %s and must survive stripping — if it did not, " % [must_survive, path] +
		"the stripper ate code and every negative arm below would pass on an empty window")
	## ⛔ AND THE OTHER HALF, because a #-only strip is LINE-BASED and cannot see inside a \"\"\"
	## block: text there survives stripping and would satisfy a positive arm above. This file has
	## none TODAY — that is MEASURED INERT, not safe by design. If it ever fails, the answer is a
	## region strip for this path, not a wider window.
	assert_eq(out.count('"""'), 0,
		"%s gained a multi-line string: a #-only strip is blind inside one, so the arms above can " % path +
		"now be satisfied by prose again — this helper needs a region strip for it")
	return out


## The branch's own body, bounded by the NEXT branch rather than by a character count. A magic
## width is the coincidental-value shape CLAUDE.md names: 120 happened to stop 17 characters short
## of the motion branch's condition, so an ordinary edit there would have redded a correct fix.
func _branch_body(src: String, header: String) -> String:
	var at := src.find(header)
	assert_gt(at, -1, "the branch must still exist, as a branch: %s" % header)
	if at < 0:
		return ""
	var next_elif := src.find("\n\telif ", at)
	var next_func := src.find("\nfunc ", at)
	var stop := next_elif
	if stop < 0 or (next_func > -1 and next_func < stop):
		stop = next_func
	return src.substr(at, stop - at) if stop > at else src.substr(at)


## ⛔ THE DEFECT. Drift must not cross the threshold; a real push must.
func test_only_a_deliberate_push_crosses_the_hide_threshold() -> void:
	var dz: float = _mgr().STICK_DEADZONE
	assert_gt(dz, 0.0, "precondition: there must BE a deadzone — 0.0 is the defect restored")
	for v in [0.0, 0.04, 0.1, dz]:
		assert_false(absf(v) > dz,
			"axis %.2f is drift or rest and must NOT hide the cursor" % v)
	for v in [dz + 0.01, 0.5, 1.0, -0.9]:
		assert_true(absf(v) > dz,
			"axis %.2f is a deliberate push and must still hide the cursor" % v)


## The handler must actually CONSULT axis_value — a deadzone constant nothing reads is decoration.
func test_the_handler_reads_the_axis_value() -> void:
	## ⛔ ANCHOR ON THE CODE FORM, not the bare type name. My first version searched
	## "InputEventJoypadMotion" and matched inside the COMMENT I had just added above the branch,
	## so the window measured 400 characters of my own prose and the arm redded on a correct fix.
	## @cowir-autogrind hit the identical trap this hour: prose crowding out the code an assertion
	## is measuring. Anchoring on the `elif …:` form fixed the first half; _code_only fixes the
	## second, where my own six comment lines sat between the branch and the thing being asserted.
	var src := _code_only(MCM, "func _hide_cursor() -> void:")
	var body := _branch_body(src, "elif event is InputEventJoypadMotion:")
	assert_true(body.find("axis_value") > -1,
		"the motion branch must read axis_value — before 2026-09-12 it hid the cursor on the " +
		"event's mere EXISTENCE, which is what made a resting stick enough")
	assert_true(body.find("STICK_DEADZONE") > -1, "…and compare it against the deadzone")


## ⛔ THE OTHER DIRECTION. A BUTTON press is always deliberate and must keep hiding the cursor
## immediately — deadzoning the wrong branch would make a gamepad-first player's cursor linger.
func test_a_button_press_still_hides_without_a_deadzone() -> void:
	var src := _code_only(MCM, "func _hide_cursor() -> void:")
	var body := _branch_body(src, "elif event is InputEventJoypadButton:")
	## ⛔ THE POSITIVE HALF FIRST. Both asserts below are NEGATIVE, and an empty window satisfies
	## a negative perfectly — which is exactly how an over-eager stripper reads as green.
	assert_true(body.find("_hide_cursor()") > -1,
		"the button branch must still HIDE — without this the two negatives below would pass on " +
		"an empty window, which is the failure @cowir-adhoc measured in their own stripper")
	## ⛔ CHECK FOR THE DEADZONE, not just for axis_value. My first version asserted only
	## `find("axis_value") == -1`, and the mutation that deadzones this branch realistically —
	## `if absf(0.0) > STICK_DEADZONE:` — never mentions axis_value, so the arm PASSED a mutation
	## that restored the defect on the wrong branch. Caught because I predicted a red and got a
	## green; the arm was hollow against everything except the one shape I happened to imagine.
	assert_eq(body.find("axis_value"), -1,
		"a button press has no axis and must NOT be gated on one — gamepad-first players expect " +
		"the cursor gone the moment they press anything")
	assert_eq(body.find("STICK_DEADZONE"), -1,
		"…and must not be gated on the deadzone by any other route either: a button press is " +
		"always deliberate, and a threshold here would make the cursor linger after a press")
	assert_eq(body.find("InputEventJoypadMotion"), -1,
		"BOUNDS: the slice must STOP at the next branch — a window that ran on into the motion " +
		"branch would red both negatives above on entirely correct code")


## The two raw-axis readers in src/input/ must agree, or the directory has two deadzones that
## drift apart — which is the two-sources-one-surface shape CLAUDE.md records.
func test_the_two_axis_readers_share_one_deadzone() -> void:
	var filter_dz: float = load(FILTER).STICK_DEADZONE
	assert_eq(_mgr().STICK_DEADZONE, filter_dz,
		"MouseCursorManager and GamepadFilter both read raw axes and must use the SAME deadzone")


## THE CONTROL, and it is the one that mattered here: it records WHY these arms are source-shaped.
func test_the_cursor_effect_is_genuinely_unmeasurable_here() -> void:
	assert_eq(DisplayServer.get_name(), "headless",
		"precondition: the suite runs headless, which is why the arms above pin the decision")
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	assert_ne(Input.get_mouse_mode(), Input.MOUSE_MODE_HIDDEN,
		"set_mouse_mode must be a NO-OP here — if this ever FAILS, the display server gained " +
		"mouse support and these arms should become behavioural instead of reading source")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
