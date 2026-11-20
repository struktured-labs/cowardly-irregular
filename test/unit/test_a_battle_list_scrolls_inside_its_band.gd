extends GutTest

## battle 26685's stated limit: a floored battle menu MOVES above the hint bar, but a list taller than the band between the
## top margin and the floor still overran it, because the row cap was sized from the whole screen. The cap now reads the floor.

var _saved_scale = null


func before_each() -> void:
	_saved_scale = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _saved_scale


func _rows(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"label": "Ability %d" % i, "id": "r%d" % i})
	return out


func _menu(rows: Array, floor_y: float) -> Win98Menu:
	var m := Win98Menu.new()
	m.screen_floor_y = floor_y
	add_child_autofree(m)
	m.setup("Hero", rows, Vector2(300, 200), "fighter")
	await get_tree().process_frame
	return m


func test_the_floor_names_every_member_this_file_drives() -> void:
	var m := Win98Menu.new()
	autofree(m)
	for p in ["screen_floor_y", "_max_visible_rows", "_scroll_offset", "selected_index", "submenu"]:
		assert_true(p in m, "FLOOR: Win98Menu.%s" % p)
	for f in ["setup", "_update_selection", "_open_submenu"]:
		assert_true(m.has_method(f), "FLOOR: Win98Menu.%s()" % f)
	assert_true((load("res://src/ui/Win98Menu.gd") as GDScript).get_script_constant_map().has("MENU_SCREEN_MARGIN"), "FLOOR: Win98Menu.MENU_SCREEN_MARGIN")


## THE DEFECT: 40 rows at 200%. Without a floor the list is sized to the screen and is taller than the band; with one it fits and scrolls.
func test_a_long_list_fits_the_band_above_its_floor() -> void:
	GameState.text_size_scale = 2.0
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var floor_y: float = vp.y - 150.0
	var band: float = floor_y - float(Win98Menu.MENU_SCREEN_MARGIN) * 2.0
	var loose: Win98Menu = await _menu(_rows(40), 0.0)
	assert_gt(loose.size.y, band, "CONTROL: sized to the screen the list is %d px, taller than the %d px band" % [int(loose.size.y), int(band)])
	var held: Win98Menu = await _menu(_rows(40), floor_y)
	assert_lte(held.size.y, band + 0.5, "with a floor the list is %d px, inside the %d px band" % [int(held.size.y), int(band)])
	assert_lte(held.position.y + held.size.y, floor_y + 0.5, "and ends at %d, above the floor %d" % [int(held.position.y + held.size.y), int(floor_y)])
	assert_gte(held.position.y, 0.0, "with its top on screen (%d)" % int(held.position.y))
	assert_gt(held._max_visible_rows, 0, "it scrolls: %d of 40 rows show" % held._max_visible_rows)
	assert_lt(held._max_visible_rows, loose._max_visible_rows if loose._max_visible_rows > 0 else 41, "fewer rows show than when sized to the screen")


## Every row is still reachable: walking to the last row scrolls it into the window.
func test_the_last_row_scrolls_into_view() -> void:
	GameState.text_size_scale = 2.0
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var held: Win98Menu = await _menu(_rows(40), vp.y - 150.0)
	assert_gt(held._max_visible_rows, 0, "CONTROL: the list scrolls")
	assert_eq(held._scroll_offset, 0, "CONTROL: it opens on its first rows")
	held.selected_index = 39
	held._update_selection()
	assert_eq(held._scroll_offset, 40 - held._max_visible_rows, "the last row is the window's last")


## A list that fits is not touched by the floor: same size, no scrolling.
func test_a_short_list_is_unchanged_by_a_floor() -> void:
	GameState.text_size_scale = 1.0
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var loose: Win98Menu = await _menu(_rows(5), 0.0)
	var held: Win98Menu = await _menu(_rows(5), vp.y - 40.0)
	assert_eq(held.size, loose.size, "a 5-row menu is the same size with a floor")
	assert_eq(held._max_visible_rows, 0, "and does not scroll")


## The ability list is a SUBMENU: it inherits the floor (battle ef6f81487) and so the same cap.
func test_a_long_submenu_fits_the_band_too() -> void:
	GameState.text_size_scale = 2.0
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var floor_y: float = vp.y - 150.0
	var band: float = floor_y - float(Win98Menu.MENU_SCREEN_MARGIN) * 2.0
	var item := {"label": "Ability", "id": "ability_menu", "submenu": _rows(40)}
	var root: Win98Menu = await _menu([item, {"label": "Defer", "id": "defer"}], floor_y)
	root._open_submenu(0, item)
	await get_tree().process_frame
	await get_tree().process_frame
	var sub: Win98Menu = root.submenu
	assert_not_null(sub, "CONTROL: the submenu opened")
	if sub == null:
		return
	assert_eq(sub.screen_floor_y, floor_y, "CONTROL: the submenu carries its parent's floor")
	assert_lte(sub.size.y, band + 0.5, "the 40-row submenu is %d px, inside the %d px band" % [int(sub.size.y), int(band)])
	assert_gt(sub._max_visible_rows, 0, "and scrolls")
	root.force_close()
