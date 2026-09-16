extends GutTest

## The on-screen keyboard is how you name an autobattle script or an autogrind rule set on a pad.
## Its grid is 10 columns wide, so crossing a row was NINE presses, and nothing repeated.
##
## ⛔ AND ITS BACKSPACE CLAIMED TO REPEAT AND NEVER DID. The branch carried the comment
## "allow echo for backspace-like behavior" and omitted the `not event.is_echo()` guard its four
## neighbours have — which achieves nothing, because `is_action_pressed` defaults allow_echo=false,
## so an echo already reads as not-pressed. Measured, not reasoned:
##     echo event, is_action_pressed("ui_cancel")        -> false
##     echo event, is_action_pressed("ui_cancel", true)  -> true
##     fresh press, is_action_pressed("ui_cancel")       -> true
## So holding never deleted a second character on a keyboard either, and a pad emits no echo at
## all. The comment told the next reader the feature was there.

const VirtualKeyboardScript = preload("res://src/ui/VirtualKeyboard.gd")

const PAST_DELAY := 0.5


func _make_keyboard(text: String = "") -> Control:
	var kb = VirtualKeyboardScript.new()
	add_child_autofree(kb)
	kb.setup("Name", text, 16)
	kb.visible = true
	return kb


func after_each() -> void:
	for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_cancel"]:
		Input.action_release(a)


func test_holding_right_walks_the_row() -> void:
	var kb := _make_keyboard()
	kb.cursor_col = 0
	Input.action_press("ui_right")
	kb._process(PAST_DELAY)
	assert_eq(kb.cursor_col, 0, "the frame a direction goes down must not repeat")
	kb._process(PAST_DELAY)
	assert_eq(kb.cursor_col, 1, "holding past the delay walks the row on its own")
	kb._process(PAST_DELAY)
	assert_eq(kb.cursor_col, 2, "…and keeps walking while held")


func test_holding_down_walks_the_column() -> void:
	var kb := _make_keyboard()
	kb.cursor_row = 0
	Input.action_press("ui_down")
	kb._process(PAST_DELAY)
	kb._process(PAST_DELAY)
	assert_eq(kb.cursor_row, 1, "a held vertical walks too — this is a grid, not a list")


## ⛔ THE DEFECT. Holding backspace deleted exactly one character, on every input device, while a
## comment in the file said it repeated.
func test_holding_backspace_deletes_more_than_one_character() -> void:
	var kb := _make_keyboard("ABCDEF")
	assert_eq(kb.input_text, "ABCDEF", "precondition: the field starts full")
	Input.action_press("ui_cancel")
	kb._process(PAST_DELAY)
	assert_eq(kb.input_text, "ABCDEF", "the frame the button goes down is the press path's")
	kb._process(PAST_DELAY)
	assert_eq(kb.input_text, "ABCDE", "a held cancel deletes")
	kb._process(PAST_DELAY)
	kb._process(PAST_DELAY)
	assert_eq(kb.input_text, "ABC", "…and keeps deleting, which is what the comment promised")


## ⛔ THE HALF THAT MAKES THE ABOVE SAFE. The press path cancels the whole dialog when the field is
## already empty. A hold must never reach that: holding backspace to clear a name would close the
## keyboard the instant the last character went.
func test_a_held_backspace_never_cancels_the_dialog() -> void:
	var kb := _make_keyboard("AB")
	watch_signals(kb)
	Input.action_press("ui_cancel")
	for i in range(8):
		kb._process(PAST_DELAY)
	assert_eq(kb.input_text, "", "the hold empties the field")
	assert_signal_not_emitted(kb, "cancelled",
		"a hold must only ever DELETE — reaching the cancel branch would close the keyboard")


## The load-bearing guard: MenuRepeat polls Input, so it inherits none of _input's refusals.
func test_a_hidden_keyboard_does_not_move_under_a_held_direction() -> void:
	var kb := _make_keyboard("AB")
	kb.cursor_col = 3
	kb.visible = false
	Input.action_press("ui_right")
	Input.action_press("ui_cancel")
	for i in range(6):
		kb._process(PAST_DELAY)
	assert_eq(kb.cursor_col, 3, "a hidden keyboard must not walk its grid")
	assert_eq(kb.input_text, "AB", "…nor delete the text behind it")


func test_releasing_drops_the_ramp() -> void:
	var kb := _make_keyboard()
	kb.cursor_col = 0
	Input.action_press("ui_right")
	kb._process(PAST_DELAY)
	kb._process(PAST_DELAY)
	assert_eq(kb.cursor_col, 1, "precondition: the hold fired once")
	Input.action_release("ui_right")
	kb._process(PAST_DELAY)
	Input.action_press("ui_right")
	kb._process(PAST_DELAY)
	assert_eq(kb.cursor_col, 1, "a fresh hold serves its delay again rather than inheriting the ramp")


## ECHO CANNOT DRIVE ANY OF THIS, which is why the repeat had to be polled rather than the missing
## guard restored. Pinned as a measurement so the old comment cannot come back as a "fix".
func test_an_echo_event_does_not_read_as_a_press() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_X
	ev.pressed = true
	ev.echo = true
	assert_false(ev.is_action_pressed("ui_cancel"),
		"an echo reads as NOT pressed by default — omitting a `not is_echo()` guard grants nothing")
	assert_true(ev.is_action_pressed("ui_cancel", true),
		"…it takes the explicit allow_echo argument, which no branch in this file passes")


## One owner per behaviour, shared by the press path and the hold.
func test_the_press_path_and_the_hold_share_one_owner() -> void:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/ui/VirtualKeyboard.gd")
	assert_ne(code, "", "VirtualKeyboard must be readable as source")
	assert_eq(code.count("func _nav_step("), 1, "exactly one definition of the cursor step")
	assert_eq(code.count("func _backspace_step("), 1, "exactly one definition of the delete")
	assert_eq(code.count("_nav_step(") - 1, 5, "four press branches and the hold route through it")
	assert_eq(code.find("allow echo for backspace-like behavior"), -1,
		"the comment promising a repeat that never happened must not survive the repeat being real")
