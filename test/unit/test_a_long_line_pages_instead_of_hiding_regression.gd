extends GutTest

## `clip_contents` + BOX_HEIGHT 120->150 (ec2295a, pinned in test_dialogue_clip_regression) stopped
## long dialogue BLEEDING out of the box. It did not make the overflow readable: nothing in
## CutsceneDialogue scrolls the body — `scroll_active` flips true after typing, which is the mouse
## wheel, and this game is pad-first ("NO MOUSE/CLICKING required") — so the hidden tail was simply
## lost. Measured 2026-09-16 against the real box (1140x104 at 1280, font 16): 1 of 3276 authored
## strings overflowed by 34px (world5_chapter3), 3 of 3276 at a 960 window. Long lines now PAGE.

const DialogueScript = preload("res://src/cutscene/CutsceneDialogue.gd")

var _box: Node
var _advanced: int = 0


func before_each() -> void:
	Input.action_release("ui_accept")
	_advanced = 0
	_box = DialogueScript.new()
	add_child_autofree(_box)
	_box.dialogue_advanced.connect(func(): _advanced += 1)


func after_each() -> void:
	Input.action_release("ui_accept")


func _line(text: String) -> Array:
	return [{"speaker": "Fighter", "text": text, "theme": "fighter", "portrait": "fighter"}]


## Long enough to overflow any sane box; built from DISTINCT words so two pages can never be
## mistaken for each other (an identical-words fixture made the page-turn assert unfalsifiable).
func _long_text() -> String:
	var words: PackedStringArray = PackedStringArray()
	for i in 160:
		words.append("consequence%d" % i)
	return " ".join(words)


## ⛔ `RichTextLabel.get_content_height()` is NOT usable as an oracle headless: with no render pass
## it returned 23px (one line) for pages that wrap to four, for 3 of 5 pages and not the other 2 —
## so a fit arm built on it passes on anything and a packing arm fails on a correct split. Measured
## 2026-09-16. `TextParagraph` is the shaper itself, synchronous and identical run to run (92.0 x3).
## It agrees to the pixel with the splitter's own `Font.get_multiline_string_size`, so these are
## CONSISTENCY arms — they cannot catch the shaper disagreeing with the screen, only the split
## disagreeing with the shaper. A rendered probe is the only instrument for the former.
func _wrapped_height(text: String) -> float:
	var rtl: RichTextLabel = _box._text_label
	var tp := TextParagraph.new()
	tp.width = rtl.size.x
	tp.add_string(text, rtl.get_theme_font("normal_font"), _box._scaled_font_size(16))
	return tp.get_size().y


func _page_fits(page: String) -> bool:
	return _wrapped_height(page) <= _box._text_label.size.y


func test_a_line_that_overflows_is_split_into_pages() -> void:
	_box.show_dialogue(_line(_long_text()))
	assert_gt(_box._pages.size(), 1,
		"a line taller than the box must page; one page means the tail is still hidden")


## Every page must actually fit — a split that still overflows moves the loss rather than fixing it.
func test_every_page_fits_the_box() -> void:
	_box.show_dialogue(_line(_long_text()))
	var pages: PackedStringArray = _box._pages
	assert_gt(pages.size(), 1, "PRECONDITION: the fixture must page, else nothing is measured")
	for i in pages.size():
		var fits: bool = _page_fits(pages[i])
		assert_true(fits, "page %d of %d must fit the box by the label's own layout" % [i + 1, pages.size()])


## Pages must be FULL, not merely valid: a split that fits by breaking every word satisfies every
## arm above and costs the player 40 presses to read one line. Greedy = the next page's first word
## would not have fitted.
func test_each_page_is_packed_not_dribbled() -> void:
	_box.show_dialogue(_line(_long_text()))
	var pages: PackedStringArray = _box._pages
	assert_gt(pages.size(), 1, "PRECONDITION: the fixture must page")
	var box_h: float = _box._text_label.size.y
	for i in pages.size() - 1:
		var next_word: String = pages[i + 1].split(" ")[0]
		assert_gt(_wrapped_height(pages[i] + " " + next_word), box_h,
			"page %d of %d could still have taken the next page's first word (%.0f of %.0f px) — packed, not dribbled" % [
				i + 1, pages.size(), _wrapped_height(pages[i]), box_h])


## CONTROL: the whole line must NOT fit, or every assert above is free.
func test_control_the_unpaged_line_would_not_fit() -> void:
	_box.show_dialogue(_line(_long_text()))
	var fits: bool = _page_fits(_long_text())
	assert_false(fits, "the fixture must overflow the real box, else this file guards nothing")


