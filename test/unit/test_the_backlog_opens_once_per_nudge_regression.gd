extends GutTest

## CONSEQUENCE arm for the CutsceneDialogue conversion. @cowir-controller's property/consequence
## split, applied to my own change: the ledger and MenuNav's own arms own the PROPERTY (this file
## no longer reads ui_up raw); nothing owned the OUTCOME the player sees.
##
## ⛔ THE DEFECT. ui_up sat behind `not event.is_echo()`, which an AXIS does not set — so every value
## of a stick ramp was taken. In the thinking branch that meant toggle_backlog() five times; in the
## modal branch it opened the log and then scrolled it. These are not cursor steps, so no clamp or
## wrap masked them the way every paging menu masked the page_delta defect.
##
## 🔑 WHY AN EVEN-LENGTH RAMP. The final state after an ODD number of toggles is open either way, so
## "the log is open" does not discriminate and an arm asserting it would pass against the old code —
## @cowir-controller's world-map arm and @cowir-sfx's group-attack report, one more time. FOUR
## bursting events toggle to CLOSED pre-fix and to OPEN post-fix, which needs no layout pass and no
## scroll geometry to read.

const DialogueScript = preload("res://src/cutscene/CutsceneDialogue.gd")

## Four values past the 0.5 deadzone — EVEN on purpose, see above. NEGATIVE because ui_up binds
## axis 1 at axis_value -1.0 (ui_down is the positive half); a positive ramp reads as ui_down and
## the burst floor below catches that rather than every arm passing against a single press.
const RAMP := [-0.6, -0.8, -0.95, -1.0]

var _box: Node


func before_each() -> void:
	_release()
	_box = DialogueScript.new()
	add_child_autofree(_box)


func after_each() -> void:
	_release()
	if _box and is_instance_valid(_box) and _box.is_backlog_open():
		_box.close_backlog()


func _release() -> void:
	for a in ["ui_up", "ui_down", "ui_accept", "ui_cancel"]:
		Input.action_release(a)
	# Clear MenuNav's axis latch through its public path so one arm cannot strand it for the next.
	MenuNav.step(_motion(0.0))


