extends GutTest

## ⛔ THE "MAP THIS PAD" WALK HAD NO EXIT A PAD COULD REACH, AND NO DEADLINE EITHER. `_input` routes
## every event to `_handle_mapping_input` while a walk is live and consumes it; that handler binds
## every InputEventJoypadButton and acts on exactly two KEYBOARD keys. So a pad-only player who
## started the walk could only finish all 22 controls -- and the row's own hint says "THIS PAD IS
## UNMAPPED", so the population most likely to be in there is exactly the one it stranded.
##
## 🔑 WHY A CLOCK AND NOT A GESTURE, which is the design half: every pad button is a BINDING here,
## so a reserved button or a long press would have to steal one from the mapping being captured. A
## deadline claims nothing and cannot collide. `_process` already had this arm for the sibling
## single-action capture (`_capture_timer`) and none for the walk.
##
## 🔑 AND IT MEASURES TIME SINCE THE LAST ADVANCE, NOT SINCE THE LAST INPUT. That is the load-bearing
## distinction: a player whose presses are all REFUSED -- a duplicate token, or a pad with no
## control the prompt accepts -- is pressing buttons continuously, and an input-keyed timer would
## never fire for them. They are the flailing player the exit exists for.
##
## 📌 NO WALL-CLOCK WAIT ANYWHERE BELOW: `_process(delta)` is driven with synthetic deltas, so the
## arms are deterministic and cost nothing under a long run.

const CONTROLS_MENU := "res://src/ui/ControlsMenu.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


## Built WITHOUT entering the tree on purpose: `_ready` constructs the whole settings panel, and
## the walk needs only its own overlay. Nothing here auto-ticks, so every tick below is explicit.
func _menu() -> Node:
	var m = load(CONTROLS_MENU).new()
	autofree(m)
	m._build_mapping_overlay()
	return m


func _walk(m: Node) -> void:
	m._mapping = ControllerMappingCapture.new("guid", "Test Pad", "Linux")
	m._mapping_idle = 0.0
	m._refresh_mapping_prompt()


