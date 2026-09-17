extends GutTest

## A player who taps confirm through a line had no way back to it. The box holds one line;
## pagination (28d85bf3) holds one line's PAGES; nothing held the conversation. Both halves of
## today's text-loss work were about text the player never got to read — this is the half about
## text they read too fast.
##
## ui_up is free in this box (the body does not scroll — that is why pagination exists) and the
## affordance is DERIVED through hint_for_action, never a printed letter.

## ⛔ HERMETIC ABOUT THE PROFILE. Arms here derive a token or glyph from the LIVE InputMap, so this
## file inherits whatever `user://input/controls.json` holds. A remap test writes a "Custom" profile
## there; an interrupted run skips its cleanup, and every later run in that sandbox reads it.
##
## Measured 2026-09-17 across all 22 test files that ask InputProfileManager for a name or glyph:
## one stale profile (shoulders bound to FACE buttons) exposed 3 files; a DIFFERENT one (face
## buttons swapped) exposed 3 OTHERS, with zero overlap. So "not exposed" is a fact about the
## artifact you happen to carry, not about the file — which is why the whole corpus is pinned
## rather than the three that reddened.
var _saved_profile: String = ""


func before_all() -> void:
	_saved_profile = InputProfileManager.active_profile
	InputProfileManager.apply_profile("Standard")


func after_all() -> void:
	if _saved_profile != "":
		InputProfileManager.apply_profile(_saved_profile)


const DialogueScript = preload("res://src/cutscene/CutsceneDialogue.gd")

var _box: Node


func before_each() -> void:
	Input.action_release("ui_accept")
	_box = DialogueScript.new()
	add_child_autofree(_box)


func after_each() -> void:
	Input.action_release("ui_accept")


func _line(speaker: String, text: String) -> Dictionary:
	return {"speaker": speaker, "text": text, "theme": "fighter", "portrait": "fighter"}


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	_box._input(e)


func test_every_line_shown_lands_in_the_backlog() -> void:
	_box.show_dialogue([
		_line("Fighter", "Does it smell like dragon in there?"),
		_line("Cleric", "It smells like something that used to be a dragon."),
		_line("Fighter", "Those are different smells?"),
	])
	assert_eq(_box.backlog_size(), 1, "the first line is in the backlog as soon as it is shown")
	_box._finish_typing()
	_box._advance_dialogue()
	_box._finish_typing()
	_box._advance_dialogue()
	assert_eq(_box.backlog_size(), 3, "every line shown is kept, newest last")
	assert_eq(str(_box._backlog[0]["speaker"]), "Fighter", "with its speaker")
	assert_string_contains(str(_box._backlog[2]["text"]), "different smells",
		"and the newest line is the last entry")


## A conversation longer than the buffer keeps the RECENT lines — the old ones are the ones you no
## longer need, and an unbounded log on a 200-line scene is a leak.
func test_the_backlog_keeps_the_newest_and_drops_the_oldest() -> void:
	for i in 20:
		_box._record_in_backlog("Speaker%d" % i, "line %d" % i)
	assert_eq(_box.backlog_size(), _box.BACKLOG_MAX, "the buffer is capped at BACKLOG_MAX")
	assert_eq(str(_box._backlog[_box.backlog_size() - 1]["text"]), "line 19", "the newest line survives")
	assert_false("line 0" in str(_box._backlog[0]["text"]), "and the oldest is the one dropped")


## A PAGED line is one thing the player read, not one entry per page.
func test_a_paged_line_is_one_entry_with_its_whole_text() -> void:
	var words: PackedStringArray = PackedStringArray()
	for i in 160:
		words.append("consequence%d" % i)
	var long_text := " ".join(words)
	_box.show_dialogue([_line("Milo", long_text)])
	assert_gt(_box._pages.size(), 1, "PRECONDITION: the line must page, else this proves nothing")
	assert_eq(_box.backlog_size(), 1, "a paged line is ONE backlog entry")
	assert_eq(str(_box._backlog[0]["text"]), long_text, "carrying the whole line, not the first page")
	_box._finish_typing()
	_box._advance_dialogue()
	assert_eq(_box.backlog_size(), 1, "and turning its pages must not add another")


