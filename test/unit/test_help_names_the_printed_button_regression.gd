extends GutTest

## The title screen's HOW TO PLAY table is the one surface a lost player opens, and it used to
## hardcode "A Button — Confirm / Select".
##
## Confirm is bound to the EAST face (SNES layout). East is printed A on a Nintendo pad and B on
## an Xbox pad — so on the pad a Windows demo player is holding, the help screen named the button
## that CANCELS. Shipped, reachable, and wrong: nothing crashed and the text rendered fine.
##
## Pins the VALUE per pad family, not that the function runs.

const TitleScreenScript = preload("res://src/ui/TitleScreen.gd")

var _ipm: Node


func before_each() -> void:
	_ipm = load("res://src/input/InputProfileManager.gd").new()
	add_child_autofree(_ipm)


func _rows_for(device_name: String) -> String:
	return TitleScreenScript.build_confirm_cancel_rows(
		_ipm.glyph_for_action("ui_accept", device_name),
		_ipm.glyph_for_action("ui_cancel", device_name))


func test_xbox_pad_is_told_to_press_the_button_printed_B() -> void:
	var rows := _rows_for("Xbox Series X Controller")
	assert_string_contains(rows, "Ⓑ Button", "east face is printed B on an Xbox pad")
	assert_true(rows.find("Ⓑ Button") < rows.find("Ⓐ Button"),
		"Confirm row comes first, so the Ⓑ must precede the Ⓐ — the regression was these swapped")


func test_nintendo_pad_is_told_to_press_the_button_printed_A() -> void:
	var rows := _rows_for("Nintendo Switch Pro Controller")
	assert_string_contains(rows, "Ⓐ Button", "east face is printed A on a Switch Pro")
	assert_true(rows.find("Ⓐ Button") < rows.find("Ⓑ Button"),
		"Confirm row first: Ⓐ confirms on a Nintendo pad")


func test_playstation_pad_gets_shapes_not_letters() -> void:
	var rows := _rows_for("Sony DualSense Wireless Controller")
	assert_string_contains(rows, "○ Button", "east face is Circle on a DualSense")
	assert_string_contains(rows, "✕ Button", "south face is Cross")


func test_the_two_pads_disagree_which_is_the_whole_point() -> void:
	# If these ever match, the table has gone back to naming a fixed letter and the guard
	# is worthless — this is the assertion that actually fails on a regression.
	assert_ne(_rows_for("Xbox Series X Controller"), _rows_for("Nintendo Switch Pro Controller"),
		"the same physical button must be NAMED differently per pad family")


func test_no_hardcoded_letter_survives_in_the_source() -> void:
	# Belt and braces: the literal that caused this must not come back. A source pin is weak
	# alone, which is why the value assertions above carry the guard.
	var src := FileAccess.get_file_as_string("res://src/ui/TitleScreen.gd")
	assert_false(src.contains("A Button          Z / Enter"),
		"the hardcoded confirm row is back — it lies on any pad whose east face is not A")
