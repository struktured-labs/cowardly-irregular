extends GutTest

## Regression: the cutscene skip prompt and the readable-prop footer hardcoded "B" —
## on every Nintendo-family pad (8BitDo, SN30, Switch Pro) the cancel action fires
## from the cap printed Ⓐ, so the on-screen instruction named a button that did
## nothing. Both prompts now resolve the PHYSICAL cap through InputProfileManager,
## the same way HowToPlayOverlay and AutogrindUI already do.

const XBOX := "Xbox Wireless Controller"
const NINTENDO := "8BitDo SN30 Pro"


## Literal expectations per convention — never derived from the function under test.
func _expected_cancel_caps() -> Dictionary:
	if InputProfileManager.nintendo_mode:
		return {XBOX: "Ⓐ", NINTENDO: "Ⓑ"}
	return {XBOX: "Ⓑ", NINTENDO: "Ⓐ"}


func test_skip_prompt_names_the_physical_cancel_cap_per_pad_family() -> void:
	var caps := _expected_cancel_caps()
	assert_eq(CutsceneDirector.skip_prompt_text(XBOX), "Hold %s / Esc to skip..." % caps[XBOX])
	assert_eq(CutsceneDirector.skip_prompt_text(NINTENDO), "Hold %s / Esc to skip..." % caps[NINTENDO])
	assert_ne(CutsceneDirector.skip_prompt_text(XBOX), CutsceneDirector.skip_prompt_text(NINTENDO),
		"the two families print cancel on different caps — one string cannot serve both")


func test_readable_prop_footer_names_the_same_cap() -> void:
	var caps := _expected_cancel_caps()
	assert_eq(ReadableProp.close_glyph(XBOX), caps[XBOX])
	assert_eq(ReadableProp.close_glyph(NINTENDO), caps[NINTENDO])
	var prop := ReadableProp.new()
	add_child_autofree(prop)
	prop.setup("Notebook", func() -> Array: return ["only page"])
	prop.interact(null)
	assert_true(prop._footer_label.text.ends_with("[%s] Close" % ReadableProp.close_glyph()),
		"footer must render the resolved cap, got: %s" % prop._footer_label.text)
	prop._close_panel()


func test_director_label_is_built_from_the_helper() -> void:
	var director := CutsceneDirector.new()
	add_child_autofree(director)
	assert_eq(director._skip_label.text, CutsceneDirector.skip_prompt_text(),
		"_ready must build the label from skip_prompt_text, not a literal")


func test_no_hardcoded_b_prompt_survives_in_either_file() -> void:
	for path in ["res://src/cutscene/CutsceneDirector.gd", "res://src/exploration/ReadableProp.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_false(src.is_empty(), "%s must be readable" % path)
		assert_eq(src.find("Hold B "), -1, "%s: literal 'Hold B' prompt came back" % path)
		assert_eq(src.find("\"[B] Close\""), -1, "%s: literal '[B] Close' came back" % path)
