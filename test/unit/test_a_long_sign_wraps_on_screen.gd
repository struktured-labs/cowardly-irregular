extends GutTest

## Regression (cowir-main's Backwards Warren frame): "Sealed wing. The keys are also in the sealed wing. Efficient,
## everyone agreed, before agreeing to seal it." ran off the right edge of the screen. A Signpost label was one
## auto-width line in the world and one viewport-wide unwrapped line in Mode 7. Both now wrap.

const LONG := "Sealed wing. The keys are also in the sealed wing. Efficient, everyone agreed, before agreeing to seal it."


func _sign(text: String) -> Signpost:
	var s := Signpost.new()
	s.sign_text = text
	add_child_autofree(s)
	return s


func _line_height(l: Label) -> float:
	return l.get_theme_font("font").get_height(l.get_theme_font_size("font_size"))


func test_a_long_world_sign_wraps_within_its_width() -> void:
	var s := _sign(LONG)
	await get_tree().process_frame
	await get_tree().process_frame
	var l: Label = s._label
	assert_eq(l.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "a lore sign wraps")
	assert_lte(l.size.x, Signpost.FLAT_WIDTH + 0.5, "and stays inside FLAT_WIDTH")
	assert_gt(l.get_minimum_size().y, _line_height(l) * 1.5, "SCOPE: the long line really did wrap onto several")


func test_a_short_sign_stays_one_line() -> void:
	var s := _sign("→ Village")
	await get_tree().process_frame
	await get_tree().process_frame
	var l: Label = s._label
	assert_lt(l.get_minimum_size().y, _line_height(l) * 1.5, "CONTROL: a short direction sign is still one line")


func test_a_mode7_prompt_wraps_inside_the_screen() -> void:
	var l := Label.new()
	l.text = LONG
	l.add_theme_font_size_override("font_size", Mode7Prompt.FONT_SIZE)
	add_child_autofree(l)
	var vp := Vector2(1280, 720)
	Mode7Prompt.place(l, vp, Mode7Prompt.ROW_INFO)
	await get_tree().process_frame
	assert_gte(l.position.x, 0.0, "the prompt starts on screen")
	assert_lte(l.position.x + l.size.x, vp.x, "and ends on screen")
	assert_eq(l.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "a long prompt wraps rather than running past the edge")


func test_a_sign_at_the_top_of_the_screen_reads_below_its_post() -> void:
	var s := _sign(LONG)
	s.position = Vector2(400, 8)
	await get_tree().process_frame
	await get_tree().process_frame
	s._keep_flat_label_on_screen()
	var top: float = s._label.get_global_transform_with_canvas().origin.y
	assert_gte(top, 0.0, "a wrapped sign near the top edge must not start above the screen (top %.0f)" % top)
