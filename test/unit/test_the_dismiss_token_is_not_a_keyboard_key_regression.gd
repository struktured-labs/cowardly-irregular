extends GutTest

## ⛔ THE DISMISS TOKEN WAS A KEYBOARD KEY, ON A PAD, BETWEEN TWO DERIVED GLYPHS.
##
## RebalanceReviewPanel's footer read:
##     "↑/↓ Cycle    %s Apply    [S] Dismiss    %s Close"
##                    ^derived     ^FROZEN        ^derived
##
## Apply and Close resolve through `hint_for_action`. Dismiss was the literal `[S]` — a keyboard
## key — for a control the handler fires on `JOY_BUTTON_Y`, the NORTH face. So a pad player was
## told to press a key their controller does not have, for the one dismiss route that works on it.
##
## 🔑 NO LETTER WOULD HAVE WORKED. Measured, index 3 per family:
##     Xbox Ⓨ   ·   Switch Ⓧ   ·   PlayStation △
## A Switch player needed Ⓧ and the legend said S. That two correctly-derived tokens sat either
## side of it is what makes this an oversight rather than a decision.
##
## The safe helper is `button_name_for_index`, which returns "" with no pad — it refuses to name
## a button nobody has, and the caller names the KEY instead. Dismiss is a raw button read, not a
## bound action, so `hint_for_action` is not available to it.

const PANEL := "res://src/ui/RebalanceReviewPanel.gd"
const XBOX := "Xbox Wireless Controller"
const SWITCH := "Nintendo Switch Pro Controller"
const PS := "PS5 Controller"


func _ipm():
	return InputProfileManager


## ⛔ THE DEFECT. The token a pad player is shown must be that pad's north face.
func test_the_dismiss_token_is_derived_per_family() -> void:
	var want := {XBOX: "Ⓨ", SWITCH: "Ⓧ", PS: "△"}
	for device in want:
		var tok: String = _ipm().button_name_for_index(JOY_BUTTON_Y, device)
		assert_eq(tok, want[device],
			"%s must be told %s for Dismiss — the legend said the keyboard key 'S' to every pad" % [
				device, want[device]])


## ⛔ AND NO FROZEN LETTER CAN SERVE THEM ALL — the reason a literal was never a shortcut here.
func test_the_three_families_disagree_about_the_north_face() -> void:
	var seen := {}
	for device in [XBOX, SWITCH, PS]:
		seen[_ipm().button_name_for_index(JOY_BUTTON_Y, device)] = device
	assert_eq(seen.size(), 3,
		"all three families must print a DIFFERENT north face, or this defect would have been " +
		"cosmetic rather than wrong on two pads out of three")


## THE OTHER DIRECTION. With no pad the legend must name the KEY, not a glyph nobody can press.
func test_with_no_pad_the_legend_names_the_key() -> void:
	assert_true(Input.get_connected_joypads().is_empty(),
		"precondition: GUT runs with no pad, which is the keyboard case")
	assert_eq(_ipm().button_name_for_index(JOY_BUTTON_Y), "",
		"the helper must REFUSE to name a button with no pad — naming one is the defect this " +
		"lane removed from five surfaces in .308-.338")
	var panel = load(PANEL).new()
	add_child_autofree(panel)
	var legend: String = panel._legend_text()
	assert_true(legend.find("S Dismiss") > -1,
		"…so the caller must fall back to the keyboard key, got: %s" % legend)


## The legend must carry all three controls, and Dismiss must not be a literal any more.
func test_the_legend_derives_every_token_it_shows() -> void:
	var panel = load(PANEL).new()
	add_child_autofree(panel)
	var legend: String = panel._legend_text()
	for word in ["Apply", "Dismiss", "Close"]:
		assert_true(legend.find(word) > -1, "the legend must still advertise %s, got: %s" % [word, legend])
	assert_eq(legend.find("[S]"), -1,
		"the bracketed literal must be gone — it is the frozen caption this file kept")


## ⛔ THE CLAIM AND THE HANDLER MUST AGREE. The legend names the north face; the handler must
## actually fire on it. A derived token pointing at a button nothing reads is the same defect
## with better spelling.
func test_the_handler_really_fires_on_the_button_the_legend_names() -> void:
	var panel = load(PANEL).new()
	add_child_autofree(panel)
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_Y
	ev.pressed = true
	assert_true(panel._is_dismiss_event(ev),
		"the NORTH face must dismiss — that is what the legend now promises every pad player")
	var wrong := InputEventJoypadButton.new()
	wrong.button_index = JOY_BUTTON_A
	wrong.pressed = true
	assert_false(panel._is_dismiss_event(wrong),
		"CONTROL: a different face must NOT dismiss, or the arm above passes on any press")


## The keyboard route the no-pad legend promises must also work.
func test_the_key_the_legend_names_actually_dismisses() -> void:
	var panel = load(PANEL).new()
	add_child_autofree(panel)
	var ev := InputEventKey.new()
	ev.keycode = KEY_S
	ev.pressed = true
	assert_true(panel._is_dismiss_event(ev), "S must dismiss — the no-pad legend names it")
	var x := InputEventKey.new()
	x.keycode = KEY_X
	x.pressed = true
	assert_false(panel._is_dismiss_event(x),
		"X must NOT dismiss: ui_cancel binds it and closes the whole panel, which is why that arm " +
		"was removed in .311 — the header docstring promised it until 2026-09-12")
