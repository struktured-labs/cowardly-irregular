extends GutTest

## Regression (struktured 2026-10-03, "look for [font problems] across the board"): the symbol fallback chain sets the line
## height for every Label (NotoSansSymbols: 28px at 13px against the base font's ~18), so every wrapped label in the game
## was double-spaced. FontFallbacks now corrects each Label as it enters the tree, re-measures on a font-size change, and
## leaves a label's own line_spacing choice alone.


func _label(text: String, size: int = 13) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	add_child_autofree(l)
	return l


func test_a_new_label_gets_the_correction() -> void:
	var l := _label("one\ntwo")
	var want := FontFallbacks.cached_correction(l.get_theme_font("font"), 13)
	assert_lte(want, 0, "a correction only ever shortens a line (0 since the fallback metrics carry the base line box)")
	assert_eq(l.get_theme_constant("line_spacing"), want, "a label entering the tree takes the line-spacing correction")


func test_a_font_size_change_re_measures() -> void:
	var l := _label("one\ntwo", 13)
	l.add_theme_font_size_override("font_size", 24)
	await get_tree().process_frame
	assert_eq(l.get_theme_constant("line_spacing"), FontFallbacks.cached_correction(l.get_theme_font("font"), 24),
		"a label resized after entering the tree is corrected for its new size")


func test_a_labels_own_choice_is_kept() -> void:
	var l := Label.new()
	l.add_theme_constant_override("line_spacing", 7)
	add_child_autofree(l)
	assert_eq(l.get_theme_constant("line_spacing"), 7, "CONTROL: an explicit line_spacing is the label's call, not ours")


func test_two_lines_are_no_longer_double_spaced() -> void:
	var one := _label("one")
	var two := _label("one\ntwo")
	await get_tree().process_frame
	var pitch: float = two.get_minimum_size().y - one.get_minimum_size().y
	assert_lt(pitch, 13 * 1.6, "the second line adds an ordinary line pitch, got %.0f px" % pitch)
