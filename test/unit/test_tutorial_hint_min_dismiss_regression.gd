extends GutTest

## Regression: playtest 2026-07-15 (intercom 2555) — spotlight_unlock hint
## was too easy to dismiss mid-battle before the player could read "X is now
## unlocked". Fix: per-hint `min_dismiss` seconds in the HINTS catalog that
## blocks dismiss input for that window and shows a countdown.
##
## Contract pinned here:
##   1. spotlight_unlock has min_dismiss = 2.0 in the catalog (the reported
##      case).
##   2. show_hint sets _min_dismiss_timer from the passed value.
##   3. While _min_dismiss_timer > 0: dismiss inputs are consumed but do NOT
##      dismiss. Dismiss label reads "▶ [in Ns]".
##   4. After the window elapses, dismiss inputs work again and the label
##      reverts to the standard "Press any button to dismiss" prompt.
##   5. Hints with no min_dismiss field (default 0.0) dismiss on first input
##      as before — backward compatible.


func before_each() -> void:
	# Session dedupe is a static var — clear our test ids each run.
	TutorialHint._shown_hints.erase("min_dismiss_probe_gated")
	TutorialHint._shown_hints.erase("min_dismiss_probe_open")
	TutorialHint._shown_hints.erase("spotlight_unlock")
	if GameState:
		GameState.game_constants.erase("tutorial_min_dismiss_probe_gated")
		GameState.game_constants.erase("tutorial_min_dismiss_probe_open")
		GameState.game_constants.erase("tutorial_spotlight_unlock")


func _new_hint() -> TutorialHint:
	var parent := Node.new()
	add_child_autofree(parent)
	var hint := TutorialHint.new()
	parent.add_child(hint)
	return hint


func _fake_key_press() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_Z
	e.pressed = true
	return e


func test_spotlight_unlock_catalog_entry_has_min_dismiss() -> void:
	# The reported bug is specifically about the spotlight-victory unlock
	# screen — pin its catalog entry so a refactor can't silently drop the
	# gate.
	var entry: Dictionary = TutorialHints.HINTS.get("spotlight_unlock", {})
	assert_true(entry.has("min_dismiss"),
		"spotlight_unlock must have a min_dismiss field — otherwise mid-battle button-mashers skip the load-bearing unlock message (msg 2555)")
	var val: float = float(entry.get("min_dismiss", 0.0))
	assert_gte(val, 1.0,
		"spotlight_unlock min_dismiss must be at least 1.0s to be readable (2s was requested)")


func test_show_hint_applies_min_dismiss() -> void:
	var hint := _new_hint()
	hint.show_hint("min_dismiss_probe_gated", "T", "B", 2.0)
	assert_true(hint._active, "hint should be active after show")
	assert_almost_eq(hint._min_dismiss_timer, 2.0, 0.001,
		"_min_dismiss_timer must equal the passed value at show time")
	assert_true(String(hint._dismiss_label.text).contains("in"),
		"dismiss label should show a countdown while min-dismiss is active")


func test_dismiss_blocked_during_min_dismiss_window() -> void:
	var hint := _new_hint()
	hint.show_hint("min_dismiss_probe_gated", "T", "B", 2.0)
	hint._input(_fake_key_press())
	assert_true(hint._active,
		"key press during min-dismiss window MUST NOT dismiss the hint")
	assert_true(hint.visible,
		"hint stays visible during min-dismiss window")


func test_dismiss_works_after_min_dismiss_window_elapses() -> void:
	var hint := _new_hint()
	hint.show_hint("min_dismiss_probe_gated", "T", "B", 2.0)
	# Simulate 2.5s of process — timer should hit 0 and label revert.
	hint._process(2.5)
	assert_almost_eq(hint._min_dismiss_timer, 0.0, 0.001,
		"_min_dismiss_timer must clamp to 0 after the window elapses")
	assert_eq(String(hint._dismiss_label.text), TutorialHint.READY_DISMISS_TEXT,
		"dismiss label reverts to the standard prompt once window elapses")
	hint._input(_fake_key_press())
	assert_false(hint._active,
		"key press AFTER the min-dismiss window MUST dismiss the hint")


func test_no_min_dismiss_field_is_zero_and_dismisses_immediately() -> void:
	# Backwards compatibility — hints without the field must behave exactly
	# as before (dismiss on first input).
	var hint := _new_hint()
	hint.show_hint("min_dismiss_probe_open", "T", "B")  # no min_dismiss arg → 0.0
	assert_almost_eq(hint._min_dismiss_timer, 0.0, 0.001)
	assert_eq(String(hint._dismiss_label.text), TutorialHint.READY_DISMISS_TEXT,
		"no min-dismiss = standard prompt shown immediately")
	hint._input(_fake_key_press())
	assert_false(hint._active,
		"backwards-compatible: no min_dismiss = dismiss on first press")


func test_tutorial_hints_show_passes_catalog_min_dismiss_through() -> void:
	# End-to-end catalog wiring: TutorialHints.show(spotlight_unlock) must
	# propagate the catalog's min_dismiss into the TutorialHint instance.
	var parent := Node.new()
	add_child_autofree(parent)
	TutorialHints.show(parent, "spotlight_unlock")
	var hint: TutorialHint = null
	for c in parent.get_children():
		if c is TutorialHint:
			hint = c
			break
	assert_not_null(hint, "TutorialHints.show must add a TutorialHint child")
	if hint == null:
		return
	assert_gt(hint._min_dismiss_timer, 0.0,
		"spotlight_unlock catalog entry's min_dismiss must reach the instance via TutorialHints.show")
