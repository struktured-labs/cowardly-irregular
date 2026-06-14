extends GutTest

## Regression test for the AutobattleGridEditor off-screen-rules bug.
##
## Bug (medium): The rule grid is hand-positioned into a plain Control
## (_grid_container) of fixed height (~620px at 720p). Each rule row consumes
## CELL_HEIGHT(44) + ROW_SPACING(24) = 68px, so only ~9 rules fit. There was
## no ScrollContainer, no clip_contents, no MAX_RULES cap, and no scroll-follow
## on the cursor. Once a script exceeded ~9 rules, rows drew past the container
## into the legend strip / off the bottom of the screen, and as cursor_row
## advanced the animated cursor followed the selected row off-screen with no
## scroll. Mastering long autobattle scripts is a core design pillar, so this
## hit the power user directly.
##
## Fix:
##   - _scroll_offset var + _update_scroll_offset() clamps the selected row
##     into the visible viewport by shifting _grid_container.position.y. The
##     animated cursor reads _grid_container.position, so it follows.
##   - _grid_container.clip_contents = true hides scrolled-out rows.
##   - MAX_RULES caps OR-row growth (still scrollable below the cap).
##
## Tested behaviorally: instantiate the editor, inject a long script, navigate
## to the last row, and verify the selected cell stays inside the grid viewport.

const GridEditorScript = preload("res://src/ui/autobattle/AutobattleGridEditor.gd")

const VIEW_W := 1280
const VIEW_H := 720


func _make_editor() -> AutobattleGridEditor:
	var editor = GridEditorScript.new()
	editor.size = Vector2(VIEW_W, VIEW_H)
	add_child_autofree(editor)
	# _ready() runs on add_child; setup() rebuilds UI + grid with real data.
	editor.setup("hero", "Hero", null, [])
	return editor


func _fill_rules(editor: AutobattleGridEditor, count: int) -> void:
	"""Replace the editor's rules with `count` simple always->attack rows."""
	editor.rules.clear()
	for i in range(count):
		editor.rules.append({
			"conditions": [{"type": "always"}],
			"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
			"enabled": true
		})
	editor._refresh_grid()


func test_grid_container_clips_overflow() -> void:
	"""_grid_container must clip its contents so scrolled-out rows don't bleed
	over the stats panel / legend strip."""
	var editor = _make_editor()
	assert_not_null(editor._grid_container, "grid container must be built")
	assert_true(editor._grid_container.clip_contents,
		"grid container must have clip_contents=true so off-screen rows are "
		+ "hidden instead of bleeding over the legend/stats (regression)")


func test_far_row_scrolls_into_view() -> void:
	"""With many rules, selecting the LAST row must scroll the grid so the
	row's cell stays within the visible grid viewport. Pre-fix the cursor
	followed the row off the bottom of the screen with no scroll."""
	var editor = _make_editor()
	var row_stride = editor.CELL_HEIGHT + editor.ROW_SPACING
	# 20 rows * 68px = 1360px of content vs ~620px viewport — well past overflow.
	_fill_rules(editor, 20)

	# Selecting row 0 first: no scroll needed, offset stays at top.
	editor.cursor_row = 0
	editor.cursor_col = 0
	editor._update_cursor()
	assert_eq(editor._scroll_offset, 0.0,
		"row 0 must not scroll the grid (offset stays at top)")

	# Navigate to the last row — this MUST scroll.
	editor.cursor_row = editor.rules.size() - 1
	editor.cursor_col = 0
	editor._update_cursor()

	assert_gt(editor._scroll_offset, 0.0,
		"selecting the last of 20 rows must produce a positive scroll offset "
		+ "(regression: pre-fix _scroll_offset did not exist and rows ran "
		+ "off-screen)")

	# The selected row's local-y within the grid, after scroll, must be inside
	# the visible viewport [0, view_h]. This is exactly what the cursor draws.
	var view_h = editor._grid_container.size.y
	var local_top = editor.cursor_row * row_stride - editor._scroll_offset
	var local_bottom = local_top + editor.CELL_HEIGHT
	assert_gte(local_top, 0.0,
		"selected row top must not be scrolled above the viewport")
	assert_lte(local_bottom, view_h,
		"selected row bottom must stay within the grid viewport height "
		+ "(regression: the row used to draw past the bottom of the screen)")


func test_scroll_offset_resets_when_returning_to_top() -> void:
	"""Scrolling down then back to row 0 must return the grid to the top
	(offset back to 0), so the first rules aren't permanently pushed up."""
	var editor = _make_editor()
	_fill_rules(editor, 20)

	editor.cursor_row = 19
	editor._update_cursor()
	assert_gt(editor._scroll_offset, 0.0, "should be scrolled down at row 19")

	editor.cursor_row = 0
	editor._update_cursor()
	assert_eq(editor._scroll_offset, 0.0,
		"returning to row 0 must scroll the grid back to the top")


func test_grid_container_position_tracks_scroll() -> void:
	"""The grid container's y position must shift by -_scroll_offset from its
	base anchor. The animated cursor reads _grid_container.position, so this is
	what keeps rows and cursor moving together."""
	var editor = _make_editor()
	_fill_rules(editor, 20)

	editor.cursor_row = 19
	editor._update_cursor()

	var expected_y = editor.GRID_BASE_POS.y - editor._scroll_offset
	assert_almost_eq(editor._grid_container.position.y, expected_y, 0.5,
		"grid container y must equal GRID_BASE_POS.y - _scroll_offset so rows "
		+ "and the cursor shift together")


func test_max_rules_caps_or_row_growth() -> void:
	"""_add_or_row / _insert_row_after must refuse to grow past MAX_RULES so a
	script can't balloon unbounded. (Scrolling handles everything below the
	cap; the cap is a sanity bound.)"""
	var editor = _make_editor()
	_fill_rules(editor, editor.MAX_RULES)
	assert_eq(editor.rules.size(), editor.MAX_RULES, "precondition: at cap")

	editor.cursor_row = editor.rules.size() - 1
	editor._add_or_row()
	assert_eq(editor.rules.size(), editor.MAX_RULES,
		"_add_or_row must not exceed MAX_RULES")

	editor._insert_row_after(0)
	assert_eq(editor.rules.size(), editor.MAX_RULES,
		"_insert_row_after must not exceed MAX_RULES")
