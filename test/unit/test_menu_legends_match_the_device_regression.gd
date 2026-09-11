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
## ⚠️ SCOPE, UPDATED 2026-09-11: that gap is now CLOSED. BUTTON_NAMES gives the five non-face
## indices the profiles bind a per-family printed name (Minus/Back/Share · Plus/Start/Options ·
## L/LB/L1 · R/RB/R1), so hint_for_action names the button instead of dropping to a keyboard key a
## pad player cannot press. MenuScene's Select legend is converted. Still NOT covered: legends
## elsewhere in the game that were never surveyed — this file pins four files, not every legend.

const CONVERTED := [
	"res://src/ui/ItemsMenu.gd",
	"res://src/ui/LensMenu.gd",
	"res://src/ui/RadialPicker.gd",
	"res://src/ui/MenuScene.gd",
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

## NON-FACE BUTTONS MUST BE NAMED, NOT SILENTLY DOWNGRADED. Select/Start/L3/shoulders have no entry
## in FACE_GLYPHS, so before BUTTON_NAMES the helper fell through to the keyboard key — printing
## "Tab" to someone holding a pad. Each family names them differently, which is the whole point.
func test_non_face_buttons_are_named_per_family() -> void:
	var nin: String = InputProfileManager.button_name_for_action("battle_toggle_auto", "Nintendo Switch Pro Controller")
	var xb: String = InputProfileManager.button_name_for_action("battle_toggle_auto", "Xbox Wireless Controller")
	var ps: String = InputProfileManager.button_name_for_action("battle_toggle_auto", "DualSense Wireless Controller")
	assert_eq(nin, "Minus", "Nintendo calls button 4 Minus")
	assert_eq(xb, "Back", "Xbox calls it Back")
	assert_eq(ps, "Share", "PlayStation calls it Share")
	assert_ne(nin, xb, "CONTROL: the accessor must vary by family, not return one constant")
	assert_eq(InputProfileManager.button_name_for_action("ui_accept"), "",
		"a FACE button must return empty here — it has a glyph and should use it")
	assert_eq(InputProfileManager.button_name_for_action("zzq_not_an_action"), "",
		"CONTROL: an unbound action returns empty")


## The shoulders differ too, and they are the bindings struktured actually reported confusion about.
func test_the_shoulders_are_named_per_family() -> void:
	assert_eq(InputProfileManager.button_name_for_action("battle_defer", "Nintendo Switch Pro Controller"), "L")
	assert_eq(InputProfileManager.button_name_for_action("battle_defer", "Xbox Wireless Controller"), "LB")
	assert_eq(InputProfileManager.button_name_for_action("battle_defer", "DualSense Wireless Controller"), "L1")
	assert_eq(InputProfileManager.button_name_for_action("battle_advance", "DualSense Wireless Controller"), "R1")

## THE INTEGRATION, and it exists because a mutation proved the gap. Deleting the non-face lookup
## from hint_for_action left this whole file GREEN: the box has no pad, so that branch never ran and
## every arm was testing the accessor in isolation. The device_name seam makes the pad path
## reachable headless.
func test_hint_for_action_uses_the_name_table_on_a_pad() -> void:
	assert_eq(InputProfileManager.hint_for_action("battle_toggle_auto", "Xbox Wireless Controller"), "Back",
		"with an Xbox pad the Select legend must say Back, not a keyboard key")
	assert_eq(InputProfileManager.hint_for_action("battle_toggle_auto", "DualSense Wireless Controller"), "Share",
		"and Share on PlayStation")
	assert_eq(InputProfileManager.hint_for_action("battle_defer", "DualSense Wireless Controller"), "L1",
		"the shoulders route through the same lookup")
	# FACE buttons must still take the glyph path, not the name table.
	assert_eq(InputProfileManager.hint_for_action("ui_accept", "Xbox Wireless Controller"),
		InputProfileManager.glyph_for_action("ui_accept", "Xbox Wireless Controller"),
		"a face button must still resolve to its GLYPH")
	# CONTROL: no device name = keyboard, so the seam is genuinely switching behaviour.
	assert_eq(InputProfileManager.hint_for_action("battle_toggle_auto"), "Tab",
		"CONTROL: with no pad and no override it must fall back to the keyboard key")
