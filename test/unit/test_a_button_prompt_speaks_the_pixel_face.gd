extends GutTest

## Every pad prompt ("Ⓐ / ", "Ⓑ skip", the controls menu, how-to-play, tutorial hints) prints a face glyph in a plain
## Label, and none of Ⓐ Ⓑ Ⓧ Ⓨ ○ □ △ was in the pixel face, so the one character naming the button fell to a smooth
## Noto glyph at another size. ● ○ (autobattle ON/OFF) and ■ □ (EXP pips) are the same shapes, filled and hollow.

const SHAPES := ["Ⓐ", "Ⓑ", "Ⓧ", "Ⓨ", "○", "□", "△", "●", "■"]


func test_every_face_glyph_of_every_pad_family_is_drawn_by_the_face() -> void:
	var seen := 0
	var missing := ""
	for family in InputProfileManager.FACE_GLYPHS:
		for idx in InputProfileManager.FACE_GLYPHS[family]:
			var g := str(InputProfileManager.FACE_GLYPHS[family][idx])
			seen += 1
			for ch in g:
				if not UiFont.draws(ch):
					missing += ch
	assert_gte(seen, 12, "CONTROL: three families of four face buttons were read")
	assert_eq(missing, "", "face glyphs a prompt prints that the pixel face does not draw")


func test_the_printed_layouts_are_whole_in_the_face() -> void:
	# The real string the controls screen prints, not a list typed here.
	for family in InputProfileManager.FACE_GLYPHS:
		var s: String = InputProfileManager.face_layout_diagram(family)
		assert_false(s.contains("?"), "CONTROL: %s's diagram names all four buttons: %s" % [family, s])
		var missing := ""
		for ch in s:
			if not UiFont.draws(ch):
				missing += ch
		assert_eq(missing, "", "%s layout '%s' leaves the face" % [family, s])


func test_each_shape_is_one_cell_of_the_face() -> void:
	for ch in SHAPES:
		var rows: Array = UiFontGlyphs.GLYPHS.get(ch, [])
		assert_eq(rows.size(), UiFontGlyphs.ROWS, "'%s' has seven rows" % ch)
		for row in rows:
			assert_eq(str(row).length(), 5, "'%s' is five columns, like the letters beside it" % ch)


func test_the_cut_letters_are_four_different_buttons() -> void:
	var drawn := {}
	for ch in ["Ⓐ", "Ⓑ", "Ⓧ", "Ⓨ"]:
		drawn[str(UiFontGlyphs.GLYPHS.get(ch, []))] = ch
	assert_eq(drawn.size(), 4, "no two face letters share a drawing")


func test_the_built_face_draws_the_table_rows() -> void:
	var f: FontFile = UiFont.display()
	var size := Vector2i(UiFont.nominal(), 0)
	var img: Image = f.get_texture_image(0, size, 0)
	for ch in SHAPES:
		var rows: Array = UiFontGlyphs.GLYPHS.get(ch, [])
		var r: Rect2 = f.get_glyph_uv_rect(0, size, ch.unicode_at(0))
		assert_eq(Vector2i(r.size), Vector2i(5, UiFontGlyphs.ROWS), "'%s' cell in the built face" % ch)
		var lit := 0
		var same := true
		for y in rows.size():
			for x in str(rows[y]).length():
				var on: bool = img.get_pixel(int(r.position.x) + x, int(r.position.y) + y).a > 0.5
				lit += int(on)
				if on != (str(rows[y])[x] == "#"):
					same = false
		assert_true(same, "'%s' in the built face is the table's rows" % ch)
		assert_gt(lit, 5, "CONTROL: '%s' lit some pixels" % ch)
