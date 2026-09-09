extends GutTest

## Regression: the advance hint on every dialogue line — cutscene box AND battle box —
## was the literal "Z / A / Click". On Nintendo-family pads (8BitDo, SN30, Switch Pro)
## confirm fires from the cap printed Ⓑ, so the most-seen prompt in the game named the
## wrong button. Both boxes now resolve the physical cap through InputProfileManager
## and re-resolve each time the hint is shown, so a pad plugged in mid-scene is honoured.

const XBOX := "Xbox Wireless Controller"
const NINTENDO := "8BitDo SN30 Pro"


## Literal expectations per convention — never derived from the function under test.
func _expected_confirm_caps() -> Dictionary:
	if InputProfileManager.nintendo_mode:
		return {XBOX: "Ⓑ", NINTENDO: "Ⓐ"}
	return {XBOX: "Ⓐ", NINTENDO: "Ⓑ"}


func test_confirm_glyph_names_the_physical_cap_per_pad_family() -> void:
	var caps := _expected_confirm_caps()
	assert_eq(CutsceneDialogue.confirm_glyph(XBOX), caps[XBOX])
	assert_eq(CutsceneDialogue.confirm_glyph(NINTENDO), caps[NINTENDO])
	assert_eq(CutsceneDialogue.advance_hint_text(NINTENDO), "Z / %s / Click ▶" % caps[NINTENDO])
	assert_eq(BattleDialogue.advance_hint_text(NINTENDO), "Z / %s / Click to continue..." % caps[NINTENDO])


func test_cutscene_box_hint_is_built_from_the_helper() -> void:
	var box := CutsceneDialogue.new()
	add_child_autofree(box)
	assert_not_null(box._advance_hint, "the dialogue box must build its advance hint at _ready")
	assert_eq(box._advance_hint.text, CutsceneDialogue.advance_hint_text(),
		"_ready must build the hint from advance_hint_text, not a literal")


func test_battle_box_hint_is_built_from_the_helper() -> void:
	var box := BattleDialogue.new()
	add_child_autofree(box)
	assert_not_null(box._advance_hint, "the battle dialogue box must build its advance hint at _ready")
	assert_eq(box._advance_hint.text, BattleDialogue.advance_hint_text(),
		"_ready must build the hint from advance_hint_text, not a literal")


func test_no_literal_a_prompt_survives_in_either_box() -> void:
	for path in ["res://src/cutscene/CutsceneDialogue.gd", "res://src/ui/BattleDialogue.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_false(src.is_empty(), "%s must be readable" % path)
		assert_eq(src.find("\"Z / A /"), -1, "%s: literal 'Z / A /' prompt came back" % path)
