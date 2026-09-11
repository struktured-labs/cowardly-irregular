extends GutTest

## `ReadableProp.close_glyph()` read:
##
##     if InputProfileManager:
##         return InputProfileManager.glyph_for_action("ui_cancel", device_name)
##     return "B"
##
## ⛔ THAT `if` GUARDS THE AUTOLOAD, NOT A PAD. The autoload is always present in a shipped game, so
## the "B" fallback never fired — and `glyph_for_action` resolves the face family through
## `face_family_for_device("")`, which returns **"xbox"** for *no device*. Measured, no pad connected:
##
##     close_glyph()               ->  Ⓐ        what a KEYBOARD player was shown
##     ui_cancel keyboard bindings ->  X, Escape
##
## So the village notebook's footer read `[Ⓐ] Close` to someone holding no controller. The branch
## looked like a fallback and answered a different question than the one it appeared to answer.
##
## 🔑 WHAT THIS GUARD DEFENDS IS THE PAIR, not the spelling (@cowir-battle's framing): the defect is
## (unsafe helper) + (autoload-only guard). Either alone is fine — `hint_for_action` needs no pad
## branch because it falls back to the key itself, and an autoload check is harmless beside it. The
## file becomes defective again the moment someone swaps the helper, and the `if` will still be
## sitting there reading like protection. So the arm forbids the unsafe helpers in this file by name.
##
## ⚠️ SCOPE: this file only. The same pair exists across `src/ui/**` and is @cowir-controller's audit;
## a lane-wide ban belongs with that pass, not bolted on here.

const READABLE := "res://src/exploration/ReadableProp.gd"
## Returns the face family for an UNKNOWN pad, which is a real case — so it may not return "".
const UNSAFE := ["glyph_for_action", "face_glyph_for_index"]


## ⛔ CODE ONLY. The repair's own comment QUOTES `glyph_for_action` to explain what was wrong, so an
## unstripped scan reports the fix as the defect — it did, on this guard's first run. Strings are NOT
## stripped: a helper name here is always a call, never a caption.
func _code() -> String:
	var raw := FileAccess.get_file_as_string(READABLE)
	assert_gt(raw.length(), 500, "PRECONDITION: ReadableProp must be readable")
	var out := ""
	for line in raw.split("\n"):
		var l := str(line)
		var at := l.find("#")
		out += (l.substr(0, at) if at >= 0 else l) + "\n"
	return out


## THE RENDERED STRING. Not "does it call the right helper" — what a player with no pad actually sees.
func test_the_close_hint_names_something_a_keyboard_player_can_press() -> void:
	var RP = load(READABLE)
	assert_true(Input.get_connected_joypads().is_empty(),
		"PRECONDITION: this arm measures the NO-PAD case; a pad is connected, so it proves nothing")
	var glyph: String = RP.close_glyph()
	assert_gt(glyph.length(), 0, "the close hint must not be empty — the footer renders '[%s] Close'" % glyph)
	# The face glyphs are exactly what a keyboard player cannot press.
	for face in ["Ⓐ", "Ⓑ", "Ⓧ", "Ⓨ", "○", "✕", "□", "△"]:
		assert_false(glyph.contains(face),
			"with NO pad connected the close hint rendered '%s', which contains the face glyph %s — " % [glyph, face] +
			"a player holding no controller cannot press it")
	assert_eq(glyph, InputProfileManager.hint_for_action("ui_cancel"),
		"the hint must be whatever hint_for_action resolves, not a frozen or separately-derived value")


## THE PAIR. The `if InputProfileManager:` is harmless beside a safe helper and load-bearing-looking
## beside an unsafe one. Forbid the unsafe half so the combination cannot re-form.
func test_this_file_does_not_pair_an_autoload_check_with_an_unsafe_helper() -> void:
	var src := _code()
	var guards_autoload := src.contains("if InputProfileManager:")
	for helper in UNSAFE:
		assert_false(src.contains(helper),
			("%s resolves the face family through face_family_for_device(\"\"), which answers " % helper) +
			"\"xbox\" for NO DEVICE — so it hands a keyboard player a glyph. This file has an " +
			"autoload check (%s) that reads like a pad branch and is not one; the two together are " % str(guards_autoload) +
			"the defect. Use hint_for_action or button_name_for_index.")
	assert_true(src.contains("hint_for_action"),
		"close_glyph must derive through hint_for_action, which falls back to the KEY with no pad")


## CONTROL: the unsafe-helper scan must be able to report a name PRESENT, or the arm above is free.
func test_the_helper_scan_discriminates() -> void:
	var src := _code()
	assert_true(src.contains("InputProfileManager"),
		"CONTROL present: the scan can see the autoload's name in this file")
	assert_false(src.contains("face_glyph_for_index"),
		"CONTROL absent: a helper this file does not call must scan as absent")
	# THE STRIPPER, both directions: it must eat the comment that names the forbidden helper, and
	# must NOT eat the code that names the safe one. Over-stripping would make the arm above vacuous.
	var raw := FileAccess.get_file_as_string(READABLE)
	assert_true(raw.contains("glyph_for_action"),
		"CONTROL: the raw file DOES contain the forbidden name — in the comment explaining the fix")
	assert_false(src.contains("glyph_for_action"),
		"CONTROL: ...and the stripper removed it, which is the only reason the arm above can pass")
	assert_true(src.contains("hint_for_action"),
		"CONTROL: the stripper did not eat the real call")
	# And the live predicate both ways, so neither direction is assumed.
	assert_true("if InputProfileManager:\n\t\treturn InputProfileManager.glyph_for_action(".contains(UNSAFE[0]),
		"CONTROL: the forbidden spelling is detectable in the exact shape that shipped")