func _press(m: Node, button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = true
	m._handle_mapping_input(ev)


func _consts() -> Dictionary:
	var c: Dictionary = load(CONTROLS_MENU).get_script_constant_map()
	assert_true(c.has("MAPPING_IDLE_LIMIT"),
		"the deadline must be a named const -- a literal in _process cannot be read by the hint")
	assert_true(c.has("MAPPING_IDLE_WARN_AT"),
		"the warning threshold must be a named const too")
	return c


## ⛔ THE FILE-LEVEL FLOOR, DERIVED FROM THIS FILE'S OWN SOURCE rather than hand-listed. Every arm
## below reaches members on a dynamically-typed receiver, so a rename aborts the enclosing arm and
## -- once any assert has already run in it -- the file scores PASSING with the subject never
## driven. A hand-list selects from my own map of what the file reaches; deriving cannot go stale,
## and it caught two names I would not have written down.
func test_the_menu_exposes_every_member_this_file_drives() -> void:
	var src: String = GdSource.code_of("res://test/unit/test_a_stalled_pad_walk_releases_itself.gd")
	assert_true(src.find("_mapping_idle") > -1,
		"POSITIVE CONTROL: this file's own source must survive stripping, or the derivation below " +
		"runs on an empty window and passes having checked nothing")
	var names: Dictionary = {}
	var rx := RegEx.create_from_string("\\bm\\.([A-Za-z_][A-Za-z0-9_]*)")
	for hit in rx.search_all(src):
		names[hit.get_string(1)] = true
	assert_gt(names.size(), 5,
		"CONTROL: the derivation must find the members this file drives, not a handful")
	var m: Node = _menu()
	var missing: Array = []
	for n in names:
		if m.has_method(str(n)):
			continue
		if str(n) in m:
			continue
		missing.append(str(n))
	assert_eq(missing, [],
		"every member this file reaches must exist on the menu -- a missing one aborts its arm " +
		"and the file can still score green. Derived set: %s" % [names.keys()])


## CONTROL FIRST, then the defect: the walk must be live before the clock, live just under the
## deadline, and released past it. The middle assert is what stops a "release immediately" bug
## from passing this arm.
func test_a_stalled_walk_releases_itself() -> void:
	var limit: float = _consts()["MAPPING_IDLE_LIMIT"]
	var m: Node = _menu()
	_walk(m)
	assert_not_null(m._mapping, "CONTROL: a walk must be live before the clock runs")
	m._process(limit - 1.0)
	assert_not_null(m._mapping,
		"a walk one second short of the deadline must STILL be live -- a player reading a prompt " +
		"is not a stalled player")
	m._process(2.0)
	assert_null(m._mapping,
		"past the deadline the walk must release itself: this is the only exit a pad-only player " +
		"can reach, because every pad button is consumed as a binding")


## ⛔ THE ARM THAT MAKES IT A NO-PROGRESS DEADLINE RATHER THAN A WALL CLOCK. Without it, a fixed
## deadline would pass the arm above and evict a player in the middle of a legitimate 22-control
## walk -- a worse bug than the one being fixed.
func test_progress_resets_the_deadline() -> void:
	var limit: float = _consts()["MAPPING_IDLE_LIMIT"]
	var m: Node = _menu()
	_walk(m)
	m._process(limit - 1.0)
	assert_almost_eq(m._mapping_idle, limit - 1.0, 0.001,
		"CONTROL: the clock must have actually advanced, or the reset below proves nothing")
	_press(m, JOY_BUTTON_A)
	assert_almost_eq(m._mapping_idle, 0.0, 0.001,
		"an ACCEPTED binding is progress and must reset the clock")
	m._process(limit - 1.0)
	assert_not_null(m._mapping,
		"a player who bound a control a moment ago must not be evicted -- the deadline measures " +
		"time since the last ADVANCE, not since the walk began")


## ⛔ THE LOAD-BEARING HALF. A refused press looks like input and is not progress. Keyed to input,
## the deadline would never fire for the one player who cannot get out: pressing buttons, every
## one rejected, with no keyboard.
func test_a_refused_press_does_not_reset_the_deadline() -> void:
	var limit: float = _consts()["MAPPING_IDLE_LIMIT"]
	var m: Node = _menu()
	_walk(m)
	_press(m, JOY_BUTTON_A)
	var bound: int = (m._mapping.bindings as Dictionary).size()
	assert_eq(bound, 1, "CONTROL: the first press must have been ACCEPTED, giving us a duplicate to reuse")
	m._process(limit - 1.0)
	_press(m, JOY_BUTTON_A)
	assert_eq((m._mapping.bindings as Dictionary).size(), bound,
		"CONTROL: the second press of the same button must be REFUSED -- one input cannot serve " +
		"two SDL controls, so nothing new is bound")
	assert_almost_eq(m._mapping_idle, limit - 1.0, 0.001,
		"a REFUSED press must NOT reset the clock -- a player mashing rejected buttons is the " +
		"population this exit exists for, and resetting here would strand them forever")
	m._process(2.0)
	assert_null(m._mapping, "so the flailing player still gets out at the deadline")


## No time pressure on the normal path: the countdown is silent until the walk is actually
## stalling, then it names the way out instead of only counting down.
func test_the_warning_is_silent_until_the_tail() -> void:
	var c: Dictionary = _consts()
	var limit: float = c["MAPPING_IDLE_LIMIT"]
	var warn: float = c["MAPPING_IDLE_WARN_AT"]
	assert_gt(limit, warn, "CONTROL: the warning tail must fit inside the deadline")
	var m: Node = _menu()
	_walk(m)
	m._process(limit - warn - 1.0)
	assert_eq(m._mapping_idle_label.text, "",
		"CONTROL: outside the tail the warning must be EMPTY -- a countdown shown from the start " +
		"runs a calm remap walk against a visible clock")
	m._process(2.0)
	assert_ne(m._mapping_idle_label.text, "",
		"inside the tail the warning must appear")
	assert_true(m._mapping_idle_label.text.to_lower().contains("prompt"),
		"and it must say how to CARRY ON, not only that time is running out: '%s'" % m._mapping_idle_label.text)


## The walk's own label is separate from `_mapping_status` DELIBERATELY: that line carries the
## duplicate-input refusal, and a countdown written to it would erase the explanation a refused
## player just earned.
func test_the_countdown_does_not_erase_the_refusal_message() -> void:
	var limit: float = _consts()["MAPPING_IDLE_LIMIT"]
	var m: Node = _menu()
	_walk(m)
	_press(m, JOY_BUTTON_A)
	_press(m, JOY_BUTTON_A)
	var refusal: String = m._mapping_status.text
	assert_true(refusal.to_lower().contains("already"),
		"CONTROL: the second press must have produced the duplicate refusal: '%s'" % refusal)
	m._process(limit - 1.0)
	assert_eq(m._mapping_status.text, refusal,
		"the countdown must not clobber the refusal -- it has its own label for exactly this reason")
	assert_ne(m._mapping_idle_label.text, "", "while the countdown itself is visible")


## The row hint warned BEFORE the player committed that the walk could only be finished. That was
## true and is now false, so the hint had to change with the code.
func test_the_row_hint_no_longer_says_a_walk_can_only_be_finished() -> void:
	var src: String = GdSource.code_of(CONTROLS_MENU)
	var at: int = src.find("func _map_pad_hint")
	assert_gt(at, -1, "the row hint builder must exist")
	## BOTH boundaries: a window that runs to end-of-file would scan the whole rest of the script
	## and every claim below would be about the file rather than about this function.
	var nxt: int = src.find("\nfunc ", at + 10)
	assert_gt(nxt, at, "the hint builder must be followed by another function, bounding the window")
	var body: String = src.substr(at, nxt - at)
	assert_false(body.contains("needs a keyboard to skip/cancel"),
		"the old hint said a keyboard was needed to get out at all; a stall now releases the walk")
	assert_true(body.contains("MAPPING_IDLE_LIMIT"),
		"the hint must DERIVE the number from the const the deadline uses, not restate it")
	assert_true(body.to_lower().contains("keyboard"),
		"it must still say a keyboard is what SKIPS one control -- that part did not change")


## The deadline is armed where the walk starts, not only where it ticks: a second walk begun after
## an expiry must not inherit the expired clock and die on its first frame.
func test_a_second_walk_starts_with_a_fresh_clock() -> void:
	var limit: float = _consts()["MAPPING_IDLE_LIMIT"]
	var m: Node = _menu()
	_walk(m)
	m._process(limit + 1.0)
	assert_null(m._mapping, "CONTROL: the first walk must have expired")
	assert_almost_eq(m._mapping_idle, 0.0, 0.001,
		"releasing a walk must clear the clock, or the next walk inherits an expired one")
	assert_eq(m._mapping_idle_label.text, "",
		"and the stale countdown must not survive on screen after the overlay is reused")
