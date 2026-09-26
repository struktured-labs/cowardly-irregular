extends GutTest

## Settings → Text Size is "Scale dialogue text size". CutsceneDialogue multiplies
## speaker, body, and the continue hint through TextScale. BattleDialogue (boss
## intro, low-HP taunt, defeat line) kept 14/13/10, so 200% still drew the
## pre-fight lines at the default size — and simply scaling those three fonts
## paints the name through the line and the continue hint past the box.
## The panel grows with the same fonts, and 100% stays the 120px box.

var _saved_scale: float = 1.0


func before_each() -> void:
	if GameState and "text_size_scale" in GameState:
		_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	if GameState and "text_size_scale" in GameState:
		GameState.text_size_scale = _saved_scale


func _box() -> BattleDialogue:
	var box := BattleDialogue.new()
	add_child_autofree(box)
	return box


func _wrapped(text: String, font: Font, width: float, fsz: int) -> float:
	var tp := TextParagraph.new()
	tp.width = width
	tp.add_string(text, font, fsz)
	return tp.get_size().y


## A body that fits the 74px slot at 13px and does not fit that same slot at 26px.
func _body_that_overflows_the_unscaled_slot(width: float) -> String:
	var font := ThemeDB.fallback_font
	var text := ""
	for i in 40:
		text += "sovereign%d " % i
		var h13 := _wrapped(text, font, width, 13)
		var h26 := _wrapped(text, font, width, 26)
		if h13 <= 70.0 and h26 > 74.0:
			return text.strip_edges()
		if h13 > 70.0:
			break
	return ""


func test_one_hundred_percent_keeps_the_120px_boss_box() -> void:
	GameState.text_size_scale = 1.0
	var box := _box()
	box.show_boss_intro("Cave Rat King", ["Cave Rat King: Kneel, irregular."])
	assert_eq(box._speaker_label.get_theme_font_size("font_size"), 14,
		"100% speaker stays 14, the size the box was built around")
	assert_eq(box._text_label.get_theme_font_size("normal_font_size"), 13,
		"100% body stays 13")
	assert_eq(box._advance_hint.get_theme_font_size("font_size"), 10,
		"100% continue hint stays 10")
	assert_eq(int(box._dialogue_box.size.y), BattleDialogue.BOX_HEIGHT,
		"100% panel stays 120px tall")
	assert_eq(int(box._text_label.position.y), 28, "100% body stays at y=28")
	assert_eq(int(box._text_label.size.y), 74, "100% body slot stays 74px")
	assert_eq(int(box._advance_hint.position.y), int(box._dialogue_box.size.y) - 20,
		"100% hint stays 20px off the bottom")
	assert_eq(int(box._advance_hint.position.x), int(box._dialogue_box.size.x) - 150,
		"100% hint stays anchored 150px from the right")


func test_a_larger_text_size_enlarges_the_boss_line_and_keeps_it_in_the_box() -> void:
	var box := _box()
	GameState.text_size_scale = 2.0
	box.show_boss_intro("Cave Rat King", ["Cave Rat King: Hi."])
	var width := box._text_label.size.x
	var body := _body_that_overflows_the_unscaled_slot(width)
	assert_ne(body, "", "CONTROL: the fixture must be a line the 100% slot can hold and the unscaled 200% slot cannot")
	var font := ThemeDB.fallback_font
	assert_lte(_wrapped(body, font, width, 13), 70.0, "CONTROL: this line fits the 100% body")
	assert_gt(_wrapped(body, font, width, 26), 74.0, "CONTROL: this line does not fit the 74px body the box uses at 100%")

	box.show_boss_intro("Cave Rat King", ["Cave Rat King: %s" % body])
	assert_eq(box._speaker_label.get_theme_font_size("font_size"), TextScale.scaled(14),
		"the boss name must use Text Size, the same helper cutscene dialogue uses")
	assert_eq(box._text_label.get_theme_font_size("normal_font_size"), TextScale.scaled(13),
		"the boss line must use Text Size")
	assert_eq(box._advance_hint.get_theme_font_size("font_size"), TextScale.scaled(10),
		"the continue hint must use Text Size")
	assert_gt(int(box._dialogue_box.size.y), BattleDialogue.BOX_HEIGHT,
		"the panel must grow, or the larger glyphs have nowhere to go")

	var speaker := box._speaker_label
	var speaker_font := speaker.get_theme_font("font")
	var speaker_px := speaker.get_theme_font_size("font_size")
	assert_lte(speaker.position.y + speaker_font.get_height(speaker_px), box._text_label.position.y + 1.0,
		"the boss name must sit above the line, not through it")

	var shaped := _wrapped(body, box._text_label.get_theme_font("normal_font"), width, box._text_label.get_theme_font_size("normal_font_size"))
	assert_lte(shaped, box._text_label.size.y, "the boss line must fit inside the body slot")
	assert_lte(box._text_label.position.y + box._text_label.size.y, box._dialogue_box.size.y,
		"the body slot must stay inside the panel")

	var hint := box._advance_hint
	var hint_font := hint.get_theme_font("font")
	var hint_px := hint.get_theme_font_size("font_size")
	var hint_w := hint_font.get_string_size(hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hint_px).x
	assert_lte(hint.position.y + hint_font.get_height(hint_px), box._dialogue_box.size.y - float(BattleDialogue.TILE_SIZE),
		"the continue hint must stay above the bottom border")
	assert_lte(hint.position.x + hint_w, box._dialogue_box.size.x - float(BattleDialogue.TILE_SIZE),
		"the continue hint must stay inside the right border")
	assert_gte(hint.position.x, float(BattleDialogue.TILE_SIZE),
		"the continue hint must stay inside the left border")


func test_the_smaller_text_size_shrinks_the_font_and_keeps_the_panel() -> void:
	GameState.text_size_scale = 0.8
	var box := _box()
	box.show_boss_intro("Cave Rat King", ["Cave Rat King: Kneel, irregular."])
	assert_eq(box._text_label.get_theme_font_size("normal_font_size"), TextScale.scaled(13),
		"80% must shrink the boss line")
	assert_eq(box._speaker_label.get_theme_font_size("font_size"), TextScale.scaled(14))
	assert_eq(box._advance_hint.get_theme_font_size("font_size"), TextScale.scaled(10))
	assert_eq(int(box._dialogue_box.size.y), BattleDialogue.BOX_HEIGHT,
		"80% keeps the 120px panel; smaller glyphs fit the existing slots")
	assert_eq(int(box._text_label.position.y), 28)
	assert_eq(int(box._text_label.size.y), 74)