func _motion(v: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_LEFT_Y
	ev.axis_value = v
	return ev


func _line(speaker: String, text: String) -> Dictionary:
	return {"speaker": speaker, "text": text, "theme": "fighter", "portrait": "fighter"}


## Two lines so the backlog has something behind the current one — open_backlog refuses an empty log.
func _two_lines() -> void:
	_box.show_dialogue([
		_line("Fighter", "Does it smell like dragon in there?"),
		_line("Cleric", "It smells like something that used to be a dragon."),
	])
	_box._finish_typing()
	_box._advance_dialogue()


## ⛔ A DERIVED FLOOR, not one `has_method` per call site. @cowir-autogrind's form: it names every
## member this file reaches, read out of this file's OWN source, so it cannot fall out of date with
## the reaches the way a hand-written list does. That matters because the rung of any single reach
## is decided by whether an assert already ran in ITS arm — so adding a precondition line above a
## reach silently converts it from rung 1 (Risky, EC=4, loud) to rung 3 (Passing, EC=0, silent).
## This floor is indifferent to that: it reds on a rename whatever the order.
##
## ⚠️ THE DERIVATION IS NOT QUOTE-AWARE, and that is a declared limit rather than an oversight.
## @cowir-sfx's scanner invented a receiver out of a fixture STRING shaped like a call, so an
## assert message here containing `_box.something` would add a phantom member. **It fails LOUD** —
## a phantom does not exist on the subject, so this arm reds and names it — which is the safe
## direction and why a quote-aware pass is not worth its complexity in a file with no such fixture.
## If this ever reds on a name that is only ever inside a string, that is the cause.
##
## 📌 THE FLOOR COVERS THE RECEIVER ITS DERIVATION NAMES, and this file drives three
## (@cowir-music's clause — "is this file floored?" can answer YES about a narrower set than the
## name suggests). Checked per receiver rather than per file, measured:
##     _box      27 reaches   THIS FLOOR
##     MenuNav    1 reach     NO FLOOR WARRANTED — a `class_name` static resolves at PARSE TIME, so
##                            a missing member is not an abort at all: the script never compiles and
##                            run_tests.sh exits 3, NOTHING RAN. Measured: renaming step() gave
##                            EC=3. @cowir-controller's discriminator is the CALL SHAPE, not the
##                            symbol — a floor here could only ever be dead code
##     Input      6 reaches   engine builtin; a rename is not a change this repo can make
## So no second floor is warranted here, and that is a measurement rather than an assumption.
func test_every_member_this_file_reaches_still_exists() -> void:
	var src: String = FileAccess.get_file_as_string(
		"res://test/unit/test_the_backlog_opens_once_per_nudge_regression.gd")
	assert_gt(src.length(), 3000, "control: this file must be readable, got %d chars" % src.length())

	var reached: Dictionary = {}
	for raw in src.split("\n"):
		var line: String = str(raw).strip_edges()
		if line.begins_with("#"):
			continue
		var at := line.find("_box.")
		while at >= 0:
			var start := at + 5
			var end := start
			while end < line.length() and (line[end] == "_" or line[end].is_valid_identifier()):
				end += 1
			var name := line.substr(start, end - start)
			if name != "" and name != "has_method":
				reached[name] = true
			at = line.find("_box.", end)
	assert_gt(reached.size(), 8,
		"ANTI-VACUITY: the scan must find this file's own reaches, found %d" % reached.size())

	var missing: Array = []
	for m in reached:
		if not (_box.has_method(m) or m in _box):
			missing.append(m)
	assert_eq(missing, [],
		"CutsceneDialogue no longer exposes members this file drives, so the arms touching them " +
		"abort — and an abort after a passing assert scores GREEN. Renamed or removed: %s" % [missing])


## ANTI-VACUITY: if the synthetic ramp does not read as a burst, every arm below is asserting
## against a single press and would pass on the unconverted code too.
func test_the_ramp_really_reads_as_a_burst() -> void:
	var pressed := 0
	for v in RAMP:
		if _motion(v).is_action_pressed("ui_up"):
			pressed += 1
	assert_gt(pressed, 1, "the fixture must reproduce the burst — %d of %d ramp values read as pressed"
		% [pressed, RAMP.size()])
	assert_eq(pressed % 2, 0, "and an EVEN count, or the toggle arm cannot tell one toggle from four")


func test_the_fixture_reaches_the_input_handler_at_all() -> void:
	# CONTROL: _input returns immediately unless the box is visible, which would make every arm
	# below a statement about a hidden node.
	_two_lines()
	assert_true(_box.visible, "the box must be visible or _input returns before reading anything")
	assert_gt(_box.backlog_size(), 1, "and the log must have something behind the current line")
	## ⛔ THE HANDLER IS ASSERTED BEFORE IT IS CALLED, not assumed. @cowir-controller hit this on
	## LensMenu, which defines _unhandled_input: calling a method that does not exist ABORTS the
	## test function, so the arms below would stop mid-loop with their earlier asserts already
	## passed and nothing on screen wrong. A rename is the realistic way this happens.
	assert_true(_box.has_method("_input"),
		"CutsceneDialogue must still route through _input — if it moved to _unhandled_input, every " +
		"arm here aborts at the first call and scores green on the asserts it reached")


## ⛔ THE DEFECT, thinking branch: four bursting events used to toggle FOUR TIMES and land closed.
func test_one_nudge_toggles_the_log_once_while_the_llm_thinks() -> void:
	_two_lines()
	_box.set_thinking(true)
	assert_true(_box._thinking_label != null and _box._thinking_label.visible,
		"control: the thinking branch must actually be armed, or this tests the ordinary path")

	Input.action_press("ui_up")
	for v in RAMP:
		_box._input(_motion(v))

	assert_true(_box.is_backlog_open(),
		"one stick push must toggle the log ONCE — four toggles land closed, which is what a ramp did")


## ⛔ SECOND ROUTE — the MODAL branch, where the log is already open and ui_up/ui_down scroll it.
## @cowir-autogrind's rule that a consequence arm is scoped to a ROUTE and not to a feature: the
## toggle arm above covers the thinking branch and says nothing about this one.
##
## ⚠️ MY FIRST VERSION OF THIS ARM WAS NON-DISCRIMINATING AND I BLAMED THE WRONG THING. It stayed
## green under the mutation, and I removed it declaring that headless has no scroll geometry.
## PROBED INSTEAD OF ASSERTED: geometry is real — 30 backlog entries give max_value 494 against a
## page of 368, a scrollable range of 126. The arm was blind because MY FIXTURE had two lines and
## therefore no range, not because the engine cannot show one. The declaration was comfortable and
## false, which is worse than the arm it justified removing.
func test_one_nudge_scrolls_the_open_log_once() -> void:
	_two_lines()
	for i in 30:
		_box._record_in_backlog("Speaker%d" % i, "a backlog line, number %d, long enough to wrap" % i)
	_box.open_backlog()
	await _frames(6)
	assert_true(_box.is_backlog_open(), "precondition: the log is open")

	## ⛔ THE ONLY RUNG-3 REACH IN THIS FILE, so the only silent one. Two asserts have already run by
	## here, so a rename of _backlog_scroll aborts this arm to Passing/EC=0 — `.366`'s EC=4 derives
	## from [Risky] names and cannot see an abort after a passing assert (@cowir-sfx's triage axis:
	## pre-assert reaches are rung 1 and already loud; post-assert ones are the hole). `in` is the
	## non-aborting existence test — assert_not_null would abort on the read it is checking.
	assert_true("_backlog_scroll" in _box,
		"CutsceneDialogue must still expose _backlog_scroll — renamed, this arm aborts AFTER its " +
		"asserts and scores green with the scroll never measured")
	var start: int = _box._backlog_scroll.scroll_vertical
	assert_gt(start, 100,
		"ANTI-VACUITY: open_backlog scrolls to the end, so there must be range to scroll BACK " +
		"through — read %d, and at 0 this arm cannot tell one scroll from four" % start)

	Input.action_press("ui_up")
	for v in RAMP:
		_box._input(_motion(v))
	await _frames(2)

	assert_eq(_box._backlog_scroll.scroll_vertical, start - 40,
		"one push scrolls the log ONE step — four steps is -160 against a range of ~126, which " +
		"clamps to 0 and throws the reader to the top of the log")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## A SECOND genuine push must still work: the latch is released by state, not by the event.
func test_a_second_push_still_closes_the_log() -> void:
	_two_lines()
	_box.set_thinking(true)
	Input.action_press("ui_up")
	for v in RAMP:
		_box._input(_motion(v))
	assert_true(_box.is_backlog_open(), "precondition: the first push opened it")

	Input.action_release("ui_up")
	_box._input(_motion(0.0))
	Input.action_press("ui_up")
	for v in RAMP:
		_box._input(_motion(v))
	assert_false(_box.is_backlog_open(),
		"after a genuine release the next push toggles again — a stranded latch would eat it")
