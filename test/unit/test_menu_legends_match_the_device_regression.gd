extends GutTest

## Three on-screen legends were hardcoded "[A] Confirm  [B] Cancel" — wrong TWICE:
##
##   1. A keyboard player has no A or B button. The real keys are Z and X.
##   2. This game puts Confirm on the EAST face (the SNES layout), so on a pad
##      glyph_for_action("ui_accept") is Ⓑ and ui_cancel is Ⓐ. The legends had them INVERTED for
##      every Xbox and PlayStation player — correct only on a Nintendo-layout pad.
##
## Same defect the battle hint bar carried ("[X] Speed", family-specific, shown with no pad), fixed
## the same way: derive from InputProfileManager.hint_for_action(), which returns the live family's
## glyph when a pad is present and the keyboard key when it is not.
##
## ⚠️ SCOPE: the three legends that use FACE buttons only. MenuScene's "[Select] Toggle autobattle"
## is NOT converted — Select is button 4, outside FACE_GLYPHS, so glyph_for_action returns "?" and
## the helper would silently print the keyboard key to a pad player. That needs a button-name table,
## which is a different change; it is named here so the gap is recorded rather than implied closed.

const CONVERTED := [
	"res://src/ui/ItemsMenu.gd",
	"res://src/ui/LensMenu.gd",
	"res://src/ui/RadialPicker.gd",
]


## PRECONDITION + the reason the fix is needed at all: the accessor must disagree with the old
## hardcoded letters. If Confirm were on the south face this whole file would be moot.
func test_confirm_is_on_the_east_face_so_the_old_letters_were_inverted() -> void:
	var accept_glyph: String = InputProfileManager.glyph_for_action("ui_accept")
	var cancel_glyph: String = InputProfileManager.glyph_for_action("ui_cancel")
	assert_ne(accept_glyph, cancel_glyph, "PRECONDITION: the two must differ, or nothing is inverted")
	assert_eq(accept_glyph, str(InputProfileManager.FACE_GLYPHS["xbox"][1]),
		"on an Xbox-family pad Confirm is the EAST face — which is Ⓑ, not the Ⓐ the legends said")
	assert_eq(cancel_glyph, str(InputProfileManager.FACE_GLYPHS["xbox"][0]),
		"and Cancel is the SOUTH face, Ⓐ — the exact inversion the hardcoded legends shipped")


## The helper must actually vary by device, or converting the legends achieved nothing.
func test_the_helper_answers_for_the_live_device() -> void:
	var accept: String = InputProfileManager.hint_for_action("ui_accept")
	assert_ne(accept, "", "the helper must return something for a bound action")
	if Input.get_connected_joypads().is_empty():
		assert_eq(accept, "Z",
			"with NO pad the legend must name the KEYBOARD key — Z, not a face-button letter")
		assert_eq(InputProfileManager.hint_for_action("ui_cancel"), "X", "and Cancel is X")
	else:
		assert_eq(accept, InputProfileManager.glyph_for_action("ui_accept"),
			"with a pad it must be the live family's glyph")
	assert_eq(InputProfileManager.hint_for_action("zzq_not_an_action"), "",
		"CONTROL: an unbound action returns empty so callers keep their own wording")


## THE RATCHET. None of the converted legends may go back to a hardcoded face letter.
func test_the_converted_legends_are_derived() -> void:
	var offenders: Array[String] = []
	for path in CONVERTED:
		var src := FileAccess.get_file_as_string(path)
		assert_gt(src.length(), 100, "corpus file must be readable: %s" % path)
		if not src.contains("hint_for_action"):
			offenders.append("%s does not derive its legend" % path.get_file())
		if src.contains("[A] Confirm") or src.contains("[A] Craft") or src.contains("[B] Back") \
				or src.contains("[B] Cancel"):
			offenders.append("%s still hardcodes a face letter" % path.get_file())
	assert_eq(offenders, [] as Array[String],
		"a legend hardcodes A/B again — that is inverted for Xbox and PlayStation players and " +
		"meaningless on a keyboard: %s" % [", ".join(offenders)])
