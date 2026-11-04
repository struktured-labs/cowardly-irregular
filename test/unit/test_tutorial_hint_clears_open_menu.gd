extends GutTest

## Demo prep 2026-11: the battle tutorial popup covered the command menu. The hint now starts below any open menu
## in its columns, and never leaves the screen doing so.

func test_hint_drops_below_a_menu_in_its_columns() -> void:
	var menu := Rect2(430, 60, 200, 180)
	var y: float = TutorialHint.top_clear_of(200.0, Vector2(880, 110), [menu])
	assert_gt(y, menu.end.y, "hint top is below the menu")


func test_hint_stays_on_screen() -> void:
	assert_eq(TutorialHint.fit_on_screen(700.0, 110.0, 720.0), 602.0)
	assert_eq(TutorialHint.fit_on_screen(4.0, 110.0, 720.0), TutorialHint.PANEL_TOP)


func test_open_menu_counts_as_reserved() -> void:
	var hint := TutorialHint.new()
	add_child_autofree(hint)
	var menu := Control.new()
	menu.add_to_group("win98_menus")
	menu.position = Vector2(300, 50)
	menu.size = Vector2(200, 150)
	add_child_autofree(menu)
	var found := false
	for r in hint._reserved_rects():
		if (r as Rect2).is_equal_approx(Rect2(300, 50, 200, 150)):
			found = true
	assert_true(found, "a visible win98 menu is reserved")
	menu.visible = false
	for r in hint._reserved_rects():
		assert_false((r as Rect2).is_equal_approx(Rect2(300, 50, 200, 150)), "hidden menu not reserved")
