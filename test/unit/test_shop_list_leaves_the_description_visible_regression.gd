extends GutTest

## The item shelf and the blacksmith shelf are longer than the gap above the
## description panel. Win98Menu capped a menu to the viewport, so a shop list
## that "fit" the screen painted over that panel — comparison stats and the
## gold shortfall, which live only there. The same list moved one row per
## press; every other long menu pages.

const ShopSceneScript := preload("res://src/exploration/ShopScene.gd")
const Win98MenuScript := preload("res://src/ui/Win98Menu.gd")


func _item_shop() -> ShopScene:
	var shop: ShopScene = ShopSceneScript.new()
	add_child_autofree(shop)
	shop.setup(shop.ShopType.ITEM, "General Store", VillageShop.ITEM_INVENTORY.duplicate())
	shop._open_buy_menu()
	return shop


func _menu_bottom(menu: Control) -> float:
	return menu.position.y + menu.size.y


func test_the_item_shelf_covers_the_description_unless_it_stops_short() -> void:
	var shop := _item_shop()
	var menu: Win98Menu = shop.current_menu
	var desc: Control = shop.description_panel
	assert_gte(menu.menu_items.size(), 20,
		"CONTROL: the general-store shelf is a long list, not a three-row menu")
	var bare := Win98MenuScript.new()
	bare.battle_mode = false
	shop.add_child(bare)
	bare.setup("Buy", menu.menu_items.duplicate(), Vector2(100, 100), "fighter")
	assert_gt(_menu_bottom(bare), desc.position.y,
		"CONTROL: this shelf reaches the description when the menu may grow to the viewport. bottom=%s desc=%s" % [_menu_bottom(bare), desc.position.y])
	bare.queue_free()
	assert_lte(_menu_bottom(menu), desc.position.y,
		"the buy list must end at the description panel, not on top of it. bottom=%s desc=%s" % [_menu_bottom(menu), desc.position.y])
	assert_gt(menu._max_visible_rows, 1,
		"the shelf still shows a window of rows")
	assert_lt(menu._max_visible_rows, menu.menu_items.size(),
		"a shelf longer than that window must scroll")
	await get_tree().create_timer(0.25, true, false, true).timeout


func test_page_down_moves_a_long_shelf_and_stops_on_the_last_row() -> void:
	var shop := _item_shop()
	var menu: Win98Menu = shop.current_menu
	menu._can_accept_input = true
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_PAGEDOWN
	menu._input(ev)
	assert_eq(menu.selected_index, MenuPaging.PAGE_ROWS,
		"page down jumps a screen of rows, not one")
	for _i in 4:
		menu._input(ev)
	assert_eq(menu.selected_index, menu.menu_items.size() - 1,
		"page down clamps on the last row instead of wrapping to the top")
	assert_gt(menu._scroll_offset, 0,
		"the last row scrolls into the window")
	var up := InputEventKey.new()
	up.pressed = true
	up.keycode = KEY_PAGEUP
	menu._input(up)
	assert_eq(menu.selected_index, menu.menu_items.size() - 1 - MenuPaging.PAGE_ROWS,
		"page up jumps back by the same screen")
	await get_tree().create_timer(0.25, true, false, true).timeout


func test_a_short_shop_menu_and_a_battle_menu_do_not_page() -> void:
	var shop := _item_shop()
	shop._open_main_menu()
	var main: Win98Menu = shop.current_menu
	assert_eq(main._max_visible_rows, 0, "Buy/Sell/Exit fits; it must not scroll")
	assert_lte(_menu_bottom(main), shop.description_panel.position.y,
		"the short menu stays above the description")
	main._can_accept_input = true
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_PAGEDOWN
	main._input(ev)
	assert_eq(main.selected_index, 0, "a menu that fits does not page")

	var battle := Win98MenuScript.new()
	add_child_autofree(battle)
	var rows: Array = []
	for i in 30:
		rows.append({"id": "r%d" % i, "label": "Row %d" % i})
	battle.battle_mode = true
	battle.setup("Command", rows, Vector2(100, 100), "fighter")
	battle._can_accept_input = true
	battle._input(ev)
	assert_eq(battle.selected_index, 0,
		"page down must not steal a battle menu — L/R there are Defer and Advance")
	await get_tree().create_timer(0.25, true, false, true).timeout
