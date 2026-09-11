extends GutTest

## The credits roll's skip hint was the literal "B / Esc: Skip". On a Nintendo-family pad (his
## 8BitDo) cancel fires from the cap printed Ⓐ, so every world ending named a button that does
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
		assert_true(credits._skip_hint.text.ends_with("/ Esc: Skip"), "the keyboard half survives")


func test_no_literal_b_hint_survives_in_the_credits() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/CreditsSequence.gd")
	assert_false(src.is_empty(), "control: source readable")
	assert_eq(src.find("\"B / Esc"), -1, "CreditsSequence: literal 'B / Esc' hint came back")
