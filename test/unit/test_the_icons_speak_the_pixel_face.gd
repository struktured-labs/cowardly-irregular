extends GutTest

## Plain Labels draw the pixel face, but ✦ ♦ ♥ ♪ ☠ ⚔ were not in it, so each one fell to a smooth fallback font at
## another size beside pixel words: the victory LEVEL UP line, the equipment compare line, the key-item emblem,
## the cutscene heart and note emotes (beside a pixel ! and ?), the bard's barks, the doom counter, the treasure count.

const ICONS := ["✦", "♦", "♥", "♪", "☠", "⚔"]


## Every glyph a table hands straight to a plain Label: derived from the tables, so a new entry is judged too.
func _table_glyphs() -> Array:
	var out: Array = []
	for v in KeyItemPopup.EMBLEM_BY_CATEGORY.values():
		out.append(str(v))
	out.append(KeyItemPopup.EMBLEM_DEFAULT)
	for v in CutsceneActor.EMOTE_GLYPHS.values():
		out.append(str(v))
	return out


func test_every_emblem_and_emote_is_drawn_by_the_face() -> void:
	var glyphs := _table_glyphs()
	assert_gt(glyphs.size(), 10, "CONTROL: both tables were read")
	var missing: Array = []
	for g in glyphs:
		for ch in g:
			if not UiFont.draws(ch):
				missing.append(ch)
	assert_eq(missing, [], "every emblem and emote glyph is in the pixel face")


func test_the_draws_check_can_say_no() -> void:
	# CONTROL for the measure: an emoji the face never draws must read as not drawn.
	assert_false(UiFont.draws("⚡"), "⚡ is not in the face")
	assert_true(UiFont.draws("!"), "! is")


func test_each_icon_is_one_cell_of_the_face() -> void:
	for ch in ICONS:
		var rows: Array = UiFontGlyphs.GLYPHS.get(ch, [])
		assert_eq(rows.size(), UiFontGlyphs.ROWS, "'%s' has seven rows" % ch)
		for row in rows:
			assert_eq(str(row).length(), 5, "'%s' is five columns, like the letters beside it" % ch)


func test_the_built_face_draws_the_table_rows() -> void:
	var f: FontFile = UiFont.display()
	var size := Vector2i(UiFont.nominal(), 0)
	var img: Image = f.get_texture_image(0, size, 0)
	for ch in ICONS:
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
