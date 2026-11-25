extends GutTest

## MenuChrome placed every menu title, counter and footer (Bestiary, Equipment, Items, Party Status, Settings, Status,
## Shop), and fitted a long one by SHRINKING its font, down to 65% of its authored px, before wrapping. The ruling is
## that text grows, wraps or scrolls and never shrinks. Each helper now keeps the label's own px and wraps; a footer
## that needs more height than its slot grows UP from the slot's bottom instead of shrinking or clipping.
##
## ⛔ Fit is judged with each label's own layout (line count x line height, its rect), never with a font query.

const LONG := "Shift+Up/Down or the Right Stick: scroll the entry   Z/Enter: open   X/Esc: back to the field   Tab: next page"

var _host: Control = null
var _saved_scale = null


func before_each() -> void:
	_saved_scale = GameState.text_size_scale
	_host = Control.new()
	_host.size = Vector2(1280, 720)
	add_child_autofree(_host)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale


func _label(text: String, px: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	_host.add_child(l)
	return l


func _one_line_w(l: Label) -> float:
	return l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x


func _drawn_h(l: Label) -> float:
	return l.get_line_count() * l.get_line_height()


func test_a_title_too_wide_wraps_at_its_own_size() -> void:
	var t := _label(LONG, 28)
	var c := _label("12 / 120 seen", 28)
	var bottom := MenuChrome.place_header(t, c, 640.0, 16.0, false, 16.0)
	assert_gt(_one_line_w(t), 640.0 - 32.0, "CONTROL: on one line the title is wider than the header")
	assert_eq(t.get_theme_font_size("font_size"), 28, "the title keeps its px (was cut to as little as 65%)")
	assert_eq(c.get_theme_font_size("font_size"), 28, "the counter keeps its px")
	assert_gt(t.get_line_count(), 1, "so the title wraps")
	assert_lte(t.position.x + t.size.x, 640.0 - 16.0 + 0.5, "and stays inside the header")
	assert_lte(t.position.y + _drawn_h(t), bottom + 0.5, "the content below starts under every title line")
	assert_lte(c.position.x + c.size.x, 640.0 - 16.0 + 0.5, "the counter stays inside the header")


func test_a_title_that_fits_is_placed_as_before() -> void:
	var t := _label("Bestiary", 20)
	var c := _label("3 / 40", 20)
	var bottom := MenuChrome.place_header(t, c, 1280.0, 16.0, false, 24.0)
	var tw := t.get_minimum_size()
	assert_eq(t.get_theme_font_size("font_size"), 20, "px unchanged")
	assert_eq(t.get_line_count(), 1, "one line")
	assert_eq(t.position, Vector2(24, 16), "the title sits at the margin")
	assert_eq(c.position.x, 1280.0 - 24.0 - c.size.x, "the counter sits at the right margin")
	assert_almost_eq(bottom, 16.0 + maxf(tw.y, c.size.y), 0.5, "the row is one line tall")


func test_a_long_footer_wraps_at_its_own_size_and_is_not_cut() -> void:
	var f := _label(LONG, 28)
	var r := MenuChrome.place_footer(f, Vector2(640, 720), 16.0)
	assert_gt(_one_line_w(f), 640.0 - 32.0, "CONTROL: on one line the footer is wider than its row")
	assert_eq(f.get_theme_font_size("font_size"), 28, "the footer keeps its px")
	assert_gt(f.get_line_count(), 1, "so it wraps")
	assert_false(f.clip_text, "and nothing is clipped")
	assert_lte(_drawn_h(f), r.size.y + 0.5, "every line fits the footer's height")
	assert_lte(r.end.y, 720.0 - 16.0 + 0.5, "the footer ends inside the screen margin")


func test_new_words_in_a_short_slot_grow_up_not_down() -> void:
	var f := _label("Back", 28)
	f.set_meta(&"footer_font", 28)
	var slot := Rect2(16, 660, 608, 40)
	f.text = LONG
	MenuChrome.fit_footer_text(f, slot)
	assert_eq(f.get_theme_font_size("font_size"), 28, "the footer keeps its px")
	assert_false(f.clip_text, "nothing is clipped")
	assert_gt(f.size.y, slot.size.y, "CONTROL: the words need more than the slot")
	assert_almost_eq(f.position.y + f.size.y, slot.end.y, 0.5, "the footer still ends at the slot's bottom (it grew up)")
	assert_lte(_drawn_h(f), f.size.y + 0.5, "and every line fits")


func test_words_that_fit_the_slot_keep_the_slot() -> void:
	var f := _label("Back", 14)
	f.set_meta(&"footer_font", 14)
	var slot := Rect2(16, 660, 608, 40)
	MenuChrome.fit_footer_text(f, slot)
	assert_eq(Rect2(f.position, f.size), slot, "a footer that fits is exactly its slot")
	assert_eq(f.get_theme_font_size("font_size"), 14, "at its own px")


func test_the_bestiary_chrome_keeps_the_text_size() -> void:
	for s in [1.0, 2.0, 2.5]:
		GameState.text_size_scale = s
		var vp := SubViewport.new()
		vp.size = Vector2i(1280, 720)
		add_child_autofree(vp)
		var m: Control = load("res://src/ui/BestiaryMenu.gd").new()
		vp.add_child(m)
		await get_tree().process_frame
		await get_tree().process_frame
		var f: Label = m._footer
		assert_not_null(f, "CONTROL @%s: the bestiary has its footer" % s)
		if f == null:
			continue
		assert_eq(f.get_theme_font_size("font_size"), TextScale.scaled(14), "@%s: the footer is drawn at the Text Size" % s)
		assert_false(f.clip_text, "@%s: the footer is not clipped" % s)
		assert_lte(f.position.y + _drawn_h(f), 720.0 + 0.5, "@%s: the footer ends on screen" % s)
		m.queue_free()