## Nothing is dropped or duplicated in the split.
func test_the_pages_carry_the_whole_line() -> void:
	_box.show_dialogue(_line(_long_text()))
	var joined: String = " ".join(_box._pages)
	assert_eq(joined, _long_text(), "the pages joined back must be the authored line, word for word")


## A page turn is not a line advance: same queue entry, no dialogue_advanced, portrait untouched.
func test_advancing_turns_the_page_before_it_leaves_the_line() -> void:
	_box.show_dialogue(_line(_long_text()))
	_box._finish_typing()
	var first: String = _box._current_text
	_box._advance_dialogue()
	assert_eq(_box._page_index, 1, "the first advance past a typed page must turn the page")
	assert_ne(_box._current_text, first, "and show the next page's text")
	assert_eq(_box._current_index, 0, "the queue must NOT move while pages remain")
	assert_eq(_advanced, 0, "dialogue_advanced belongs to a LINE; a page turn must not emit it")


## And the last page still hands the line back, so a paged line cannot trap the scene.
func test_the_last_page_advances_the_line() -> void:
	_box.show_dialogue(_line(_long_text()))
	var pages: int = _box._pages.size()
	assert_gt(pages, 1, "PRECONDITION: the fixture must page")
	for i in pages - 1:
		_box._finish_typing()
		_box._advance_dialogue()
		assert_eq(_advanced, 0, "page %d of %d must not have left the line" % [i + 2, pages])
	_box._finish_typing()
	_box._advance_dialogue()
	# The queue had one entry, so leaving it ends the dialogue — _finish_dialogue resets the index and hides the box, which is why the index itself proves nothing here.
	assert_eq(_advanced, 1, "exactly one line advance for one line, however many pages it took")
	assert_false(_box.visible, "and the box closes when the last page is advanced off the last line")


## The overwhelming case is untouched: a short line is one page and behaves as it always did.
func test_a_short_line_is_one_page() -> void:
	_box.show_dialogue(_line("Does it smell like dragon in there?"))
	assert_eq(_box._pages.size(), 1, "a line that fits must not be paged")
	_box._finish_typing()
	_box._advance_dialogue()
	assert_eq(_advanced, 1, "and its first advance must leave the line")


## A paged line must SAY so — a full box and a continued box look identical otherwise.
func test_a_paged_line_advertises_its_pages() -> void:
	_box.show_dialogue(_line(_long_text()))
	_box._finish_typing()
	assert_true("(1/%d)" % _box._pages.size() in _box._advance_hint.text,
		"the hint must carry the page counter: %s" % _box._advance_hint.text)
	_box.show_dialogue(_line("Short."))
	_box._finish_typing()
	assert_false("(1/" in _box._advance_hint.text,
		"and an unpaged line must not grow a counter: %s" % _box._advance_hint.text)


## THE CORPUS: no authored string may hide part of itself. Property, not a pin — if authors shorten
## everything this stays true, and the fixture arms above keep the guard honest.
func test_no_authored_line_hides_its_tail() -> void:
	_box.show_dialogue(_line("Building the real box so pagination measures the real width."))
	var dir := DirAccess.open("res://data/cutscenes")
	assert_not_null(dir, "the cutscene corpus must be readable")
	if dir == null:
		return
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	var worst_pages: PackedStringArray = PackedStringArray()
	var worst_file: String = ""
	var checked: int = 0
	for f in names:
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/" + f))
		if not (d is Dictionary):
			continue
		for s in d.get("steps", []):
			if not (s is Dictionary):
				continue
			for t in _strings_of(s):
				if t.is_empty():
					continue
				checked += 1
				var pages: PackedStringArray = _box._paginate(t)
				assert_eq(" ".join(pages), t, "%s: pagination must not alter an authored line" % f)
				if pages.size() > worst_pages.size():
					worst_pages = pages
					worst_file = f
	gut.p("authored strings paginated: %d · deepest %d pages (%s)" % [checked, worst_pages.size(), worst_file])
	assert_gt(checked, 1000, "PRECONDITION: the corpus must actually load, else this is vacuous")
	# The deepest authored string goes through the label's own layout, not the font call that split it.
	for i in worst_pages.size():
		var fits: bool = _page_fits(worst_pages[i])
		assert_true(fits, "%s page %d/%d must fit the real box" % [worst_file, i + 1, worst_pages.size()])


func _strings_of(step: Dictionary) -> Array:
	var out: Array = []
	if step.has("text"):
		out.append(str(step["text"]))
	if step.has("prompt"):
		out.append(str(step["prompt"]))
	var lines = step.get("lines", null)
	if lines is Array:
		for it in lines:
			out.append(str(it.get("text", "")) if it is Dictionary else str(it))
	return out
