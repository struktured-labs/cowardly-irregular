extends GutTest

## ⛔ THE F1 REFERENCE SWAPPED TWO CONTROLS ON AN XBOX PAD, AND IT IS THE ONE SCREEN WHOSE WHOLE JOB
## IS NAMING BUTTONS (struktured: "it should be really easy to know all the buttons").
##
## Two rows were hardcoded Nintendo spellings -- `"X (top face)"` for Battle speed and
## `"Y (west face)"` for Repeat. Measured on the real derivation:
##
##                      north face (idx 3)    west face (idx 2)
##     Nintendo                 Ⓧ                    Ⓨ
##     Xbox                     Ⓨ                    Ⓧ
##     PS5                      △                    □
##
## 🔑 So the two letters are each other's OPPOSITE across the two families, and the rows named one
## letter each: an Xbox player who reads "X" for Battle speed presses Ⓧ, which is the WEST face --
## REPEAT. Reading "Y" for Repeat presses Ⓨ -- BATTLE SPEED. **Not one wrong letter; the two
## controls trade places, in both directions.** A third row (Dash, "Y (west face)") had the right
## position and the same Nintendo-only letter.
##
## ⚠️ WHY NO EXISTING GUARD CAUGHT IT, and this is the evening's recurring tell: there IS a file
## called `test_help_names_the_printed_button_regression`, it is green, and its subject is
## `TitleScreen.build_confirm_cancel_rows` -- **2 rows of a 17-row table.** The other 15 were never
## in any corpus. HowToPlayOverlay's own header says so outright: *"The rows still written out below
## are NOT derived and several are Nintendo-only spellings... The whole body is one returned
## multi-line string, which is why every caption census in the fleet skipped this file as a
## docstring and nothing flagged them."* The gap was documented and assigned away; the helper that
## fixes it (`_face_cell`) was already in the same file, used by three other rows.
##
## ⛔ AND A SECOND GUARD ALREADY READ THIS FILE AND WAS CORRECTLY GREEN:
## `test_no_pad_means_no_guess_regression:123` loads HowToPlayOverlay and scans every surface for a
## leaked family glyph without a pad. It passes because it scans `FACE_GLYPHS` -- the CIRCLED forms
## `Ⓐ Ⓑ Ⓧ Ⓨ ✕ ○ □ △` -- and the defect was plain ASCII `X` and `Y` inside a caption. **Two guards
## looked at this screen and neither could see it: one covered 2 rows of 17, the other watched a
## different CHARACTER CLASS.** Worth stating so the next reader does not take the glyph scanner as
## cover for captions; it is not, and it never claimed to be.
##
## 📌 ASSERTS PER ROW, not per file. A file-wide "contains North face" passes if BOTH cells derive
## the same index -- which is the likeliest way to break this while fixing it.

const Overlay := preload("res://src/ui/HowToPlayOverlay.gd")

var _ipm: Node


func before_each() -> void:
	_ipm = load("res://src/input/InputProfileManager.gd").new()
	add_child_autofree(_ipm)


## The line of the reference that explains a given control, so a row can be judged on its own.
func _row_naming(needle: String) -> String:
	for line in Overlay.build_text().split("\n"):
		if str(line).find(needle) != -1:
			return str(line)
	return ""


## THE DEMONSTRATION: the derivation really does give different letters per family, so a single
## hardcoded letter cannot be right for everyone. Without this arm the rest could pass over a
## derivation that returns one constant.
func test_the_two_faces_trade_letters_between_the_families() -> void:
	assert_eq(_ipm.face_glyph_for_index(JOY_BUTTON_Y, "Xbox Series X Controller"), "Ⓨ",
		"north face is printed Y on an Xbox pad")
	assert_eq(_ipm.face_glyph_for_index(JOY_BUTTON_X, "Xbox Series X Controller"), "Ⓧ",
		"west face is printed X on an Xbox pad")
	assert_eq(_ipm.face_glyph_for_index(JOY_BUTTON_Y, "Nintendo Switch Pro Controller"), "Ⓧ",
		"north face is printed X on a Nintendo pad -- the OPPOSITE letter")
	assert_eq(_ipm.face_glyph_for_index(JOY_BUTTON_X, "Nintendo Switch Pro Controller"), "Ⓨ",
		"west face is printed Y on a Nintendo pad -- the OPPOSITE letter")
	## PS5 prints neither letter, so "a letter" is not merely mis-assigned, it is the wrong KIND.
	assert_eq(_ipm.face_glyph_for_index(JOY_BUTTON_Y, "PS5 Controller"), "△",
		"a PlayStation pad prints shapes; no letter is correct for it at all")


## No pad is attached under the test wrapper (it tmpfs's /dev/input), so every face cell must name
## the POSITION. That is the branch a player without a pad sees, and it is deterministic here.
func test_each_row_names_the_face_it_actually_uses() -> void:
	## The convention at test_no_pad_means_no_guess_regression:118 -- state the precondition rather
	## than depend on it. run_tests.sh tmpfs's /dev/input, so no pad is attached; with RUN_TESTS_SEE_PADS=1
	## the cells become GLYPHS and the asserts below would fail naming "North face", which reads as a
	## derivation bug. This line makes the real cause the first thing printed.
	assert_true(Input.get_connected_joypads().is_empty(),
		"PRECONDITION: this arm's subject is the no-pad branch, which is what the wrapper runs as")
	var speed := _row_naming("Battle speed")
	var repeat := _row_naming("Repeat last turn")
	var dash := _row_naming("hold to move")
	assert_ne(speed, "", "PRECONDITION: the reference still has a Battle speed row")
	assert_ne(repeat, "", "PRECONDITION: the reference still has a Repeat row")
	assert_ne(dash, "", "PRECONDITION: the reference still has a Dash row")
	assert_string_contains(speed, "North face",
		"Battle speed is raw JOY_BUTTON_Y -- the NORTH face, named by position when no pad is attached")
	assert_string_contains(repeat, "West face",
		"Repeat is raw JOY_BUTTON_X -- the WEST face")
	assert_string_contains(dash, "West face",
		"Dash is bound to pad button 2 -- the WEST face")


## THE ANTI-REGRESSION, derived over every row rather than pinning these three: a face cell must
## never carry a bare family letter. Catches the next row written the old way, which is how three
## of them got here.
func test_no_row_names_a_bare_family_letter_for_a_face() -> void:
	var text: String = Overlay.build_text()
	var re := RegEx.new()
	re.compile("[ABXY] \\((top|north|west|east|south|bottom) face\\)")
	var hits: Array = []
	for m in re.search_all(text):
		hits.append(m.get_string())
	assert_eq(hits, [],
		"a face cell must be DERIVED, not a hardcoded letter -- 'X (top face)' is correct only on a "
		+ "Nintendo pad and names the opposite control on an Xbox one. Found: %s" % [hits])
	## CONTROL: the pattern must be able to fire, or an empty result proves nothing about the text.
	var probe := RegEx.new()
	probe.compile("[ABXY] \\((top|north|west|east|south|bottom) face\\)")
	assert_eq(probe.search("X (top face)      ` (backtick)").get_string(), "X (top face)",
		"CONTROL: the detector must match the exact string this defect shipped as")
