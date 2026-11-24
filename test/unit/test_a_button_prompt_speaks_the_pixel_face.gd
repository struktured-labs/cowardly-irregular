extends GutTest

## Pad prompts print a face glyph in a plain Label. The PlayStation shapes ○ □ △ were not in the pixel face, so they fell
## to a smooth Noto glyph at another size; ● ○ (autobattle ON/OFF) and ■ □ (EXP pips) are the same shapes. The circled
## letters are DELIBERATELY left to Noto: drawn as a cut-out in a 5-wide cell (0ab7cf8d4) they read as "0" at 1x.

const SHAPES := ["○", "□", "△", "●", "■"]
## Shrink-only. Drawing one of these in the face reds below, so the legibility call is made again on purpose.
const LEFT_TO_NOTO := ["Ⓐ", "Ⓑ", "Ⓧ", "Ⓨ"]


func _face_glyphs() -> Array:
	var out: Array = []
	for family in InputProfileManager.FACE_GLYPHS:
		for idx in InputProfileManager.FACE_GLYPHS[family]:
			out.append(str(InputProfileManager.FACE_GLYPHS[family][idx]))
	return out


func test_every_face_glyph_is_in_the_face_or_deliberately_left_to_noto() -> void:
	var glyphs := _face_glyphs()
	assert_gte(glyphs.size(), 12, "CONTROL: three families of four face buttons were read")
	var missing := ""
	for g in glyphs:
		for ch in g:
			if not UiFont.draws(ch) and not LEFT_TO_NOTO.has(ch):
				missing += ch
	assert_eq(missing, "", "face glyphs a prompt prints that the pixel face neither draws nor deliberately leaves to Noto")


func test_the_letters_left_to_noto_are_not_in_the_face_and_still_resolve() -> void:
	var f: Font = UiFont.display()
	assert_gt(f.fallbacks.size(), 0, "CONTROL: the face has a chain behind it")
	var glyphs := _face_glyphs()
	for ch in LEFT_TO_NOTO:
		assert_true(glyphs.has(ch), "CONTROL: '%s' is still a face glyph some pad prints (else drop it from the list)" % ch)
		assert_false(UiFont.draws(ch), "'%s' is drawn by the face again: re-judge it at 1x before shrinking LEFT_TO_NOTO" % ch)
		var found := false
		for fb in f.fallbacks:
			found = found or (fb != null and fb.has_char(ch.unicode_at(0)))
		assert_true(found, "'%s' resolves in the chain behind the face (no tofu)" % ch)


func test_the_playstation_layout_is_whole_in_the_face() -> void:
	# The real string the controls screen prints, not a list typed here.
	var s: String = InputProfileManager.face_layout_diagram("playstation")
	assert_false(s.contains("?"), "CONTROL: the diagram names all four buttons: %s" % s)
	var missing := ""
	for ch in s:
		if not UiFont.draws(ch):
			missing += ch
	assert_eq(missing, "", "playstation layout '%s' leaves the face" % s)


func test_each_shape_is_one_cell_of_the_face() -> void:
	for ch in SHAPES:
		var rows: Array = UiFontGlyphs.GLYPHS.get(ch, [])
		assert_eq(rows.size(), UiFontGlyphs.ROWS, "'%s' has seven rows" % ch)
		for row in rows:
			assert_eq(str(row).length(), 5, "'%s' is five columns, like the letters beside it" % ch)


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
