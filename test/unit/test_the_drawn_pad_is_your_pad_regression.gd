extends GutTest

## ControllerOverlay draws a PICTURE of a pad — four face circles at fixed positions — and welded
## Nintendo's letters onto them: A east, B south, X north, Y west. It is on by default
## (`show_controller_overlay: bool = true`) and the autogrind context hangs "Exit" off the south
## circle.
##
## ⛔ THE DEFECT. The label placement was always CORRECT: "b" is the SOUTH position and Exit is
## ui_cancel, which is index 0 = south on every family. What was wrong is the letter drawn in that
## circle. On an Xbox pad south prints Ⓐ, so the overlay showed "Exit" pointing at a circle marked
## B — and that player's physical B is EAST, which is ui_accept. Look for B, press B, confirm.
## Measured per family:
##
##            east   south  north  west
##   xbox      Ⓑ      Ⓐ      Ⓨ      Ⓧ
##   nintendo  Ⓐ      Ⓑ      Ⓧ      Ⓨ        <- the one family the frozen letters matched
##   psx       ○      ✕      △      □
##
## 🔑 WHY NO CAPTION SCAN COULD FIND THIS, and it is the shape @cowir-autogrind named:
##   caption form   "A/Enter: Confirm"              a letter inside a STRING       a scan matches
##   diagram form   _draw_face_button(pos, "A", …)  a letter as a CALL ARGUMENT    invisible
## There is no `.text =`, no `[A]`, no `A:`. `RadialPicker` was the first of these and I caught it
## by NAME rather than by the net, which I should have read as a signal at the time. Two instances
## is a shape, so this file guards the drawing call rather than the rendered string.
##
## WITH NO PAD the circles show the POSITION (E/S/N/W). That is not a placeholder: the position is
## the only fact true of every pad, and face_glyph_for_index would hand back the XBOX table's
## letter as though it were neutral — the bucket-4 default this lane swept in .318.

const OVERLAY_PATH := "res://src/ui/ControllerOverlay.gd"

const XBOX := "Xbox 360 Controller"
const NINTENDO := "Nintendo Switch Pro Controller"
const PLAYSTATION := "PS5 Controller"

## The drawn positions, as FACE_GLYPHS indices. POS_A is rightmost (east), POS_B lowest (south),
## POS_X topmost (north), POS_Y leftmost (west) — read off the constants, not assumed.
const EAST := 1
const SOUTH := 0
const NORTH := 3
const WEST := 2


func _ipm():
	return InputProfileManager


func _overlay() -> Node:
	var o = load(OVERLAY_PATH).new()
	add_child_autofree(o)
	return o


## BEHAVIOURAL. GUT attaches no pad, which is exactly the branch that used to print a guess.
func test_with_no_pad_the_circles_show_the_position_not_a_family() -> void:
	assert_true(Input.get_connected_joypads().is_empty(),
		"precondition: this arm describes the no-pad case, which is what GUT runs as")
	var o := _overlay()
	assert_eq(o._face_print(EAST, "E"), "E", "east must fall back to its position")
	assert_eq(o._face_print(SOUTH, "S"), "S", "south likewise")
	assert_eq(o._face_print(NORTH, "N"), "N", "north likewise")
	assert_eq(o._face_print(WEST, "W"), "W", "west likewise")
	for idx in [EAST, SOUTH, NORTH, WEST]:
		var drawn: String = o._face_print(idx, "?")
		for family in _ipm().FACE_GLYPHS:
			for i in _ipm().FACE_GLYPHS[family]:
				assert_ne(drawn, str(_ipm().FACE_GLYPHS[family][i]),
					"no family's glyph may be drawn with no pad attached — that is the xbox guess")


