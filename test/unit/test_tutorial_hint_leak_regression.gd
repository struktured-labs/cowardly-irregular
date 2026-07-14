extends GutTest

## Regression: TutorialHints.show() previously instanced + add_child'd a
## TutorialHint BEFORE checking _shown_hints / GameState. For any hint shown
## a second time the node was orphaned forever (show_hint short-circuited
## without setting _active, so hint_dismissed never fired and queue_free was
## never called).
##
## Two fixes layered for belt-and-suspenders:
##   1. TutorialHints.show() guards on _shown_hints BEFORE instancing.
##   2. TutorialHint.show_hint queue_free()s self on the early-return path.


func test_show_hint_queue_frees_on_already_shown_path() -> void:
	# Pre-mark the hint as shown.
	TutorialHint._shown_hints["leak_test_a"] = true
	var parent := Node.new()
	add_child_autofree(parent)
	var hint = TutorialHint.new()
	parent.add_child(hint)
	hint.show_hint("leak_test_a", "T", "B")
	# After the call, the node must be queued for deletion.
	assert_true(hint.is_queued_for_deletion(),
		"TutorialHint.show_hint must queue_free itself when the hint was already shown")


func test_tutorial_hints_show_does_not_add_child_when_already_shown() -> void:
	# Use a real catalog id so the warning path is skipped — we're testing the
	# _shown_hints guard, not the unknown-hint guard.
	var probe_id := "movement"
	TutorialHint._shown_hints[probe_id] = true
	var parent := Node.new()
	add_child_autofree(parent)
	var before_children := parent.get_child_count()
	TutorialHints.show(parent, probe_id)
	assert_eq(parent.get_child_count(), before_children,
		"TutorialHints.show must NOT add_child when the hint is already in _shown_hints")
