extends GutTest

## Target rows in the battle command menu ("Slime (48 HP) ~12 dmg [KILL]") were
## measured at a hardcoded 11px and drawn at TextScale.scaled(16). The panel
## stayed on its 210px floor, clip_text ellipsized the damage and [KILL] off
## the end, and a larger text-size setting clipped the glyph vertically too.
## The box is now sized from the font the row actually draws. The half-screen
## cap is unchanged, and a short command stays on the narrow menu.


const Win98MenuScript = preload("res://src/ui/Win98Menu.gd")

var _scale_before: float = 1.0


func before_all() -> void:
	if GameState and "text_size_scale" in GameState:
		_scale_before = float(GameState.text_size_scale)


func before_each() -> void:
	if GameState and "text_size_scale" in GameState:
		GameState.text_size_scale = _scale_before


func after_each() -> void:
	if GameState and "text_size_scale" in GameState:
		GameState.text_size_scale = _scale_before


func _open(items: Array) -> Win98Menu:
	var menu = Win98MenuScript.new()
	add_child_autofree(menu)
	menu.setup("Attack", items, Vector2(40, 40), "fighter")
	# setup() builds the rows, then awaits a frame and two short timers before it goes idle.
	# Freeing the menu in the middle of that leaves it as a child of the test.
	await get_tree().create_timer(0.25, true, false, true).timeout
	return menu


## The visible box. A Label refuses to be shorter than font.get_height() (leading included), so the row clips it.
func _visible(label: Label) -> Vector2:
	var parent := label.get_parent() as Control
	if parent and parent.clip_contents:
		return parent.size
	return label.size


func _fits(label: Label) -> void:
	var font := label.get_theme_font("font")
	var px := label.get_theme_font_size("font_size")
	assert_not_null(font, "the row must have a font to measure against")
	var box := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	var shown := _visible(label)
	assert_gte(shown.x + 0.5, box.x,
		"'%s' draws at %dpx and needs %.0fpx, but the box is %.0fpx — the tail gets ellipsized" % [label.text, px, box.x, shown.x])
	assert_gte(shown.y + 0.5, box.y,
		"the row is shorter than the %dpx line it draws (%.0fpx in a %.0fpx clip)" % [px, box.y, shown.y])
	assert_eq(label.vertical_alignment, VERTICAL_ALIGNMENT_TOP,
		"the glyph has to sit at the top of the clip, or the leading below it is what gets cut")


