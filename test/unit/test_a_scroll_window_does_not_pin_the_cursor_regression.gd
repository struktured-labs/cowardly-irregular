extends GutTest

## Four list menus computed their scroll window as `max(0, selected - visible + 1)`. That keeps the
## selection on screen — the thing the comments claimed — and does it by pinning the cursor to the
## BOTTOM row for the entire back half of a list: past the first screenful the window moves on every
## single step, and the rows BELOW the cursor are never visible. Walking back up drags the window up
## one row at a time with the cursor still glued to the bottom edge.
##
## Sites: EquipmentMenu (item list) · JobMenu (job list) · AbilitiesMenu (abilities AND passives).
##
## A window can only know whether the selection is still inside it if it remembers where it was, so
## the fix is stateful: MenuScroll.window_offset takes the caller's previous offset and moves it only
## when the selection has left. Each menu now stores one int per list.
##
## MenuScroll is pure, so every arm below drives the real function — no source pinning needed for the
## arithmetic. The last two arms pin the CALL SITES, which is the half a unit test cannot reach.

const VISIBLE := 6
const TOTAL := 20

var GdSource = load("res://test/unit/helpers/gd_source.gd")


## The old formula, kept as the thing being defended against rather than described in prose.
func _pinned(selected: int) -> int:
	return maxi(0, selected - VISIBLE + 1)


func test_the_first_screenful_does_not_move_the_window() -> void:
	var offset := 0
	for selected in range(VISIBLE):
		offset = MenuScroll.window_offset(selected, VISIBLE, TOTAL, offset)
		assert_eq(offset, 0, "selection %d is inside the first screenful; the window must not move" % selected)


func test_the_window_follows_only_when_the_selection_leaves_it() -> void:
	var offset := 0
	offset = MenuScroll.window_offset(VISIBLE, VISIBLE, TOTAL, offset)
	assert_eq(offset, 1, "the first selection past the window moves it by exactly one row")
	offset = MenuScroll.window_offset(VISIBLE + 1, VISIBLE, TOTAL, offset)
	assert_eq(offset, 2, "each further step past the bottom edge moves it by one")


## THE LOAD-BEARING ARM. Descend, then walk back up: the window must sit still until the cursor
## reaches its top row. Under the old formula every one of these steps moved it.
func test_walking_back_up_does_not_drag_the_window() -> void:
	var offset := 0
	for selected in range(13):
		offset = MenuScroll.window_offset(selected, VISIBLE, TOTAL, offset)
	assert_eq(offset, 7, "descending to 12 leaves the window at 7")

	var moved := 0
	for selected in range(11, 6, -1):
		var before := offset
		offset = MenuScroll.window_offset(selected, VISIBLE, TOTAL, offset)
		if offset != before:
			moved += 1
		assert_eq(offset, 7, "selection %d is still inside the window; it must not move" % selected)
		assert_ne(offset, _pinned(selected), "selection %d must not be pinned to the bottom row" % selected)
	assert_eq(moved, 0, "five upward steps inside the window move it zero times")

	offset = MenuScroll.window_offset(6, VISIBLE, TOTAL, offset)
	assert_eq(offset, 6, "reaching the top row of the window finally moves it, by one")


func test_the_cursor_is_not_glued_to_the_last_row() -> void:
	var offset := 0
	for selected in range(13):
		offset = MenuScroll.window_offset(selected, VISIBLE, TOTAL, offset)
	offset = MenuScroll.window_offset(9, VISIBLE, TOTAL, offset)
	var row := 9 - offset
	assert_eq(row, 2, "selection 9 sits on row 2 of the window, with three rows visible below it")
	assert_true(row < VISIBLE - 1, "the cursor must be able to sit somewhere other than the bottom row")


func test_a_wrap_snaps_the_window_to_the_new_end() -> void:
	var offset := MenuScroll.window_offset(TOTAL - 1, VISIBLE, TOTAL, 0)
	assert_eq(offset, TOTAL - VISIBLE, "wrapping to the last row shows the end of the list")
	offset = MenuScroll.window_offset(0, VISIBLE, TOTAL, offset)
	assert_eq(offset, 0, "wrapping back to the first row shows the start")


## Entering a list, or switching to another one, resets the selection to 0 — which pulls the window
## back on its own. This is why no menu needs an explicit reset when its list changes.
func test_a_stale_offset_from_a_longer_list_self_corrects() -> void:
	assert_eq(MenuScroll.window_offset(0, VISIBLE, 3, 14), 0, "a selection of 0 always pulls the window to 0")
	assert_eq(MenuScroll.window_offset(2, VISIBLE, 3, 14), 0, "a list shorter than the window never scrolls")


func test_degenerate_inputs_do_not_produce_a_negative_or_runaway_offset() -> void:
	assert_eq(MenuScroll.window_offset(0, 0, TOTAL, 0), 0, "a zero-height window has no offset")
	assert_eq(MenuScroll.window_offset(0, VISIBLE, 0, 0), 0, "an empty list has no offset")
	assert_eq(MenuScroll.window_offset(-1, VISIBLE, TOTAL, 5), 0, "a selection below the list clamps to 0")
	assert_eq(MenuScroll.window_offset(999, VISIBLE, TOTAL, 0), TOTAL - VISIBLE, "a selection past the end clamps to the last window")


## The call sites, which the arms above cannot reach: every list that had the old formula now stores
## an offset and passes it in. A site that recomputes from scratch is the bug returning.
func test_every_list_menu_stores_its_own_window() -> void:
	var sites := {
		"res://src/ui/EquipmentMenu.gd": ["_item_scroll"],
		"res://src/ui/JobMenu.gd": ["_job_scroll"],
		"res://src/ui/AbilitiesMenu.gd": ["_ability_scroll", "_passive_scroll"],
	}
	for path in sites:
		var code: String = GdSource.code_of(path)
		assert_ne(code, "", "%s must be readable as source" % path)
		for field in sites[path]:
			assert_true(code.contains("var %s: int = 0" % field), "%s must declare %s as stored state" % [path, field])
			assert_true(code.contains("%s = MenuScroll.window_offset(" % field),
				"%s must assign %s from the shared helper, not recompute a window" % [path, field])


func test_the_pinning_formula_is_gone_from_every_menu() -> void:
	var checked := 0
	for name in ["EquipmentMenu", "JobMenu", "AbilitiesMenu"]:
		var code: String = GdSource.code_of("res://src/ui/%s.gd" % name)
		assert_ne(code, "", "%s must be readable as source" % name)
		checked += 1
		assert_eq(code.find("- max_visible + 1"), -1,
			"%s still computes a window from the selection alone, which pins the cursor to the bottom row" % name)
	assert_eq(checked, 3, "all three menus were read; a short corpus would pass this vacuously")
	assert_true(GdSource.code_of("res://src/ui/MenuScroll.gd").contains("selected >= offset + visible"),
		"the helper itself must still test the selection against the window it was given")
