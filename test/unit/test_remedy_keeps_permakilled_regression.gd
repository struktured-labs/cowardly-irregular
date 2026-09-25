extends GutTest

## Remedy's cure_all_status wiped status_effects outright. Poison went, and so
## did the permadeath marker, so a Phoenix Down afterwards stood the ally up.
## Battle start already keeps the marker (clear_transient_statuses). The tonic,
## the field menu, and any autobattle item use share ItemSystem.use_item, so
## that one clear was the hole. Esuna's ailment list never names permakilled.
## Time Mage undo_death still has to be able to lift the marker on purpose.


func _person(who: String, alive: bool) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": who, "max_hp": 200, "max_mp": 40,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	if not alive:
		c.die()
	return c


func test_a_remedy_cures_poison_and_leaves_permadeath() -> void:
	var remedy: Dictionary = ItemSystem.get_item("remedy")
	assert_false(remedy.is_empty(), "CONTROL: the shipped Remedy is loaded")
	assert_true(bool(remedy.get("effects", {}).get("cure_all_status", false)),
		"CONTROL: Remedy is the cure-all — this is the path under test")
	var erased := _person("Bram", false)
	erased.add_status("permakilled")
	erased.add_status("poison", 5)
	var user := _person("Theron", true)
	assert_true(erased.has_status("permakilled"), "CONTROL: the marker is on before the tonic")
	assert_false(erased.is_alive, "CONTROL: they are down")

	assert_true(ItemSystem.use_item(user, "remedy", [erased] as Array[Combatant]))

	assert_false(erased.has_status("poison"), "poison is what a Remedy is for")
	assert_true(erased.has_status("permakilled"),
		"the tonic must not unwrite permadeath — without the marker, Phoenix Down treats them as a normal KO")
	assert_eq(int(erased.status_durations.get("permakilled", 0)), -1,
		"the marker stays permanent; a 3-turn duration would let it wear off")
	assert_false(erased.is_alive, "a cure is not a raise")
	assert_eq(erased.current_hp, 0, "and it must not restore HP")
	erased.revive(erased.max_hp)
	assert_false(erased.is_alive, "revive() still refuses once the marker has survived the tonic")
	assert_eq(erased.current_hp, 0, "a refused revive must not restore HP")


func test_a_remedy_still_clears_an_ordinary_ailment() -> void:
	var standing := _person("Milo", true)
	standing.add_status("poison", 5)
	standing.add_status("blind", 3)
	var user := _person("Theron", true)
	assert_true(ItemSystem.use_item(user, "remedy", [standing] as Array[Combatant]))
	assert_false(standing.has_status("poison"), "a living ally's poison still clears")
	assert_false(standing.has_status("blind"), "and their other ailments clear too")
	assert_false(standing.has_status("permakilled"), "a Remedy must not invent a permadeath marker")
	assert_true(standing.is_alive)


func test_permadeath_alone_is_not_a_reason_to_spend_a_remedy() -> void:
	var erased := _person("Bram", false)
	erased.add_status("permakilled")
	assert_eq(ItemSystem.ineffective_use_reason("remedy", [erased]), "Bram has no status to cure",
		"the field menu must keep the tonic — the only status on them is the one a Remedy cannot lift")
	assert_eq(ItemSystem.ineffective_use_reason("remedy", [erased], true), "Bram has no status to cure",
		"the battle item row uses the same gate")
	var poisoned := _person("Milo", false)
	poisoned.add_status("permakilled")
	poisoned.add_status("poison", 4)
	assert_eq(ItemSystem.ineffective_use_reason("remedy", [poisoned]), "",
		"poison on a permakilled ally is still a real use — the tonic cures that and leaves the marker")


func test_undo_death_still_lifts_a_marker_a_remedy_could_not() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var erased := _person("Bram", false)
	erased.add_status("permakilled")
	erased.add_status("poison", 3)
	var user := _person("Theron", true)
	ItemSystem.use_item(user, "remedy", [erased] as Array[Combatant])
	assert_true(erased.has_status("permakilled"), "CONTROL: the tonic left the marker for undo_death to remove")
	bm._execute_meta_ability(user, {"id": "undo_death", "meta_effect": "reverse_permadeath"}, [erased])
	assert_false(erased.has_status("permakilled"), "Time Mage undo_death still removes the marker on purpose")
	assert_true(erased.is_alive, "and then stands them up")
	assert_gt(erased.current_hp, 0)


func test_the_field_menu_keeps_a_remedy_that_cannot_lift_permadeath() -> void:
	var erased := _person("Bram", false)
	erased.add_status("permakilled")
	var menu: ItemsMenu = await _menu_for(erased, 1)
	menu._use_selected_item()
	assert_eq(int(menu.inventory.get("remedy", 0)), 1, "the bag count the menu draws from must stay 1")
	assert_eq(erased.get_item_count("remedy"), 1, "the ally's own stack must stay 1 — the tonic was not spent")
	assert_true(erased.has_status("permakilled"), "and the marker is still on them")
	assert_false(erased.is_alive)


func test_the_field_menu_spends_a_remedy_on_poison_and_keeps_permadeath() -> void:
	var erased := _person("Bram", false)
	erased.add_status("permakilled")
	erased.add_status("poison", 5)
	var menu: ItemsMenu = await _menu_for(erased, 1)
	menu._use_selected_item()
	assert_eq(int(menu.inventory.get("remedy", 0)), 0, "poison is a real use, so the tonic leaves the bag")
	assert_eq(erased.get_item_count("remedy"), 0)
	assert_false(erased.has_status("poison"), "the poison is gone")
	assert_true(erased.has_status("permakilled"), "the permadeath marker stays, so a later Phoenix Down still refuses")
	assert_false(erased.is_alive)
	erased.revive(100)
	assert_false(erased.is_alive, "the menu path must not leave them revivable")


func _menu_for(member: Combatant, qty: int) -> ItemsMenu:
	var menu := ItemsMenu.new()
	add_child_autofree(menu)
	await get_tree().process_frame
	var data: Dictionary = ItemSystem.get_item("remedy")
	assert_false(data.is_empty(), "CONTROL: remedy is loaded")
	member.add_item("remedy", qty)
	menu.party = [member]
	menu.inventory = {"remedy": qty}
	menu._item_list = [{"id": "remedy", "quantity": qty, "data": data}]
	menu.selected_item_index = 0
	menu.selected_target_index = 0
	return menu


func test_esuna_clears_poison_and_leaves_permadeath() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	# Cleanse only runs on a living target. The marker is not in ESUNA_AILMENTS, so it stays.
	var standing := _person("Bram", true)
	standing.add_status("permakilled")
	standing.add_status("poison", 5)
	var caster := _person("Cleric", true)
	bm._execute_support_ability(caster, {"id": "esuna", "effect": "cleanse"}, [standing])
	assert_false(standing.has_status("poison"), "Purgatio still cures poison")
	assert_true(standing.has_status("permakilled"), "Esuna's ailment list must not include permadeath")
