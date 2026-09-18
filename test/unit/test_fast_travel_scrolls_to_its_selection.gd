extends GutTest

## ⛔ THE CRYSTAL WARP MENU DREW ITS ROWS OUTSIDE ITS OWN PANEL. Rows were added to the panel at an
## absolute y, with no ScrollContainer, no offset and no clip_contents — so once the list outgrew
## the panel the extra rows rendered over the rest of the screen and the cursor walked off with
## them, still "working" and invisible.
##
## ⚠️ AND ITS OWN SUBTITLE ADVERTISES THE CONTROL THAT GETS YOU THERE FASTEST: "(L/R to page)".
## MenuPaging moves TEN rows per trigger pull, straight into the undrawn region.
##
## 🔑 REACHABLE, MEASURED: 32 crystals are activatable (13 village scripts + 9 dungeons + 10
## overworlds, all reached through SavePoint -> GameState.activate_crystal) against ~16 rows that
## fit a 720p panel. TeleportMenu renders the SAME destination list through a ScrollContainer with
## an ensure-visible pass; this is that ported to its sibling.
##
## The invariant is what the PLAYER sees: the selected row must lie inside the scroll viewport.
## Asserting a particular scroll_vertical would pin a coincidental number.

const FastTravelScript := preload("res://src/ui/FastTravelMenu.gd")


func _menu(row_count: int) -> Node:
	var m: Node = FastTravelScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.size = Vector2(1280, 720)
	var rows: Array = []
	for i in range(row_count):
		rows.append({"id": "m%d" % i, "label": "Crystal %d" % i, "spawn": "default",
			"cost": i * 10, "affordable": true})
	m.set("_rows", rows)
	m.set("_selected", 0)
	m._build_ui()
	return m


## ⛔ A ScrollContainer computes its scroll RANGE during layout, so scroll_vertical clamps to 0
## until a frame has passed — measured: without this the fix reads as broken (row_y=812, scroll=0).
## Every arm that moves the cursor awaits one first, which is also what the running game gives it.
func _settled(m: Node) -> void:
	await get_tree().process_frame
	await get_tree().process_frame


## CONTROL: the fixture must build a real scroll viewport, or every arm below measures nothing.
func test_the_menu_builds_a_scroll_viewport() -> void:
	var m := _menu(30)
	var sc = m.get("_scroll")
	assert_ne(sc, null, "no ScrollContainer built — the rows are back on the panel unclipped")
	assert_gt(float(m.get("_viewport_height")), 0.0, "the viewport must have a height")
	assert_eq(int(m.get("_row_y").size()), 30, "every row must record its y for ensure-visible")


## The row's DRAWN extent, not its pitch. An item is ROW_HEIGHT - 2 tall, and at maximum scroll the
## last row sits flush against the bottom — measured 812..838 inside a viewport of 389..839. Using
## the 28px pitch instead reported that as off screen by one pixel and would have had me "fix" a
## correct clamp.
func _selected_is_visible(m: Node) -> bool:
	var sel: int = int(m.get("_selected"))
	var row_y: float = m.get("_row_y")[sel]
	var top: float = float(m.get("_scroll").scroll_vertical)
	var drawn_h: float = 28.0 - 2.0
	return row_y >= top and row_y + drawn_h <= top + float(m.get("_viewport_height"))


## Drives _move, the real navigation owner — not _update_selection directly. An arm that called the
## scroll itself would pass even if nothing invoked it, which is how two guards in this session
## passed on the bug they were written for.
func test_walking_to_the_last_crystal_keeps_it_on_screen() -> void:
	var m := _menu(30)
	await _settled(m)
	m._move(29)
	assert_true(_selected_is_visible(m),
		"crystal 29 of 30 is outside the viewport — row_y=%.0f, scroll=%d, view=%.0f"
			% [m.get("_row_y")[29], m.get("_scroll").scroll_vertical, m.get("_viewport_height")])


## The advertised control. A trigger pull is ten rows, which is what makes the undrawn region easy
## to reach rather than a completionist edge case.
func test_paging_lands_on_a_visible_row() -> void:
	var m := _menu(30)
	await _settled(m)
	m._move(MenuPaging.PAGE_ROWS)
	assert_true(_selected_is_visible(m),
		"a single page jump left the cursor off screen — row_y=%.0f, scroll=%d"
			% [m.get("_row_y")[int(m.get("_selected"))], m.get("_scroll").scroll_vertical])
	m._move(MenuPaging.PAGE_ROWS)
	assert_true(_selected_is_visible(m), "the second page jump left the cursor off screen")


## Walking back up must bring the viewport with it, or the cursor leaves the other end.
func test_walking_back_up_follows_the_cursor() -> void:
	var m := _menu(30)
	await _settled(m)
	m._move(29)
	assert_gt(int(m.get("_scroll").scroll_vertical), 0, "CONTROL: the viewport must have moved first")
	m._move(-28)
	assert_true(_selected_is_visible(m), "after walking back to crystal 1 the cursor is off screen")


## A list that fits must not scroll at all.
func test_a_short_list_does_not_scroll() -> void:
	var m := _menu(4)
	await _settled(m)
	m._move(3)
	assert_eq(int(m.get("_scroll").scroll_vertical), 0,
		"a list that fits the panel must stay at the top")


## ⛔ THE ARM THAT MAKES THE OTHERS REAL, and the third time this session a guard of mine passed on
## the bug it was written for. Every arm above reads _row_y / scroll_vertical / _viewport_height —
## pure bookkeeping, none of which knows where the row NODES are parented. Re-parenting them back
## onto the panel left all six GREEN: the scroll maths stayed perfect while nothing moved with the
## viewport, which is precisely the original defect.
func test_the_rows_actually_live_inside_the_viewport() -> void:
	var m := _menu(30)
	var sc = m.get("_scroll")
	assert_ne(sc, null, "CONTROL: the scroll container must exist")
	var content = m.get("_content")
	assert_ne(content, null, "CONTROL: the content holder must exist")
	assert_eq(int(content.get_child_count()), 30,
		"the rows are not children of the scrolled content — they are drawn at a fixed position on "
		+ "the panel, so scroll_vertical moves the viewport and the rows stay put")
	for child in content.get_children():
		assert_true(sc.is_ancestor_of(child),
			"a row is outside the ScrollContainer and cannot move with it")


## ⛔ RATCHET: FastTravelMenu and TeleportMenu render the same destination list and diverged
## silently. Neither may lose its scroll.
func test_both_destination_menus_scroll() -> void:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	for path in ["res://src/ui/FastTravelMenu.gd", "res://src/ui/TeleportMenu.gd"]:
		var code: String = GdSource.code_of(path)
		assert_ne(code, "", "CONTROL: %s must survive the comment strip" % path)
		assert_true(code.contains("ScrollContainer.new()"),
			"%s builds no scroll viewport — its rows draw past the panel once the list outgrows it"
				% path)
		assert_true(code.contains("scroll_vertical"),
			"%s never moves its viewport, so the selection can leave it" % path)
