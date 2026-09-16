extends GutTest

## The Quest Log scrolls 33 quests three lines at a time and had no fast scroll. struktured asked
## for one on 2026-07-25 ("should be a fast scroll down feature in menus"); MenuPaging was built for
## it and reached 3 of 16 list menus. This is the Quest Log's share.
##
## It scrolls by LINES, not selectable rows, so a page is a screenful (_max_visible_lines) rather
## than MenuPaging.PAGE_ROWS, which counts rows in the menus that select one. Clamped, never wrapped.
##
## ⚠️ WHAT THIS GUARD CANNOT DO, stated because it changes what a green here means.
## QuestLog builds its content from `get_viewport_rect().size`, and headless that is 0×0:
##     total_lines=0  max_visible=0  scroll=0   — measured, no UI children at all
## So the log can never scroll in this harness and NO behavioural arm on it is possible: a page
## press moves 0 whether the feature exists or not. Driving it with stubbed line counts does not
## help either — the page path calls _build_ui(), which recomputes both counts from real data and
## re-clamps the offset, so the stub is gone before the assert reads it.
##
## The page ARITHMETIC is therefore pinned at the source, through the comment-stripped body with a
## surviving-code-site control. The shared helper it depends on IS driven, behaviourally, below.

const QUEST_LOG := "res://src/ui/QuestLog.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func _input_body() -> String:
	var src := GdSource.code_of(QUEST_LOG)
	assert_true(src.find("func _input") > -1, "POSITIVE CONTROL: _input must survive stripping")
	var at := src.find("func _input")
	if at < 0:
		return ""
	var stop := src.find("\nfunc ", at + 10)
	return src.substr(at, stop - at) if stop > at else src.substr(at)


## ⛔ THE SHARED HELPER, driven for real — this half needs no viewport.
func test_the_page_helper_answers_both_directions() -> void:
	var up := InputEventKey.new()
	up.keycode = KEY_PAGEUP
	up.physical_keycode = KEY_PAGEUP
	up.pressed = true
	var down := InputEventKey.new()
	down.keycode = KEY_PAGEDOWN
	down.physical_keycode = KEY_PAGEDOWN
	down.pressed = true
	assert_eq(MenuPaging.page_delta(up), -1, "PageUp must page backwards")
	assert_eq(MenuPaging.page_delta(down), 1, "PageDown must page forwards")
	var other := InputEventKey.new()
	other.keycode = KEY_J
	other.physical_keycode = KEY_J
	other.pressed = true
	assert_eq(MenuPaging.page_delta(other), 0,
		"CONTROL: an unrelated key must not page, or the arms above say nothing")


## An echo must not page — holding the key would fly through the log.
func test_a_held_key_does_not_page_repeatedly() -> void:
	var echo := InputEventKey.new()
	echo.keycode = KEY_PAGEDOWN
	echo.physical_keycode = KEY_PAGEDOWN
	echo.pressed = true
	echo.echo = true
	assert_eq(MenuPaging.page_delta(echo), 0, "an auto-repeat echo must not count as a page press")


## ⛔ THE FEATURE, pinned at the source because the harness cannot render it.
func test_the_quest_log_consults_the_shared_pager() -> void:
	var body := _input_body()
	assert_gt(body.length(), 200, "POSITIVE CONTROL: the _input body must be read")
	assert_true(body.find("MenuPaging.page_delta(event)") > -1,
		"the Quest Log must ask the SHARED pager — a step of its own is the second-copy shape " +
		"that had restore_mp carrying its own item values")


## A page is a screenful of THIS log's lines, and it is clamped at both ends.
func test_the_page_is_a_screenful_and_is_clamped() -> void:
	var body := _input_body()
	assert_true(body.find("_max_visible_lines") > -1,
		"a page here must be a screenful of lines — PAGE_ROWS counts rows, and this log has none")
	## ⛔ The ABSENCE is what pins the unit. The assert above passes on _max_visible_lines appearing
	## ANYWHERE in the body — and it also appears on the clamp line — so swapping the page STEP to
	## PAGE_ROWS left it green. Predicted a red, got a green; the arm was weaker than its name.
	assert_eq(body.find("PAGE_ROWS"), -1,
		"PAGE_ROWS counts selectable ROWS; this log has none and scrolls by LINES, so paging by it " +
		"would move a fixed 10 lines regardless of how much text is on screen")
	assert_true(body.find("clampi(") > -1,
		"the jump must be clamped, not wrapped: paging past the last line is the defect this " +
		"would otherwise introduce")
	assert_true(body.find("_total_lines - _max_visible_lines") > -1,
		"…and clamped to the LAST SCREENFUL, so the final page is full rather than past the end")


## ⛔ The control must be ADVERTISED and DERIVED. MenuPaging binds battle_defer/battle_advance, which
## the three families print as L/LB/L1 and R/RB/R1 — a literal is right on one pad only, and four
## footers shipped exactly that mistake until aabe8bb8.
func test_the_footer_advertises_the_pager_and_derives_it() -> void:
	var src := GdSource.code_of(QUEST_LOG)
	var at := src.find("footer.text")
	assert_gt(at, -1, "the Quest Log must still have a footer legend")
	var line := src.substr(at, 320)
	assert_true(line.find("Page") > -1, "the page control must be advertised at all")
	assert_true(line.find('hint_for_action("battle_defer")') > -1
			and line.find('hint_for_action("battle_advance")') > -1,
		"both page tokens must be DERIVED per connected pad")
	for frozen in ["L1", "LB", "R1", "RB"]:
		assert_eq(line.find(frozen), -1,
			"'%s' is one family's name for that shoulder — the footer must not print it" % frozen)
