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


## The ordinary path: the log opens, and the rest of the same push must not reach the modal branch
## behind it and scroll the text the player just asked to read.
func test_one_nudge_opens_the_log_without_scrolling_it() -> void:
	_two_lines()
	Input.action_press("ui_up")
	for v in RAMP:
		_box._input(_motion(v))

	assert_true(_box.is_backlog_open(), "the push opens the log")
	# Pre-fix, values 2..4 fell through to the modal branch and each scrolled -40.
	if _box._backlog_scroll != null and is_instance_valid(_box._backlog_scroll):
		assert_eq(_box._backlog_scroll.scroll_vertical, 0,
			"and does not also scroll it — a headless log is shorter than its window, so any " +
			"movement here is the ramp leaking into the modal branch")


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
