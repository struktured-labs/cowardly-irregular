extends GutTest

## Quest Log stacked every objective 20px apart while Text Size grew the font, and clip_text
## kept each glyph in a box that ran through the line below. Chapter headers are the tallest
## body line. At 100% the drawn glyph is already taller than 20px; at 200% it is about twice that.

var _saved_scale: float = 1.0


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale


func _glyph(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	var fsz := label.get_theme_font_size("font_size")
	return font.get_string_size("Ag", HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).y


func _open(scale: float) -> QuestLog:
	GameState.text_size_scale = scale
	var ql := QuestLog.new()
	add_child_autofree(ql)
	ql._build_ui()
	return ql


func _labeled(ql: QuestLog, fragment: String) -> Label:
	for c in ql.get_children():
		if c is Label and str(c.text).contains(fragment):
			return c
	return null


func _quest_rows(ql: QuestLog) -> Array[Label]:
	var rows: Array[Label] = []
	for c in ql.get_children():
		if c is Label and (c as Label).clip_text and str((c as Label).text) != "":
			rows.append(c)
	rows.sort_custom(func(a: Label, b: Label) -> bool: return a.position.y < b.position.y)
	return rows


func test_default_text_does_not_draw_the_chapter_title_through_the_next_line() -> void:
	var ql := _open(1.0)
	var rows := _quest_rows(ql)
	assert_gt(rows.size(), 1, "the log must paint a chapter title and the objective under it")
	var header := rows[0]
	assert_true(str(header.text).contains("Chapter 1"), "the first row must be the chapter title")
	var ink := _glyph(header)
	assert_gt(ink, 20.0, "control: a 15px chapter title already draws taller than the old 20px pitch")
	assert_gte(rows[1].position.y, header.position.y + ink - 0.5,
		"the next objective starts inside the chapter title")
	assert_true(header.clip_text, "a long objective still stops at the panel edge")


func test_huge_text_keeps_lines_the_banner_and_the_footer_apart() -> void:
	var ql := _open(2.0)
	var rows := _quest_rows(ql)
	assert_gt(rows.size(), 2, "control: clipped quest lines must exist or the overlap check says nothing")
	for i in range(1, rows.size()):
		var prev := rows[i - 1]
		var cur := rows[i]
		assert_gte(cur.position.y, prev.position.y + _glyph(prev) - 0.5,
			"'%s' is drawn through the line above it" % str(cur.text).substr(0, 32))
	var title := _labeled(ql, "QUEST LOG")
	var banner := ql.get_node_or_null("NextBanner") as Label
	var footer := _labeled(ql, "Page")
	assert_not_null(title, "the title must be on screen")
	assert_not_null(banner, "the Next banner must be on screen")
	assert_not_null(footer, "the footer must be on screen")
	assert_gte(banner.position.y, title.position.y + _glyph(title) - 0.5,
		"QUEST LOG runs into the Next line at 200%")
	assert_gte(rows[0].position.y, banner.position.y + _glyph(banner) - 0.5,
		"the first objective runs into the Next line at 200%")
	var vp_h := ql.get_viewport().get_visible_rect().size.y
	if vp_h <= 0.0:
		vp_h = 480.0
	assert_lte(footer.position.y + _glyph(footer), vp_h + 0.5,
		"the footer hint is cut off by the bottom of the screen at 200%")
