extends GutTest

## The equipment list's footer says X unequips. X is also the first key on ui_cancel, and that
## branch sat ahead of the unequip check, so a keyboard press went back to the slot list and
## left the piece on. A pad's west face still unequipped. Escape must keep going back.


func _weapon_id() -> String:
	for id in EquipmentSystem.weapons.keys():
		return str(id)
	return ""


func _menu_with(weapon_id: String) -> EquipmentMenu:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "KeyTester"
	EquipmentSystem.equip_weapon(c, weapon_id)
	var menu: EquipmentMenu = EquipmentMenu.new()
	add_child_autofree(menu)
	menu.character = c
	menu.selected_slot = 0
	menu.mode = menu.Mode.ITEM_SELECT
	menu.visible = true
	return menu


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func test_pressing_x_unequips_instead_of_only_going_back() -> void:
	var weapon_id := _weapon_id()
	assert_ne(weapon_id, "", "PRECONDITION: EquipmentSystem must know at least one weapon")
	var menu := _menu_with(weapon_id)
	assert_eq(menu.character.equipped_weapon, weapon_id, "PRECONDITION: the weapon is on before the press")
	menu._input(_key(KEY_X))
	assert_eq(menu.character.equipped_weapon, "",
		"X on the item list must take the weapon off. ui_cancel matches that key and used to win, so the press only returned to the slot list")
	assert_eq(menu.mode, menu.Mode.SLOT_SELECT,
		"a successful unequip returns to the slot list, the same place the pad route leaves you")


func test_escape_still_returns_to_the_slot_list_without_unequipping() -> void:
	var weapon_id := _weapon_id()
	assert_ne(weapon_id, "", "PRECONDITION: EquipmentSystem must know at least one weapon")
	var menu := _menu_with(weapon_id)
	menu._input(_key(KEY_ESCAPE))
	assert_eq(menu.character.equipped_weapon, weapon_id,
		"Escape is back, not unequip — stealing it would drop gear when the player only wanted the previous screen")
	assert_eq(menu.mode, menu.Mode.SLOT_SELECT,
		"Escape must leave the item list for the slot list")


func test_item_list_cancel_hint_is_not_the_unequip_key() -> void:
	var weapon_id := _weapon_id()
	assert_ne(weapon_id, "", "PRECONDITION: EquipmentSystem must know at least one weapon")
	var menu := _menu_with(weapon_id)
	menu._build_ui()
	var footer := ""
	for child in menu.get_children():
		if child is Label and str(child.text).contains("Unequip"):
			footer = str(child.text)
	assert_ne(footer, "", "PRECONDITION: the item-list footer must be on screen")
	assert_true(footer.contains("X: Unequip") or footer.ends_with("X: Unequip") or footer.contains("/X: Unequip") or footer.contains(" X: Unequip"),
		"the footer must still name X as unequip: %s" % footer)
	assert_false(footer.contains("X/RClick: Cancel") or footer.contains("X/RClick: Back"),
		"Cancel must not name X on this screen — that key unequips, and Escape is the press that goes back. Footer: %s" % footer)
