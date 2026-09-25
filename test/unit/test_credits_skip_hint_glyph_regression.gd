extends GutTest

## The credits roll's skip hint was the literal "B / Esc: Skip". "B" names Cancel on one pad family
## only (InputProfileManager decides which), so on the rest every world ending named a button that does
## nothing — the same class as the skip prompt, the dialogue advance hint, the choice menu and the
## key-item popup, which all resolve the physical cap through InputProfileManager. Now the credits
## do too, per roll.

const XBOX := "Xbox Wireless Controller"
const NINTENDO := "8BitDo SN30 Pro"


## Literal expectations per convention — never derived from the function under test.
func _cancel_caps() -> Dictionary:
	if InputProfileManager.nintendo_mode:
		return {XBOX: "Ⓐ", NINTENDO: "Ⓑ"}
	return {XBOX: "Ⓑ", NINTENDO: "Ⓐ"}


func test_the_hint_names_the_physical_cancel_cap_per_pad_family() -> void:
	var caps := _cancel_caps()
	assert_eq(CreditsSequence.skip_hint_text(XBOX), "%s / Esc: Skip" % caps[XBOX])
	assert_eq(CreditsSequence.skip_hint_text(NINTENDO), "%s / Esc: Skip" % caps[NINTENDO])
	assert_ne(caps[XBOX], caps[NINTENDO], "control: the two families print different caps")


func test_the_roll_builds_its_hint_from_the_helper() -> void:
	var credits := CreditsSequence.new()
	add_child_autofree(credits)
	credits._build_ui()
	assert_not_null(credits._skip_hint, "control: _build_ui builds the hint label")
	if credits._skip_hint:
		assert_eq(credits._skip_hint.text, CreditsSequence.skip_hint_text(), "_build_ui must build the hint from skip_hint_text, not a literal")
		## "/ Esc: Skip" pinned the SLASH, which only exists when a pad cap precedes it — the intent
		## is that the keyboard half survives, and it does so with or without a pad attached.
		assert_true(credits._skip_hint.text.ends_with("Esc: Skip"), "the keyboard half survives")


func test_no_literal_b_hint_survives_in_the_credits() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/CreditsSequence.gd")
	assert_false(src.is_empty(), "control: source readable")
	assert_eq(src.find("\"B / Esc"), -1, "CreditsSequence: literal 'B / Esc' hint came back")


## ⛔ NO PAD, NO CAP. `glyph_for_action` answers an EMPTY device name out of the xbox table (an
## unknown pad is overwhelmingly XInput), so with zero pads connected every world ending printed
## "Ⓐ / Esc: Skip" — a circled Xbox glyph shown to a keyboard-only player. Measured 2026-09-19.
## The two arms above pass a NAMED device, so the no-pad case was never in their corpus and they
## were green through it for the life of the file.
func test_the_roll_names_no_cap_when_no_pad_is_attached() -> void:
	if not Input.get_connected_joypads().is_empty():
		pass_test("a pad is attached here, so the no-pad case is unreachable — not evidence either way")
		return
	assert_eq(CreditsSequence.skip_hint_text(), "Esc: Skip",
		"with no pad the roll must name the KEY alone; a family glyph is hardware the player does not have")
	assert_eq(CreditsSequence.skip_hint_text(XBOX), "%s / Esc: Skip" % _cancel_caps()[XBOX],
		"control: the ROLL still gets its cap for an explicitly NAMED device, so the guard is keyed to pad ABSENCE and not to the argument being omitted")
