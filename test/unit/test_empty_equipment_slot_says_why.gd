extends GutTest

## Confirming a weapon, armor, or accessory slot with nothing in the pool played menu_error and
## stayed on the stats panel. "No items available" is drawn only on the item list, and that list
## never opens when the pool is empty, so the buzz had no sentence attached. The same opener
## serves the confirm button and a click, and it names the slot.

const SRC := "res://src/ui/EquipmentMenu.gd"


func after_each() -> void:
	for layer in Toast._active_layers.duplicate():
		if is_instance_valid(layer):
			layer.free()
	Toast._active_layers.clear()


func _menu(weapons: Array, armors: Array, accessories: Array) -> EquipmentMenu:
	var who := Combatant.new()
	autofree(who)
	who.combatant_name = "Tester"
	var menu := EquipmentMenu.new()
	add_child_autofree(menu)
	menu.character = who
	menu.available_weapons = weapons
	menu.available_armors = armors
	menu.available_accessories = accessories
	return menu


func _toast_texts(menu: Node) -> Array:
	var found: Array = []
	_collect_toasts(menu, found)
	return found


func _collect_toasts(node: Node, found: Array) -> void:
	for child in node.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is CanvasLayer:
			for label in child.get_children():
				if label is Label and not found.has(label.text):
					found.append(label.text)
			continue
		_collect_toasts(child, found)


func _cursor_slot(node: Node) -> String:
	for child in node.get_children():
		if child is CanvasLayer or child.is_queued_for_deletion():
			continue
		if child.name == "Cursor" and child is Label and (child as Label).text == ">":
			for sib in node.get_children():
				if sib is Label and ["Weapon", "Armor", "Accessory"].has((sib as Label).text):
					return (sib as Label).text
		var nested := _cursor_slot(child)
		if nested != "":
			return nested
	return ""


func _fn_body(fn: String) -> String:
	var src := FileAccess.get_file_as_string(SRC)
	var i := src.find("func " + fn)
	assert_gt(i, -1, "EquipmentMenu must still define %s" % fn)
	var j := src.find("\nfunc ", i + 1)
	return src.substr(i, (j - i) if j > -1 else src.length() - i)


func test_an_empty_weapon_slot_says_there_are_no_weapons() -> void:
	var menu := _menu([], [], [])
	menu.selected_slot = 0
	menu._try_open_selected_slot()
	assert_eq(menu.mode, menu.Mode.SLOT_SELECT, "an empty pool must stay on the slot list")
	assert_eq(_toast_texts(menu), ["No weapons to equip"])


func test_an_empty_armor_slot_names_armor() -> void:
	var menu := _menu(["practice_blade"], [], ["lucky_charm"])
	menu.selected_slot = 1
	menu._try_open_selected_slot()
	assert_eq(menu.mode, menu.Mode.SLOT_SELECT)
	assert_eq(_toast_texts(menu), ["No armor to equip"])


func test_an_empty_accessory_slot_names_accessories() -> void:
	var menu := _menu(["practice_blade"], ["leather_vest"], [])
	menu.selected_slot = 2
	menu._try_open_selected_slot()
	assert_eq(menu.mode, menu.Mode.SLOT_SELECT)
	assert_eq(_toast_texts(menu), ["No accessories to equip"])


func test_a_stocked_slot_opens_the_list_without_a_warning() -> void:
	var menu := _menu(["practice_blade"], [], [])
	menu.selected_slot = 0
	menu._try_open_selected_slot()
	assert_eq(menu.mode, menu.Mode.ITEM_SELECT, "a stocked slot must open the item list")
	assert_eq(menu.selected_item_index, 0)
	assert_eq(_toast_texts(menu), [], "opening a stocked slot is not an error")


func test_clicking_an_empty_slot_moves_the_cursor_and_names_it() -> void:
	var menu := _menu(["practice_blade"], [], [])
	menu.selected_slot = 0
	menu._on_slot_click(1)
	assert_eq(menu.selected_slot, 1)
	assert_eq(menu.mode, menu.Mode.SLOT_SELECT)
	assert_eq(_toast_texts(menu), ["No armor to equip"])
	assert_eq(_cursor_slot(menu), "Armor", "the highlight has to follow the slot the message names")


func test_a_click_during_item_select_does_not_change_slots() -> void:
	var menu := _menu([], [], [])
	menu.mode = menu.Mode.ITEM_SELECT
	menu.selected_slot = 0
	menu._on_slot_click(2)
	assert_eq(menu.selected_slot, 0)
	assert_eq(menu.mode, menu.Mode.ITEM_SELECT)
	assert_eq(_toast_texts(menu), [])


func test_mashing_confirm_replaces_the_warning_instead_of_stacking_it() -> void:
	var menu := _menu([], [], [])
	menu._try_open_selected_slot()
	menu._try_open_selected_slot()
	assert_eq(_toast_texts(menu), ["No weapons to equip"])


func test_confirm_and_click_share_the_opener() -> void:
	var confirm := _fn_body("_handle_slot_input")
	var click := _fn_body("_on_slot_click")
	assert_true(confirm.contains("_try_open_selected_slot()"), "confirm must use the shared opener")
	assert_false(confirm.contains("menu_error"), "confirm must not reject on its own")
	assert_true(click.contains("_try_open_selected_slot()"), "a click must use the shared opener")
	assert_false(click.contains("menu_error"), "a click must not reject on its own")
