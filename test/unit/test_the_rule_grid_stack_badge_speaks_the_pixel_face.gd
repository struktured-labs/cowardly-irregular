extends GutTest

## The autobattle rule grid (AutobattleGridEditor) marks a cell with a small badge in a plain 12 px Label, which the
## pixel face draws at its 1x step. "⊞" (a collapsed stack of actions) was not in the face, so it fell to a smooth Noto
## glyph sitting on pixel cell text. The cycle badge "↻" is DELIBERATELY left to Noto: every 5x7 loop drawn for it read
## as ¢ or G at 1x, worse than the smooth arrow it would replace.

const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const DRAWN := ["⊞"]
## Shrink-only. Drawing one of these in the face reds below, so the legibility call is made again on purpose.
const LEFT_TO_NOTO := ["↻"]


## Every badge glyph the editor assigns, read from its source so a new badge is judged without editing this file.
func _badges() -> Array:
	var src := FileAccess.get_file_as_string(EDITOR)
	var re := RegEx.new()
	re.compile("badge\\.text\\s*=\\s*\"([^\"]+)\"")
	var out: Array = []
	for m in re.search_all(src):
		for ch in m.get_string(1):
			if not out.has(ch):
				out.append(ch)
	return out


func test_every_rule_grid_badge_is_in_the_face_or_deliberately_left_to_noto() -> void:
	var badges := _badges()
	assert_gte(badges.size(), 2, "CONTROL: the editor's badge assignments were read (%s)" % [badges])
	var missing := ""
	for ch in badges:
		if not UiFont.draws(ch) and not LEFT_TO_NOTO.has(ch):
			missing += ch
	assert_eq(missing, "", "rule grid badges the pixel face neither draws nor deliberately leaves to Noto")


func test_the_badge_left_to_noto_is_not_in_the_face_and_still_resolves() -> void:
	var f: Font = UiFont.display()
	assert_gt(f.fallbacks.size(), 0, "CONTROL: the face has a chain behind it")
	var badges := _badges()
	for ch in LEFT_TO_NOTO:
		assert_true(badges.has(ch), "CONTROL: '%s' is still a badge the editor prints (else drop it from the list)" % ch)
		assert_false(UiFont.draws(ch), "'%s' is drawn by the face again: re-judge it at 1x before shrinking LEFT_TO_NOTO" % ch)
		var found := false
		for fb in f.fallbacks:
			found = found or (fb != null and fb.has_char(ch.unicode_at(0)))
		assert_true(found, "'%s' resolves in the chain behind the face (no tofu)" % ch)


func test_the_stack_badge_is_one_cell_of_the_face() -> void:
	for ch in DRAWN:
		var rows: Array = UiFontGlyphs.GLYPHS.get(ch, [])
		assert_eq(rows.size(), UiFontGlyphs.ROWS, "'%s' has seven rows" % ch)
		for row in rows:
			assert_eq(str(row).length(), 5, "'%s' is five columns, like the letters beside it" % ch)


func test_the_built_face_draws_the_table_rows() -> void:
	var f: FontFile = UiFont.display()
	var size := Vector2i(UiFont.nominal(), 0)
	var img: Image = f.get_texture_image(0, size, 0)
	for ch in DRAWN:
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
