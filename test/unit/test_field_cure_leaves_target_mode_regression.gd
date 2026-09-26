extends GutTest

## Pause → Items stays in target-select after a potion so a second drink does not
## need reselecting. Cure items used that same stay after the last poison, silence,
## or blind was already gone, so the next confirm error-beeped and spent nothing.
## Another ally who still has the ailment — including a KO — must stay on targets.
## Remedy must not treat permadeath as a reason to stay.


const ItemsMenuScript = preload("res://src/ui/ItemsMenu.gd")


func _person(who: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = who
	c.max_hp = 100
	c.max_mp = 20
	add_child_autofree(c)
	c.current_hp = 80
	c.current_mp = 20
	c.is_alive = true
	return c


func _footer(menu: ItemsMenu) -> String:
	var found := ""
	for c in menu.get_children():
		if not (c is Label) or c.is_queued_for_deletion():
			continue
		var text := str(c.text)
		if "Page" in text or "Select Target" in text:
			found = text
	return found


func _menu(item_id: String, members: Array, qty: int, target: int) -> ItemsMenu:
	var menu := ItemsMenuScript.new()
	add_child_autofree(menu)
	await get_tree().process_frame
	var data: Dictionary = ItemSystem.get_item(item_id)
	assert_false(data.is_empty(), "CONTROL: %s is loaded" % item_id)
	members[0].add_item(item_id, qty)
	menu.party = members
	menu.inventory = {item_id: qty}
	menu._item_list = [{"id": item_id, "quantity": qty, "data": data}]
	menu.selected_item_index = 0
	menu.selected_target_index = target
	menu.mode = 1
	return menu


func test_the_last_poison_sends_the_antidote_back_to_the_item_list() -> void:
	var bram := _person("Bram")
	bram.add_status("poison", 5)
	var milo := _person("Milo")
	var menu: ItemsMenu = await _menu("antidote", [bram, milo], 2, 0)
	menu._use_selected_item()
	assert_false(bram.has_status("poison"), "the antidote still clears poison")
	assert_false(milo.has_status("poison"), "CONTROL: Milo was never poisoned")
	assert_eq(int(menu.inventory.get("antidote", 0)), 1, "one antidote remains in the bag")
	assert_eq(bram.get_item_count("antidote"), 1, "one antidote remains on Bram's stack")
	assert_eq(menu.mode, 0, "nobody is still poisoned, so the next confirm must be the item list")
	assert_string_contains(_footer(menu), "Page", "the list footer is what the player sees after the last cure")


func test_a_poisoned_ko_keeps_the_antidote_on_the_target_list() -> void:
	var bram := _person("Bram")
	bram.add_status("poison", 5)
	var milo := _person("Milo")
	milo.die()
	milo.add_status("poison", 4)
	var menu: ItemsMenu = await _menu("antidote", [bram, milo], 2, 0)
	menu._use_selected_item()
	assert_false(bram.has_status("poison"), "Bram's poison is the one this confirm spent")
	assert_true(milo.has_status("poison"), "a KO from the poison tick still carries poison onto the field")
	assert_false(milo.is_alive, "the antidote is not a raise")
	assert_eq(int(menu.inventory.get("antidote", 0)), 1)
	assert_eq(menu.mode, 1, "Milo can still take the next antidote, so target select stays open")
	assert_string_contains(_footer(menu), "Select Target")


func test_a_remedy_returns_to_the_list_when_only_permadeath_remains() -> void:
	var bram := _person("Bram")
	bram.die()
	bram.add_status("permakilled")
	bram.add_status("poison", 5)
	var menu: ItemsMenu = await _menu("remedy", [bram], 2, 0)
	menu._use_selected_item()
	assert_false(bram.has_status("poison"), "the tonic still cures poison")
	assert_true(bram.has_status("permakilled"), "permadeath is not an ailment a Remedy lifts")
	assert_false(bram.is_alive)
	assert_eq(int(menu.inventory.get("remedy", 0)), 1, "a second tonic is still in the bag")
	assert_eq(bram.get_item_count("remedy"), 1)
	assert_eq(menu.mode, 0, "permadeath alone must not keep the target list open for another beep")
	assert_string_contains(_footer(menu), "Page")
