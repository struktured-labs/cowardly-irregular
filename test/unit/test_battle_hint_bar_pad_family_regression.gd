extends GutTest

## The permanent battle hint bar read "[L] Defer · [R] Advance · [X] Speed · [Select] Auto" as a
## hardcoded const, on screen for the entire game.
##
## Speed is bound to raw JOY_BUTTON_Y — index 3, the NORTH face. The glyph printed on index 3 is
## Ⓧ only on Nintendo-layout pads. It is Ⓨ on Xbox and △ on PlayStation, and on PlayStation the
## button actually labelled ✕ is index 0 — Cancel. So a PS player following the bar pressed Cancel.
## The file's own comment acknowledged targeting "the Nintendo-layout pads this game targets",
## while FACE_GLYPHS and face_family_for_device support all three families.

const SPEED_INDEX := JOY_BUTTON_Y  # 3, north face — what BattleScene actually binds


## The three families genuinely differ at the index Speed uses. If this ever collapses to one
## glyph the bug is unreproducible and the rest of the file proves nothing.
func test_the_families_disagree_at_the_speed_index() -> void:
	var g := {}
	for fam in ["nintendo", "xbox", "playstation"]:
		g[fam] = str(InputProfileManager.FACE_GLYPHS[fam][SPEED_INDEX])
	assert_ne(g["nintendo"], g["xbox"], "index 3 must differ Nintendo vs Xbox, else there is no bug")
	assert_ne(g["nintendo"], g["playstation"], "and Nintendo vs PlayStation")
	gut.p("index %d -> nintendo %s · xbox %s · playstation %s" % [SPEED_INDEX, g["nintendo"], g["xbox"], g["playstation"]])


## Behavioural: the accessor must return the PHYSICAL glyph for each family, not one hardcoded set.
func test_face_glyph_for_index_is_family_aware() -> void:
	assert_true(InputProfileManager.has_method("face_glyph_for_index"),
		"a raw-index accessor must exist — glyph_for_action only resolves ACTIONS, and Speed is a raw binding")
	var nin: String = InputProfileManager.face_glyph_for_index(SPEED_INDEX, "Nintendo Switch Pro Controller")
	var xb: String = InputProfileManager.face_glyph_for_index(SPEED_INDEX, "Xbox 360 Controller")
	var ps: String = InputProfileManager.face_glyph_for_index(SPEED_INDEX, "Sony DualSense Wireless Controller")
	assert_eq(nin, str(InputProfileManager.FACE_GLYPHS["nintendo"][SPEED_INDEX]), "Nintendo pad gets the Nintendo glyph")
	assert_eq(xb, str(InputProfileManager.FACE_GLYPHS["xbox"][SPEED_INDEX]), "Xbox pad gets the Xbox glyph")
	assert_eq(ps, str(InputProfileManager.FACE_GLYPHS["playstation"][SPEED_INDEX]), "PlayStation pad gets the PlayStation glyph")
	assert_ne(xb, nin, "CONTROL: the accessor must actually vary, not return one constant")


## The bar must be DERIVED, not the frozen const. A source pin would pass on a dead helper.
func test_the_hint_bar_is_derived_not_frozen() -> void:
	var bar: String = Win98Menu.hint_text()
	assert_gt(bar.length(), 0, "the bar must render something")
	assert_true(bar.contains("Defer") and bar.contains("Advance") and bar.contains("Speed"),
		"it must still name the verbs it always named: %s" % bar)
	# whatever family the test box resolves to, the Speed glyph in the bar must be THAT family's
	var expected: String = InputProfileManager.face_glyph_for_index(SPEED_INDEX)
	if expected != "?":
		assert_true(bar.contains(expected),
			"the bar must print the live family's Speed glyph (%s), got: %s" % [expected, bar])


## The literal that caused it must not come back. "[X] Speed" is correct for exactly one family.
func test_the_hardcoded_nintendo_letter_is_gone_from_the_render_path() -> void:
	for path in ["res://src/ui/Win98Menu.gd", "res://src/battle/BattleScene.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_false(src.contains("label.text = HINT_DEFAULT_TEXT"),
			"%s must render via hint_text(), not the frozen const" % path)
		assert_false(src.contains("Win98Menu.HINT_DEFAULT_TEXT"),
			"%s must not reach past the accessor to the const" % path)


## CONTROL: the const survives as a fallback, so an unplugged/unknown pad still gets a bar.
func test_the_const_remains_as_a_fallback() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	assert_true(src.contains("const HINT_DEFAULT_TEXT"),
		"the fallback must still exist — no pad connected must not mean no hint bar")
	assert_true(src.contains("return HINT_DEFAULT_TEXT"),
		"and hint_text() must actually fall back to it")