## THE INVERSION, pinned per family. This is what an Xbox player was looking at.
func test_the_letter_at_each_position_is_that_familys_letter() -> void:
	assert_eq(_ipm().face_glyph_for_index(EAST, XBOX), "Ⓑ",
		"an Xbox pad prints B on the EAST circle — the overlay drew A there")
	assert_eq(_ipm().face_glyph_for_index(SOUTH, XBOX), "Ⓐ",
		"…and A on the SOUTH circle, which is where 'Exit' hangs")
	assert_eq(_ipm().face_glyph_for_index(EAST, NINTENDO), "Ⓐ",
		"Nintendo is the one family the frozen letters matched — which is how they survived")
	assert_eq(_ipm().face_glyph_for_index(SOUTH, NINTENDO), "Ⓑ")
	assert_eq(_ipm().face_glyph_for_index(SOUTH, PLAYSTATION), "✕",
		"a PlayStation pad prints no letters at all on its faces")


## ⛔ THE CONSEQUENCE, stated as its own claim so it cannot be read as a cosmetic preference:
## on an Xbox pad the frozen letters pointed at the OPPOSITE action.
func test_on_xbox_the_frozen_letters_pointed_at_the_opposite_action() -> void:
	# "Exit" hangs off the SOUTH circle, and south is ui_cancel on every family.
	assert_eq(_ipm().PROFILE_STANDARD["ui_cancel"][0], SOUTH,
		"precondition: Cancel is the south face, which is where the Exit label sits")
	assert_eq(_ipm().PROFILE_STANDARD["ui_accept"][0], EAST, "and Confirm is east")
	# The overlay used to mark south "B". An Xbox player's physical B is EAST = Confirm.
	assert_eq(_ipm().face_glyph_for_index(EAST, XBOX), "Ⓑ",
		"so looking for the 'B' the overlay drew, an Xbox player finds the CONFIRM button")


## THE RATCHET for the shape a caption scan cannot see: a face letter as a DRAWING ARGUMENT.
func test_no_face_letter_is_welded_into_a_drawing_call() -> void:
	var src := FileAccess.get_file_as_string(OVERLAY_PATH)
	assert_gt(src.length(), 500, "CONTROL: the overlay source must be readable")
	for frozen in ["_draw_face_button(POS_A, \"A\"", "_draw_face_button(POS_B, \"B\"",
			"_draw_face_button(POS_X, \"X\"", "_draw_face_button(POS_Y, \"Y\""]:
		assert_eq(src.find(frozen), -1,
			"a face letter is welded into a drawing call: %s — no caption scan can see this, " % frozen +
			"which is why it survived every sweep this lane ran")
	assert_true(src.find("_face_print(") > -1,
		"the drawn letters must come from the pad-aware helper")
	## ⛔ AND THE INDEX MUST MATCH THE POSITION. Deriving the letter is only half of it: feed
	## _face_print the wrong index and every behavioural arm above still passes, because with no
	## pad they all return the position initial regardless. This is the one claim that needs the
	## source — the mapping is invisible in a headless render.
	for pair in [["POS_A", "_face_print(1, \"E\")"], ["POS_B", "_face_print(0, \"S\")"],
			["POS_X", "_face_print(3, \"N\")"], ["POS_Y", "_face_print(2, \"W\")"]]:
		assert_true(src.find("%s, %s" % [pair[0], pair[1]]) > -1,
			"%s must draw the letter for %s — POS_A is rightmost (east, index 1), POS_B lowest " % pair +
			"(south, 0), POS_X topmost (north, 3), POS_Y leftmost (west, 2)")


## THE CONTROL. Without it the ratchet passes on an unreadable file and the table on an empty one.
func test_the_probe_can_tell_a_frozen_diagram_from_a_derived_one() -> void:
	var planted := "\t_draw_face_button(POS_A, \"A\", \"a\")"
	assert_true(planted.find("_draw_face_button(POS_A, \"A\"") > -1,
		"the needle must match the frozen form when it is present")
	var live := FileAccess.get_file_as_string(OVERLAY_PATH)
	assert_true(live.find("_draw_face_button(POS_A,") > -1,
		"…and the call must still exist in the file, or the ratchet guards a deleted line")
	var seen := {}
	for dev in [XBOX, NINTENDO, PLAYSTATION]:
		seen[_ipm().face_glyph_for_index(EAST, dev)] = true
	assert_eq(seen.size(), 3,
		"three families must print three different letters on the east circle, or the diagram " +
		"could not have been wrong for anyone")
