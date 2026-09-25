extends GutTest

## Phoenix Down on a permakilled ally. revive() refuses — that ally stays
## dead — but use_item still returns true, and the pause-menu Items path
## treated that true as success. Confirm played the heal sound, the feather
## left the bag, and the ally was still KO. A normal KO must still cost
## exactly one feather and stand up. A living ally in the same list can
## still receive the bundled heal outside battle; in battle the corpse
## is not a valid Phoenix Down target either.


const ItemsMenuScript = preload("res://src/ui/ItemsMenu.gd")


func _person(who: String, hp: int, max_hp: int) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = who
	c.max_hp = max_hp
	c.max_mp = 20
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = 20
	c.is_alive = hp > 0
	return c


func _down(who: String, permakilled: bool) -> Combatant:
	var c := _person(who, 100, 100)
	c.die()
	if permakilled:
		c.add_status("permakilled")
	return c


func _toast_text(node: Node) -> String:
	var found := ""
	for c in node.get_children():
		if c is Label and str(c.text) != "":
			found = str(c.text)
		var nested := _toast_text(c)
		if nested != "":
			found = nested
	return found


func _menu_for(member: Combatant, qty: int) -> ItemsMenu:
	var menu := ItemsMenuScript.new()
	add_child_autofree(menu)
	await get_tree().process_frame
	var data: Dictionary = ItemSystem.get_item("phoenix_down")
	assert_false(data.is_empty(), "CONTROL: phoenix_down is loaded")
	member.add_item("phoenix_down", qty)
	menu.party = [member]
	menu.inventory = {"phoenix_down": qty}
	menu._item_list = [{"id": "phoenix_down", "quantity": qty, "data": data}]
	menu.selected_item_index = 0
	menu.selected_target_index = 0
	return menu


func test_a_permakilled_corpse_is_not_a_phoenix_down_target() -> void:
	var bram := _down("Bram", true)
	assert_false(bram.is_alive, "CONTROL: Bram is KO")
	assert_true(bram.has_status("permakilled"), "CONTROL: the permadeath marker is on him")
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [bram]), "Bram can't be revived",
		"the field menu must be told to keep the feather — revive() will not stand him up")
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [bram], true), "Bram can't be revived",
		"the battle item row uses the same gate and must not offer a turn that fizzles")
	var milo := _down("Milo", true)
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [bram, milo]), "No one can be revived")
	var ordinary := _down("Theron", false)
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [ordinary]), "",
		"a normal KO is still what Phoenix Down is for")
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [bram, ordinary]), "",
		"one ally who can actually stand back up makes the use real")
	# use_item still reports success and still does not revive. The menu is what must not spend.
	assert_true(ItemSystem.use_item(bram, "phoenix_down", [bram] as Array[Combatant]))
	assert_false(bram.is_alive, "revive() still refuses a permakilled ally")
	assert_eq(bram.current_hp, 0)
	var hurt := _person("Lena", 10, 80)
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [hurt, bram]), "",
		"outside battle the bundled 25% heal on a living ally in the same list is still a real use")


func test_the_field_menu_keeps_the_feather_and_leaves_them_down() -> void:
	var bram := _down("Bram", true)
	var menu: ItemsMenu = await _menu_for(bram, 1)
	menu._use_selected_item()
	assert_eq(int(menu.inventory.get("phoenix_down", 0)), 1, "the bag count the menu draws from must stay 1")
	assert_eq(bram.get_item_count("phoenix_down"), 1, "the ally's own stack must stay 1 — the feather was not spent")
	assert_false(bram.is_alive)
	assert_eq(bram.current_hp, 0, "HP stays 0; the heal sound used to play over a corpse")
	assert_eq(_toast_text(menu), "Bram can't be revived")


func test_a_normal_ko_still_costs_one_feather_and_stands_up() -> void:
	var milo := _down("Milo", false)
	var menu: ItemsMenu = await _menu_for(milo, 2)
	menu._use_selected_item()
	assert_eq(int(menu.inventory.get("phoenix_down", 0)), 1, "exactly one feather leaves the shared count")
	assert_eq(milo.get_item_count("phoenix_down"), 1, "exactly one feather leaves Milo's stack, not both")
	assert_true(milo.is_alive)
	assert_eq(milo.current_hp, 25, "Phoenix Down stands them up at 25% of 100 HP")
