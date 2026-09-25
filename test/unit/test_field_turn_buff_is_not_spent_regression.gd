extends GutTest

## Power Drink, Speed Tonic, Defense Tonic and Magic Tonic are sold in the
## village shop and listed in the pause-menu bag. Confirming one there used
## to spend it: use_item appends a 3-turn buff, and the next battle's
## start_battle clears active_buffs before any turn, so the tonic never
## changed a swing. Smoke Bomb already refuses with "only works in battle".
## These four are the same kind of item. In a fight they still apply,
## including on someone at full HP.


const ItemsMenuScript = preload("res://src/ui/ItemsMenu.gd")

const TURN_BUFFS := ["power_drink", "speed_tonic", "defense_tonic", "magic_tonic"]


func _person(who: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = who
	c.max_hp = 100
	c.max_mp = 20
	add_child_autofree(c)
	c.current_hp = 100
	c.current_mp = 20
	c.is_alive = true
	return c


func test_a_turn_buff_is_refused_outside_battle_and_allowed_inside() -> void:
	for item_id in TURN_BUFFS:
		var data: Dictionary = ItemSystem.get_item(item_id)
		assert_false(data.is_empty(), "CONTROL: %s is loaded" % item_id)
		assert_true(data.get("effects", {}).has("add_buff"), "CONTROL: %s is a turn buff" % item_id)
		var name := str(data.get("name", item_id))
		var bram := _person("Bram")
		assert_eq(ItemSystem.ineffective_use_reason(item_id, [bram]), "%s only works in battle" % name,
			"the pause menu must be told not to spend %s" % name)
		assert_eq(ItemSystem.ineffective_use_reason(item_id, [bram], true), "",
			"%s is still a real action once a battle is underway" % name)


func test_the_field_menu_keeps_the_power_drink() -> void:
	var menu := ItemsMenuScript.new()
	add_child_autofree(menu)
	await get_tree().process_frame
	var bram := _person("Bram")
	bram.add_item("power_drink", 1)
	var data: Dictionary = ItemSystem.get_item("power_drink")
	assert_false(data.is_empty(), "CONTROL: power_drink is loaded")
	menu.party = [bram]
	menu.inventory = {"power_drink": 1}
	menu._item_list = [{"id": "power_drink", "quantity": 1, "data": data}]
	menu.selected_item_index = 0
	menu.selected_target_index = 0
	menu.mode = 1
	menu._use_selected_item()
	assert_eq(int(menu.inventory.get("power_drink", 0)), 1, "the bag count the menu draws from must stay 1")
	assert_eq(bram.get_item_count("power_drink"), 1, "Bram's stack must stay 1 — the drink was not spent")
	assert_eq(bram.active_buffs.size(), 0, "no attack buff is applied from the pause menu")
	# The executor still applies the buff. Battle is what calls it, after the menu has allowed the row.
	var milo := _person("Milo")
	assert_true(ItemSystem.use_item(milo, "power_drink", [milo] as Array[Combatant]))
	assert_eq(milo.active_buffs.size(), 1, "CONTROL: use_item still creates the attack buff a battle spends the drink for")
