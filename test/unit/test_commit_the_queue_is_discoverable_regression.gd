extends GutTest

## struktured 2026-09-10: "if you OVER advanced and just want to commit your choices, there should
## be one button to do that on joystick — otherwise you have to cancel and like reselect, its
## awkward." Then, working it out mid-conversation: "oh I know… you hold defer down, that's the
## trick — and it confirms your choices and cancels any outstanding advances."
##
## THE BUTTON ALREADY EXISTED. He had found it before and it is written down nowhere, which is why
## he could not remember it and why it reads as missing.
##
## MEASURED — the two paths differ in exactly the way that matters to his complaint:
##   A (ui_accept) -> _submit_actions()        queue + THE HIGHLIGHTED ITEM   (adds one more)
##   HOLD L        -> _confirm_turn_with_queue() queue EXACTLY as it stands   (adds nothing)
## The queued hint advertised the first as "[A] Confirm" and never mentioned the second — so
## reaching for the advertised control takes the extra action he was trying not to take.

const W98 := "res://src/ui/Win98Menu.gd"


## The commit-as-is path must exist and submit ONLY what is queued.
## BEHAVIOURAL since 2026-09-14. This pinned the literal `actions_submitted.emit(root._queued_actions
## .duplicate())`. The Advance/5-action work order needs the queue cleared and queue_changed(0) sent
## BEFORE that signal (it dispatches turn end, and the next PC's menu can exist before control
## returns), so the text had to change while the property did not. Driving the menu asserts the
## property itself: exactly the queue, and not the highlighted item.
func test_hold_l_commits_the_queue_without_adding_anything() -> void:
	var m = load(W98).new()
	m.is_root_menu = true
	m.battle_mode = true
	add_child_autofree(m)
	m.setup("Command", [
		{"id": "attack", "label": "Attack"},
		{"id": "guard", "label": "Guard"},
	], Vector2(10, 10), "fighter")
	m._can_accept_input = true
	m.set_max_queue_size(4)
	m.selected_index = 0
	for i in range(2):
		Win98Menu._last_advance_ms = -1000000
		m._handle_advance_input()
	assert_eq(m.get_queue_count(), 2, "CONTROL: two actions must be queued before the hold")
	m.selected_index = 1  # a DIFFERENT item highlighted — the one A would add
	var got: Array = []
	m.actions_submitted.connect(func(a): got.append(a))
	m._confirm_turn_with_queue()
	assert_eq(got.size(), 1, "the commit-as-is path must submit")
	if got.size() != 1:
		return
	assert_eq(got[0].size(), 2, "it must submit the queue as it stands — two, not three")
	for a in got[0]:
		assert_ne(a.id, "guard",
			"and must NOT append the highlighted item — that is the difference from A, and his whole ask")


## CONTROL: the OTHER path must genuinely add the highlighted item, or the arm above distinguishes
## nothing and this file is about a difference that does not exist.
func test_the_a_path_really_does_add_the_highlighted_item() -> void:
	var src := FileAccess.get_file_as_string(W98)
	var at := src.find("func _submit_actions")
	var body := src.substr(at, src.find("\nfunc ", at + 10) - at)
	assert_true(body.contains("all_actions.append("),
		"CONTROL: A appends the current selection — if it stopped, the two paths would be the same")


## The gesture must be REACHABLE: a hold threshold that no human press can clear, or one so short
## every press clears it, is not a control.
func test_the_hold_threshold_is_humanly_distinguishable() -> void:
	var src := FileAccess.get_file_as_string(W98)
	var re := RegEx.new()
	re.compile("L_HOLD_CONFIRM_TIME[^=]*=\\s*([0-9.]+)")
	var m := re.search(src)
	assert_not_null(m, "the hold threshold must be declared")
	var t := float(m.get_string(1))
	assert_gt(t, 0.05, "below ~50ms an ordinary tap commits when the player meant undo")
	assert_lt(t, 1.0, "above a second nobody discovers it by accident either")


## AND IT MUST BE ADVERTISED. This is the whole defect: the feature worked and was invisible.
func test_the_queued_hint_names_both_paths_truthfully() -> void:
	var src := FileAccess.get_file_as_string(W98)
	var at := src.find("func _update_hint_bar")
	var body := src.substr(at, src.find("\nfunc ", at + 10) - at)
	assert_true(body.contains("HOLD L"),
		"the queued hint must name the commit-as-is gesture — he had to rediscover it in conversation")
	assert_true(body.contains("Add+Commit"),
		"and must not call the add-one-more path plain 'Confirm', which is what made A the wrong reach")
	assert_true(body.contains("Undo"), "undo must still be advertised")
