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
	#
	# Enumerated by CAPABILITY — every file that RENDERS a controls row — not by the one
	# file that originally had the bug. When the reference moved into HowToPlayOverlay so
	# it could be opened in-game, checking only TitleScreen would have left the new home
	# unguarded while still reporting green.
	var renderers: Array[String] = [
		"res://src/ui/TitleScreen.gd",
		"res://src/ui/HowToPlayOverlay.gd",
	]
	for path in renderers:
		var src: String = FileAccess.get_file_as_string(path)
		assert_ne(src, "", "renderer must be readable: %s" % path)
		assert_false(src.contains("A Button          Z / Enter"),
			"the hardcoded confirm row is back in %s — it lies on any pad whose east face is not A" % path)


func test_the_renderer_list_names_a_file_that_actually_renders_a_row() -> void:
	# Control for the loop above: if a path 404s or the row moves again, the guard must go
	# red rather than sweep an empty corpus. Names a known-present member, not a count.
	var overlay: String = FileAccess.get_file_as_string("res://src/ui/HowToPlayOverlay.gd")
	assert_true(overlay.contains("Defer / Party Chat"),
		"HowToPlayOverlay must actually carry the controls table this guard is defending")