func _press(menu: Win98Menu, action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	menu._input(ev)


func _visible_cursor(menu: Win98Menu) -> int:
	var container := menu._get_items_container()
	if container == null:
		return -1
	for i in container.get_child_count():
		var cursor := container.get_child(i).get_node_or_null("Cursor")
		if cursor and cursor.visible:
			return i
	return -1


func _row(menu: Win98Menu, index: int) -> Control:
	return menu.find_child("Item%d" % index, true, false) as Control


func test_a_target_row_keeps_its_damage_and_kill_readout() -> void:
	var text := "Slime (48 HP) ~12 dmg [KILL]"
	var menu := await _open([{"id": "t", "label": text}])
	var label := menu.find_child("Label", true, false) as Label
	assert_not_null(label, "the target row must have a label")
	assert_eq(label.text, text)
	assert_eq(label.get_theme_font_size("font_size"), TextScale.scaled(16),
		"the row draws at the battle menu's label size, which is what the box has to be measured with")
	_fits(label)
	var row := _row(menu, 0)
	assert_eq(int(row.size.y), 24, "a 16px line is 23px tall, so the default row stays 24")
	assert_eq(int(_visible(label).y), int(row.size.y), "the visible clip is the row")
	var cap := int(menu.get_viewport_rect().size.x) / 2
	assert_lt(int(menu.size.x), cap,
		"this label fits under the half-screen cap — ellipsis here would be the measurement, not the cap")


func test_a_short_command_stays_on_the_narrow_menu() -> void:
	var menu := await _open([{"id": "a", "label": "Attack"}])
	assert_eq(int(menu.size.x), 210, "short commands keep the existing 210px menu; only rows that need the room grow")
	assert_eq(int(_row(menu, 0).size.y), 24, "default text size does not grow the row")


func test_the_smallest_text_size_keeps_the_24px_row_and_the_line() -> void:
	GameState.text_size_scale = 0.8
	var text := "Slime (48 HP) ~12 dmg [KILL]"
	var menu := await _open([{"id": "t", "label": text}])
	var label := menu.find_child("Label", true, false) as Label
	var row := _row(menu, 0)
	assert_eq(label.text, text)
	assert_eq(int(row.size.y), 24, "80% text is smaller than the default line, so the row stays 24")
	assert_eq(int(_visible(label).y), 24, "the visible clip stays on the 24px row")
	_fits(label)


func test_the_largest_text_size_grows_the_row_to_the_glyph() -> void:
	GameState.text_size_scale = 2.0
	var text := "Slime (48 HP) ~12 dmg [KILL]"
	var menu := await _open([{"id": "t", "label": text}])
	var label := menu.find_child("Label", true, false) as Label
	var row := _row(menu, 0)
	assert_gt(int(row.size.y), 24, "200% text is taller than 24px, so the row grows instead of clipping")
	assert_eq(int(_visible(label).y), int(row.size.y))
	_fits(label)
	var cap := int(menu.get_viewport_rect().size.x) / 2
	assert_lte(int(menu.size.x), cap)


func test_a_larger_text_size_still_fits_the_line_and_the_mp_cost() -> void:
	assert_true(GameState != null and "text_size_scale" in GameState, "CONTROL: text size is a live setting")
	GameState.text_size_scale = 1.5
	var menu := await _open([{"id": "fire", "label": "Fire", "cost": 999, "cost_affordable": true}])
	var name := menu.find_child("Label", true, false) as Label
	var cost := menu.find_child("Cost", true, false) as Label
	assert_not_null(name)
	assert_not_null(cost)
	assert_eq(name.get_theme_font_size("font_size"), TextScale.scaled(16))
	assert_eq(cost.get_theme_font_size("font_size"), TextScale.scaled(10))
	_fits(name)
	_fits(cost)
	var cap := int(menu.get_viewport_rect().size.x) / 2
	assert_lte(int(menu.size.x), cap, "a bigger font widens the row up to the existing half-screen cap, and no further")


func test_keyboard_down_and_confirm_selects_that_row() -> void:
	var menu := await _open([
		{"id": "attack", "label": "Attack"},
		{"id": "item", "label": "Item"},
		{"id": "defer", "label": "Defer"},
	])
	assert_true(menu._can_accept_input, "CONTROL: the menu is accepting input")
	_press(menu, "ui_down")
	_press(menu, "ui_down")
	assert_eq(menu.get_selected_item_id(), "defer")
	assert_eq(_visible_cursor(menu), 2, "the cursor is on the row confirm will select")
	var picked: Array = []
	menu.item_selected.connect(func(id, _data): picked.append(str(id)))
	_press(menu, "ui_accept")
	assert_eq(picked, ["defer"], "confirm submits the highlighted row, not a neighbour")


func test_a_pad_down_and_stick_move_the_same_cursor() -> void:
	var menu := await _open([
		{"id": "attack", "label": "Attack"},
		{"id": "item", "label": "Item"},
		{"id": "defer", "label": "Defer"},
	])
	assert_true(menu._can_accept_input, "CONTROL: the menu is accepting input")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_DOWN
	pad.pressed = true
	menu._input(pad)
	assert_eq(menu.get_selected_item_id(), "item")
	assert_eq(_visible_cursor(menu), 1)
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = 1.0
	menu._input(stick)
	assert_eq(menu.get_selected_item_id(), "defer", "the left stick steps the same row the d-pad did")
	assert_eq(_visible_cursor(menu), 2)


func test_a_long_list_scrolls_by_the_drawn_row() -> void:
	var items: Array = []
	for i in 40:
		items.append({"id": "r%d" % i, "label": "Spell %02d" % i})
	var menu := await _open(items)
	assert_true(menu._can_accept_input, "CONTROL: the menu is accepting input")
	assert_gt(menu._max_visible_rows, 1, "CONTROL: the list is tall enough to scroll")
	assert_lt(menu._max_visible_rows, items.size(), "CONTROL: the list does not fit, so scrolling is what is under test")
	var container := menu._get_items_container()
	var before: float = container.position.y
	var steps := menu._max_visible_rows
	for _i in steps:
		_press(menu, "ui_down")
	assert_eq(menu.selected_index, steps)
	assert_eq(menu.get_selected_item_id(), "r%d" % steps)
	assert_eq(menu._scroll_offset, 1, "one step past the window scrolls exactly one row")
	assert_almost_eq(container.position.y, before - float(menu._row_height()), 0.6)
	assert_eq(_visible_cursor(menu), menu.selected_index)
	var row := _row(menu, menu.selected_index)
	var shown := row.get_global_rect()
	var panel := menu.get_global_rect()
	assert_gte(shown.position.y, panel.position.y - 1.0)
	assert_lte(shown.end.y, panel.end.y + 1.0, "the selected row stays inside the panel while the list scrolls")


func test_a_target_submenu_clears_the_command_menu_and_the_status_panels() -> void:
	var enemy := Control.new()
	enemy.name = "EnemyStatusPanel"
	enemy.position = Vector2(5, 60)
	enemy.size = Vector2(175, 220)
	add_child_autofree(enemy)
	var party := Control.new()
	party.name = "PartyStatusPanel"
	party.position = Vector2(1080, 40)
	party.size = Vector2(195, 420)
	add_child_autofree(party)
	var slime := "Slime (48 HP) ~12 dmg [KILL]"
	var boss := "Glacius, the Frozen Sovereign (248 HP) ~86 dmg [KILL]"
	var menu := await _open([{
		"id": "attack_menu",
		"label": "Attack",
		"submenu": [
			{"id": "t0", "label": slime},
			{"id": "t1", "label": boss},
		],
	}])
	menu.position = Vector2(menu.get_viewport_rect().size.x * 0.42, 180)
	menu._do_open_submenu(0, menu.menu_items[0])
	await get_tree().create_timer(0.3, true, false, true).timeout
	var sub: Win98Menu = menu.submenu
	assert_not_null(sub, "the attack row opened its target list")
	var parent_r := menu.get_global_rect()
	var sub_r := sub.get_global_rect()
	assert_lte(sub_r.end.x, parent_r.position.x - 4.0,
		"the target list sits to the left of the command menu (got %s vs parent %s)" % [sub_r, parent_r])
	assert_false(sub_r.intersects(enemy.get_global_rect(), true),
		"the target list covers the enemy panel: %s vs %s" % [sub_r, enemy.get_global_rect()])
	assert_false(sub_r.intersects(party.get_global_rect(), true),
		"the target list covers the party panel: %s vs %s" % [sub_r, party.get_global_rect()])
	var first := sub.find_child("Label", true, false) as Label
	assert_eq(first.text, slime)
	_fits(first)
	assert_true(sub_r.position.x >= -1.0 and sub_r.position.y >= -1.0 and sub_r.end.x <= menu.get_viewport_rect().size.x + 1.0 and sub_r.end.y <= menu.get_viewport_rect().size.y + 1.0,
		"the submenu stays on screen")