func test_the_backlog_opens_and_closes_on_input() -> void:
	_box.show_dialogue([_line("Fighter", "One."), _line("Cleric", "Two.")])
	_box._finish_typing()
	_box._advance_dialogue()
	assert_eq(_box.backlog_size(), 2, "PRECONDITION: two lines shown")
	_press("ui_up")
	assert_true(_box.is_backlog_open(), "ui_up must open the log")
	_press("ui_cancel")
	assert_false(_box.is_backlog_open(), "and cancel must close it")


## MODAL. A press that would advance or skip the scene must act on the panel, not on the scene the
## player cannot currently see. ui_cancel is the worst case: it SKIPS the whole queue.
func test_an_open_backlog_swallows_advance_and_skip() -> void:
	_box.show_dialogue([_line("Fighter", "One."), _line("Cleric", "Two."), _line("Bard", "Three.")])
	_box._finish_typing()
	_box._advance_dialogue()
	var index_before: int = _box._current_index
	_press("ui_up")
	assert_true(_box.is_backlog_open())
	_press("ui_accept")
	assert_eq(_box._current_index, index_before, "confirm must not advance the line under the panel")
	assert_false(_box.is_backlog_open(), "it closes the panel instead")
	_press("ui_up")
	_press("ui_cancel")
	assert_true(_box.visible, "and cancel must not skip the conversation from inside the log")


## The typewriter must not keep running under a panel the player is reading.
func test_typing_pauses_under_the_panel_and_resumes_after() -> void:
	_box.show_dialogue([_line("Fighter", "A line long enough that the typewriter is still working on it.")])
	_box._record_in_backlog("Cleric", "an earlier line so the log has something to show")
	assert_true(_box._is_typing, "PRECONDITION: the line must still be typing")
	assert_false(_box._typing_timer.is_stopped(), "PRECONDITION: its timer must be running")
	_box.open_backlog()
	assert_true(_box._typing_timer.is_stopped(), "the typewriter stops while the log is up")
	_box.close_backlog()
	assert_false(_box._typing_timer.is_stopped(), "and resumes when it closes")


## The affordance is advertised, derived, and only once there is something behind the current line.
func test_the_hint_advertises_the_log_only_when_there_is_one() -> void:
	_box.show_dialogue([_line("Fighter", "Only line.")])
	_box._finish_typing()
	var first: String = _box._advance_hint.text
	assert_false("Log" in first, "one line is not a log: %s" % first)
	_box.show_dialogue([_line("Fighter", "One."), _line("Cleric", "Two.")])
	_box._finish_typing()
	_box._advance_dialogue()
	_box._finish_typing()
	var second: String = _box._advance_hint.text
	assert_true("Log" in second, "from the second line on, the hint must offer it: %s" % second)
	var glyph: String = InputProfileManager.hint_for_action("ui_up")
	assert_true(glyph in second, "and it must name the DERIVED glyph (%s), not a printed letter" % glyph)


## CONTROL: with nothing behind the current line, ui_up must not open an empty panel.
func test_a_single_line_has_no_log_to_open() -> void:
	_box.show_dialogue([_line("Fighter", "Only line.")])
	assert_eq(_box.backlog_size(), 1)
	_press("ui_up")
	assert_false(_box.is_backlog_open(), "one line is not worth a panel")


## The log belongs to the conversation: the next one starts empty, and the panel cannot outlive it.
func test_the_log_ends_with_its_conversation() -> void:
	_box.show_dialogue([_line("Fighter", "One."), _line("Cleric", "Two.")])
	_box._finish_typing()
	_box._advance_dialogue()
	_box.open_backlog()
	assert_true(_box.is_backlog_open())
	_box._finish_dialogue()
	assert_false(_box.is_backlog_open(), "the panel must not outlive the box that owns it")
	assert_eq(_box.backlog_size(), 0, "and the next conversation starts empty")
