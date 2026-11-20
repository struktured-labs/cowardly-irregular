extends GutTest

## cowir-deploy 26366 (the .807 store re-shoot): the stairs markers "▲" / "▼" drew in the pixel face as a stepped
## block that read as a "T". The rows were 1,1,3,3,5 wide, so the two 1-wide rows made a stem. A filled triangle
## in this face is one row per width.

const UP := "▲"
const DOWN := "▼"


## The ink width of each row that has ink, top to bottom; -1 for a row whose ink has a gap or is off centre.
func _widths(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		var r := str(row)
		var first := r.find("#")
		if first < 0:
			continue
		var last := r.rfind("#")
		var solid := not r.substr(first, last - first + 1).contains(".")
		var centred := first == r.length() - 1 - last
		out.append(last - first + 1 if solid and centred else -1)
	return out


func test_the_up_triangle_widens_on_every_row() -> void:
	var rows: Array = UiFontGlyphs.GLYPHS[UP]
	assert_eq(rows.size(), UiFontGlyphs.ROWS, "CONTROL: a seven-row glyph")
	assert_eq(_widths(rows), [1, 3, 5], "a point, then two more columns on every row: no stem, no doubled row")


func test_the_down_triangle_is_the_up_one_turned_over() -> void:
	var flipped: Array = UiFontGlyphs.GLYPHS[UP].duplicate()
	flipped.reverse()
	assert_eq(UiFontGlyphs.GLYPHS[DOWN], flipped, "the pair sits on the same rows, so a scroll marker does not jump when it flips")


func test_the_measure_sees_a_stem() -> void:
	# CONTROL for the measure: the .807 drawing must fail it.
	assert_eq(_widths([".....", "..#..", "..#..", ".###.", ".###.", "#####", "....."]), [1, 1, 3, 3, 5], "the old rows read as a stem")
	assert_eq(_widths(["#.#", "###"]), [-1, 3], "a gapped row is not a triangle row")


func test_the_face_draws_the_table_rows_for_both() -> void:
	var f: FontFile = UiFont.display()
	var size := Vector2i(UiFont.nominal(), 0)
	var img: Image = f.get_texture_image(0, size, 0)
	for ch in [UP, DOWN]:
		var rows: Array = UiFontGlyphs.GLYPHS[ch]
		var r: Rect2 = f.get_glyph_uv_rect(0, size, ch.unicode_at(0))
		assert_eq(Vector2i(r.size), Vector2i(5, UiFontGlyphs.ROWS), "'%s' cell" % ch)
		var lit := 0
		var same := true
		for y in rows.size():
			for x in str(rows[y]).length():
				var on: bool = img.get_pixel(int(r.position.x) + x, int(r.position.y) + y).a > 0.5
				lit += int(on)
				if on != (str(rows[y])[x] == "#"):
					same = false
		assert_true(same, "'%s' in the built face is the table's rows" % ch)
		assert_eq(lit, 9, "CONTROL: '%s' lit 1 + 3 + 5 pixels" % ch)
