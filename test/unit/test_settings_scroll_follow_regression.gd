extends GutTest

## Regression test for the SettingsMenu ScrollContainer scroll-follow.
##
## Bug (verified HIGH, tmp/fixes/src__ui__SettingsMenu.gd.md):
##   The SettingsMenu ScrollContainer correctly CLIPS its content, but
##   navigation never scrolled it to follow the keyboard/gamepad selection.
##   With debug_log_enabled (the default) the content is taller than the
##   ~570px viewport, so pressing Down past the visible rows moved the
##   highlight onto a row scrolled out of view — the cursor "disappeared"
##   and the bottom action buttons (Quit to Title / Debug Teleport) were
##   unreachable while selected. TeleportMenu already had scroll-follow;
##   SettingsMenu never adopted it.
##
## Fix: _update_selection() now caches the ScrollContainer on `_scroll`
## and calls ensure_control_visible() on the selected row so the viewport
## tracks the cursor.
##
## These tests instantiate the real menu, force a small viewport so the
## content overflows, then assert the scroll position follows selection
## down and back up.

const SETTINGS_MENU_PATH := "res://src/ui/SettingsMenu.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func _make_settings_menu() -> Control:
	# Force debug_log_enabled so the largest row set is built (max overflow).
	var prev_debug = true
	if GameState and "debug_log_enabled" in GameState:
		prev_debug = GameState.debug_log_enabled
		GameState.debug_log_enabled = true
	var script = load(SETTINGS_MENU_PATH)
	var menu = script.new()
	# Small explicit size forces the ScrollContainer viewport to overflow.
	menu.size = Vector2(800, 480)
	add_child_autofree(menu)
	# Restore the live flag — _build_ui already read it during _ready.
	if GameState and "debug_log_enabled" in GameState:
		GameState.debug_log_enabled = prev_debug
	return menu


func test_scroll_member_is_cached_after_build() -> void:
	var menu = _make_settings_menu()
	await get_tree().process_frame
	assert_true("_scroll" in menu, "SettingsMenu must declare a _scroll field")
	assert_not_null(menu._scroll, "_scroll must be assigned the ScrollContainer in _build_ui")
	assert_true(menu._scroll is ScrollContainer, "_scroll must hold a ScrollContainer")


func test_selecting_last_row_scrolls_it_into_view() -> void:
	var menu = _make_settings_menu()
	# Let the VBox + ScrollContainer lay out so child rect positions and the
	# scrollbar range are valid before we read any geometry. Headless layout
	# does NOT settle synchronously, so we pump several frames (mirrors the
	# BestiaryMenu scroll-follow regression test) before sampling.
	await get_tree().process_frame
	await get_tree().process_frame

	var item_count: int = menu._settings_items.size()
	assert_gt(item_count, 0, "settings menu should have built rows")

	# Sanity: with the forced small viewport, content must actually overflow,
	# otherwise the scroll-follow has nothing to do and the test is vacuous.
	var content_h: float = menu._scroll.get_child(0).size.y
	var viewport_h: float = menu._scroll.size.y
	assert_gt(content_h, viewport_h,
		"test setup must force overflow (content %0.0f vs viewport %0.0f)" % [content_h, viewport_h])

	# At rest, selection is row 0 — no scroll needed.
	assert_eq(menu._scroll.scroll_vertical, 0,
		"freshly built menu should start scrolled to the top")

	# Navigate to the very last row (Quit to Title / Debug Teleport region).
	# _update_selection() must call ensure_control_visible() on that row, which
	# advances the ScrollContainer offset so the cursor stays on-screen.
	menu.selected_index = item_count - 1
	menu._update_selection()
	# Give ensure_control_visible() a frame to commit the new scroll offset.
	await get_tree().process_frame

	# Behavioral guard: the scroll mechanism the fix relies on (the cached
	# ScrollContainer scroll offset) must have advanced past the top to chase
	# the bottom selection. This is the real, robust scroll-follow signal —
	# pixel-precise content-relative row coordinates do NOT settle reliably in
	# headless layout (the VBox child .position.y and scroll_vertical can be
	# read in inconsistent states within one frame), so we assert the offset
	# moved rather than comparing flaky per-row global geometry.
	assert_gt(menu._scroll.scroll_vertical, 0,
		"selecting the bottom row must scroll the container down from the top")

	# And the offset must not exceed the scroll range (i.e. it stops at the
	# bottom of the content, keeping the last row in view rather than
	# overshooting). When the headless scrollbar range has settled we can
	# bound it; otherwise the source-pins + the >0 advance above are the guard.
	var max_scroll: float = maxf(0.0, content_h - viewport_h)
	if max_scroll > 0.0:
		assert_true(float(menu._scroll.scroll_vertical) <= max_scroll + 1.0,
			"scroll offset (%d) must not overshoot the bottom of the content (max %0.0f)" % [
				menu._scroll.scroll_vertical, max_scroll])
		# At the last row the container should be at (or essentially at) the
		# bottom of its scroll range — the bottom action row is now visible.
		assert_true(float(menu._scroll.scroll_vertical) >= max_scroll - viewport_h,
			"selecting the final row should scroll near the bottom of the range (offset %d, max %0.0f)" % [
				menu._scroll.scroll_vertical, max_scroll])


func test_scrolling_back_to_top_resets_scroll() -> void:
	var menu = _make_settings_menu()
	await get_tree().process_frame
	await get_tree().process_frame

	var item_count: int = menu._settings_items.size()
	# Scroll to the bottom first.
	menu.selected_index = item_count - 1
	menu._update_selection()
	await get_tree().process_frame
	var bottom_scroll: int = menu._scroll.scroll_vertical
	assert_gt(bottom_scroll, 0, "should be scrolled down at the bottom row")

	# Return to row 0 — the top row must be visible again (scroll back to top).
	menu.selected_index = 0
	menu._update_selection()
	await get_tree().process_frame
	assert_eq(menu._scroll.scroll_vertical, 0,
		"selecting the top row must scroll the container back to the top")


func test_update_selection_uses_ensure_control_visible() -> void:
	# Source-level guard: the scroll-follow must go through the
	# ScrollContainer API in _update_selection, not be a no-op.
	var text = _read(SETTINGS_MENU_PATH)
	var idx = text.find("func _update_selection(")
	assert_gt(idx, 0, "_update_selection must exist")
	var next_func = text.find("\nfunc ", idx + 1)
	if next_func == -1:
		next_func = text.length()
	var body = text.substr(idx, next_func - idx)
	assert_true(body.find("ensure_control_visible") > -1,
		"_update_selection must call ensure_control_visible to follow the cursor")
	assert_true(body.find("_scroll") > -1,
		"_update_selection must reference the cached _scroll ScrollContainer")
