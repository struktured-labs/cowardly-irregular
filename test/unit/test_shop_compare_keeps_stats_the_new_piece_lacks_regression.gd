extends GutTest

## Blacksmith buy text compared only the new piece's stat_mods. Iron Armor
## carries Max HP and a Speed penalty that Cloth Robe does not list, so the
## preview hid -250 HP and +3 Speed — the stats that actually change.

const SHOP_PATH := "res://src/exploration/ShopScene.gd"


func _restore_party(prior: Array) -> void:
	var typed: Array[Dictionary] = []
	for entry in prior:
		if entry is Dictionary:
			typed.append((entry as Dictionary).duplicate(true))
	GameState.player_party = typed


func test_replacing_iron_armor_with_a_robe_names_the_hp_and_speed_you_lose() -> void:
	var prior: Array = GameState.player_party.duplicate(true)
	var wearing: Array[Dictionary] = [{
		"name": "Fighter",
		"equipped_weapon": "iron_sword",
		"equipped_armor": "iron_armor",
		"equipped_accessory": "",
	}]
	GameState.player_party = wearing
	var shop: Object = load(SHOP_PATH).new()
	add_child_autofree(shop)
	shop.shop_type = shop.ShopType.BLACKSMITH
	shop.current_mode = shop.ShopMode.BUY
	var robe: Dictionary = EquipmentSystem.get_armor("cloth_robe")
	var iron: Dictionary = EquipmentSystem.get_armor("iron_armor")
	assert_false(robe.is_empty(), "CONTROL: cloth_robe must be in the catalog")
	assert_eq(int(iron.get("stat_mods", {}).get("max_hp", 0)), 250, "CONTROL: iron_armor's HP bonus is the number this arm judges")
	assert_eq(int(iron.get("stat_mods", {}).get("speed", 0)), -3, "CONTROL: iron_armor's speed penalty is the number this arm judges")
	var delta: Dictionary = shop._compare_equipment("cloth_robe", robe)
	assert_eq(int(delta.get("max_hp", 0)), -250,
		"swapping Iron Armor for a robe that lists no HP must show -250 Max HP, not silence")
	assert_eq(int(delta.get("speed", 0)), 3,
		"dropping Iron Armor's speed penalty must show +3 Speed")
	shop._update_description_for_item("cloth_robe")
	var text: String = str(shop.description_label.text)
	assert_true(text.contains("Max HP: +0  (-250)"),
		"the buy panel hid the Max HP loss. Got:\n%s" % text)
	assert_true(text.contains("Speed: +0  (+3)"),
		"the buy panel hid the Speed change. Got:\n%s" % text)
	_restore_party(prior)
