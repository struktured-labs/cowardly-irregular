extends GutTest

## `BattleDialogue` set `scroll_active = false` and `clip_contents = true` and had NO paging, so a
## line taller than the body was silently CUT — the player simply never saw the tail.
##
## `CutsceneDialogue`, whose own header calls it "adapted from BattleDialogue", grew paging for
## exactly this hazard (`test_a_long_line_pages_instead_of_hiding_regression`) and the original was
## left behind. Same lineage, same clip-without-scroll shape, one of the two fixed.
##
## ⚠️ WHAT THIS DOES AND DOES NOT CLAIM, because the first version of this file claimed more.
## I wrote that this surface shows LLM boss lines bounded only by `max_tokens`. It does not:
## `BossDialogue`'s API is authored-data getters over `boss_dialogue.json`, and LLM taunts go to a
## separate bubble over the boss sprite. Measured against the real box, 0 of 382 authored boss
## lines overflow at ALL FIVE Text Size presets. So these arms guard a LATENT loss, reached by
## writing a longer line — which the sibling's guard shows happens (1 of 3276 of its strings was
## already over its box). The arms are behavioural and mutation-checked; the exposure is not live.
##
## ⛔ `RichTextLabel.get_content_height()` IS NOT AN ORACLE HEADLESS. The sibling guard measured it
## returning 23px (one line) for pages that wrap to four, for 3 of 5 pages and not the other 2 — so
## an arm built on it passes on anything. `TextParagraph` is the shaper itself, synchronous and
## stable run to run, and that is what these arms use.
##
## ⚠️ SCOPE, stated because the instrument bounds it: `TextParagraph` agrees to the pixel with the
## splitter's own `Font.get_multiline_string_size`, so these are CONSISTENCY arms. They catch the
## SPLIT disagreeing with the shaper; they cannot catch the shaper disagreeing with the screen. Only
## a rendered probe does the latter.

const DialogueScript = preload("res://src/ui/BattleDialogue.gd")

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
	return [{"speaker": "Dark Knight", "text": text, "theme": "enemy", "portrait": "enemy"}]


## Built from DISTINCT words so two pages can never be mistaken for each other — an
## identical-words fixture makes the page-turn assert unfalsifiable.
func _long_text() -> String:
	var words: PackedStringArray = PackedStringArray()
	for i in 160:
		words.append("consequence%d" % i)
	return " ".join(words)


## The shaper, not the label's own cached layout.
func _wrapped_height(text: String) -> float:
	var rtl: RichTextLabel = _box._text_label
	var fsz: int = rtl.get_theme_font_size("normal_font_size")
	if fsz <= 0:
		fsz = 13
	var tp := TextParagraph.new()
	tp.width = rtl.size.x
	tp.add_string(text, rtl.get_theme_font("normal_font"), fsz)
	return tp.get_size().y


func _page_fits(page: String) -> bool:
	return _wrapped_height(page) <= _box._text_label.size.y


func test_control_the_unpaged_line_would_not_fit() -> void:
	## Without this every assert below is free.
	_box.show_dialogue(_line(_long_text()))
	assert_false(_page_fits(_long_text()),
		"the fixture must overflow the real box, else this file guards nothing")


func test_control_a_short_line_is_not_paged() -> void:
	## The fix must not page text that already fits — a one-line boss barb must not grow a (1/2).
	_box.show_dialogue(_line("You should not have come here."))
	assert_eq(_box._pages.size(), 1,
		"a line that fits must stay on one page, got %d" % [_box._pages.size()])


func test_a_line_that_overflows_is_split_into_pages() -> void:
	## THE DEFECT. One page means the tail is still hidden behind clip_contents.
	_box.show_dialogue(_line(_long_text()))
	assert_gt(_box._pages.size(), 1,
		"a line taller than the box must page; one page means the tail is still cut")


func test_every_page_fits_the_box() -> void:
	## A split that still overflows moves the loss rather than fixing it.
	_box.show_dialogue(_line(_long_text()))
	var pages: PackedStringArray = _box._pages
	assert_gt(pages.size(), 1, "PRECONDITION: the fixture must page, else nothing is measured")
	for i in pages.size():
		assert_true(_page_fits(pages[i]),
			"page %d of %d must fit the box by the shaper's own layout" % [i + 1, pages.size()])


func test_each_page_is_packed_not_dribbled() -> void:
	## Pages must be FULL, not merely valid: a split that breaks every word satisfies every arm
	## above and costs the player 160 presses to read one line.
	_box.show_dialogue(_line(_long_text()))
	var pages: PackedStringArray = _box._pages
	assert_gt(pages.size(), 1, "PRECONDITION: the fixture must page")
	var box_h: float = _box._text_label.size.y
	for i in pages.size() - 1:
		var next_word: String = pages[i + 1].split(" ")[0]
		assert_gt(_wrapped_height(pages[i] + " " + next_word), box_h,
			"page %d of %d could still have taken the next page's first word — packed, not dribbled" % [
				i + 1, pages.size()])


func test_the_pages_carry_the_whole_line() -> void:
	## Nothing dropped, nothing duplicated: the split is a partition of the words.
	_box.show_dialogue(_line(_long_text()))
	var rejoined: String = " ".join(_box._pages)
	assert_eq(rejoined, _long_text(),
		"the pages must rejoin to exactly the line that was given")


func test_a_page_turn_is_not_a_new_line() -> void:
	## `dialogue_advanced` drives callers (voice, portraits, battle flow). Firing it on a page turn
	## would make one long boss line look like several lines to everything downstream.
	_box.show_dialogue(_line(_long_text()))
	assert_gt(_box._pages.size(), 1, "PRECONDITION: the fixture must page")
	var before: int = _advanced
	_box._advance_dialogue()   # finishes typing
	_box._advance_dialogue()   # turns the page
	assert_eq(_box._page_index, 1, "the second advance must turn the page")
	assert_eq(_advanced, before,
		"a page turn must not emit dialogue_advanced (got %d emissions)" % [_advanced - before])


func test_a_paged_line_says_which_page_it_is_on() -> void:
	## Without a counter the player cannot tell a full box from a continued one, and stops reading.
	_box.show_dialogue(_line(_long_text()))
	assert_gt(_box._pages.size(), 1, "PRECONDITION: the fixture must page")
	_box._advance_dialogue()   # finish typing so the hint is populated
	var hint: String = _box._advance_hint.text
	assert_true(hint.find("(1/%d)" % _box._pages.size()) != -1,
		"the advance hint must say which page of how many, got '%s'" % [hint])
