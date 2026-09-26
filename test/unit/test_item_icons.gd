extends GutTest

## Every item and piece of gear resolves to a real icon, and the shop, bag,
## and battle lists actually draw one beside the name.

const ShopSceneScript := preload("res://src/exploration/ShopScene.gd")
const ItemsMenuScript := preload("res://src/ui/ItemsMenu.gd")
const EquipMenuScript := preload("res://src/ui/EquipmentMenu.gd")
const MenuScript := preload("res://src/battle/BattleCommandMenu.gd")
const Win98MenuScript := preload("res://src/ui/Win98Menu.gd")


func test_every_item_and_equipment_id_resolves_to_a_real_icon() -> void:
	var ids: Array[String] = []
	for item_id in ItemSystem.items.keys():
		ids.append(str(item_id))
	for pool_name in ["weapons", "armors", "accessories"]:
		var pool: Dictionary = EquipmentSystem.get(pool_name)
		for item_id in pool.keys():
			ids.append(str(item_id))
	assert_gt(ids.size(), 100, "CONTROL: the catalogs were actually loaded")
	var missing: Array[String] = []
	for item_id in ids:
		var key := ItemIcons.icon_key(item_id)
		var path := ItemIcons.png_path(key)
		if not FileAccess.file_exists(path):
			missing.append("%s -> %s" % [item_id, key])
			continue
		var tex := ItemIcons.tinted(item_id)
		if tex == null or tex.get_width() < 8 or tex.get_height() < 8:
			missing.append("%s texture" % item_id)
			continue
		var img := tex.get_image()
		if img == null or not _has_ink(img):
			missing.append("%s blank" % item_id)
	assert_eq(missing, [], "an id resolved to a missing or blank icon: %s" % str(missing))


func test_named_categories_and_a_default_for_anything_else() -> void:
	assert_eq(ItemIcons.icon_key("potion"), "potion")
	assert_eq(ItemIcons.icon_key("hi_ether"), "ether")
	assert_eq(ItemIcons.icon_key("speed_tonic"), "tonic")
	assert_eq(ItemIcons.icon_key("phoenix_down"), "phoenix")
	assert_eq(ItemIcons.icon_key("smoke_bomb"), "smoke")
	assert_eq(ItemIcons.icon_key("repel"), "repel")
	assert_eq(ItemIcons.icon_key("calibrant_token"), "key")
	assert_eq(ItemIcons.icon_key("bronze_sword"), "sword")
	assert_eq(ItemIcons.icon_key("iron_dagger"), "dagger")
	assert_eq(ItemIcons.icon_key("wooden_staff"), "staff")
	assert_eq(ItemIcons.icon_key("war_axe"), "axe")
	assert_eq(ItemIcons.icon_key("piano_scythe"), "scythe")
	assert_eq(ItemIcons.icon_key("leather_armor"), "armor")
	assert_eq(ItemIcons.icon_key("mage_robe"), "robe")
	assert_eq(ItemIcons.icon_key("mourners_ledger"), "accessory")
	assert_eq(ItemIcons.icon_key("fire"), "scroll")
	assert_eq(ItemIcons.icon_key("wooden_bow"), "bow")
	assert_eq(ItemIcons.icon_key("iron_helmet"), "helmet")
	assert_eq(ItemIcons.icon_key("buckler_shield"), "shield")
	assert_eq(ItemIcons.icon_key("no_such_item_zzz"), "pouch")
	assert_ne(ItemIcons.tinted("no_such_item_zzz"), null, "an unknown id still gets the pouch, never a blank")
	assert_ne(ItemIcons.tint_color("potion"), ItemIcons.tint_color("hi_potion"),
		"two potions of different strength should not be the same color")
	for key in ["potion", "ether", "tonic", "phoenix", "smoke", "repel", "key", "sword", "dagger", "staff", "bow", "axe", "shield", "helmet", "armor", "robe", "accessory", "pouch"]:
		assert_true(FileAccess.file_exists(ItemIcons.png_path(key)), "missing icon png %s" % key)


func test_shop_buy_and_sell_rows_draw_an_icon() -> void:
	var shops := [
		[ShopSceneScript.ShopType.ITEM, "General Store", VillageShop.ITEM_INVENTORY.duplicate()],
		[ShopSceneScript.ShopType.BLACKSMITH, "Blacksmith", VillageShop.BLACKSMITH_WEAPONS.duplicate()],
		[ShopSceneScript.ShopType.BLACK_MAGIC, "Black Magic", VillageShop.BLACK_MAGIC_INVENTORY.duplicate()],
	]
	for spec in shops:
		var shop: ShopScene = ShopSceneScript.new()
		add_child_autofree(shop)
		shop.setup(spec[0], spec[1], spec[2])
		shop._open_buy_menu()
		_assert_menu_icons(shop.current_menu, spec[1])
	var saved: Array = []
	for entry in GameState.player_party:
		saved.append(entry.duplicate(true))
	GameState.player_party.clear()
	GameState.player_party.append({"name": "Bram", "inventory": {"potion": 2, "ether": 1}})
	var shop: ShopScene = ShopSceneScript.new()
	add_child_autofree(shop)
	shop.setup(shop.ShopType.ITEM, "General Store", VillageShop.ITEM_INVENTORY.duplicate())
	shop._open_sell_menu()
	_assert_menu_icons(shop.current_menu, "Sell")
	assert_gte(shop.current_menu.menu_items.size(), 2, "CONTROL: the sell list had the stocked potions")
	var clip := shop.current_menu.find_child("ItemClip", true, false) as Control
	assert_not_null(clip, "the shelf has no row window")
	assert_eq(int(clip.size.y) % shop.current_menu._row_height(), 0, "the window height must be a whole number of rows")
	assert_true(clip.clip_contents, "a partial row can paint into the frame padding")
	GameState.player_party.clear()
	for entry in saved:
		GameState.player_party.append(entry)


func test_the_bag_draws_an_icon_on_every_row() -> void:
	var menu: ItemsMenu = ItemsMenuScript.new()
	add_child_autofree(menu)
	menu.setup([], {"potion": 3, "ether": 1, "phoenix_down": 1, "antidote": 2})
	await get_tree().process_frame
	assert_gt(menu._item_labels.size(), 0, "CONTROL: the bag rendered rows")
	for row in menu._item_labels:
		var icon := row.get_node_or_null("ItemIcon") as TextureRect
		assert_not_null(icon, "a bag row has no icon")
		assert_ne(icon.texture, null)
		assert_eq(icon.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
		assert_eq(int(icon.size.y), 32, "the bag icon should be the 16px art at 2x")
		var name_label := row.get_node_or_null("Name") as Label
		assert_not_null(name_label)
		assert_gt(name_label.text.length(), 0, "the name is still there beside the icon")
		assert_true(_shares_a_line(icon, name_label), "the bag icon is not on the name's line")


func test_battle_item_rows_draw_an_icon() -> void:
	var scene: Node = load("res://src/battle/BattleScene.gd").new()
	add_child_autofree(scene)
	await get_tree().process_frame
	var pc := Combatant.new()
	pc.combatant_name = "Bram"
	pc.is_alive = true
	pc.max_hp = 40
	pc.current_hp = 40
	pc.job = JobSystem.get_job("fighter")
	add_child_autofree(pc)
	pc.add_item("potion", 2)
	pc.add_item("ether", 1)
	var enemy := Combatant.new()
	enemy.combatant_name = "Slime"
	enemy.is_alive = true
	enemy.max_hp = 10
	enemy.current_hp = 10
	add_child_autofree(enemy)
	scene.party_members.assign([pc])
	scene.test_enemies.assign([enemy])
	var menu = MenuScript.new(scene)
	var built: Array = menu.build_command_menu_items_with_targets(pc)
	var item_rows: Array = []
	var built_ids: Array[String] = []
	for row in built:
		built_ids.append(str(row.get("id", "")))
		if str(row.get("id", "")) == "item_menu":
			item_rows = row.get("submenu", [])
	assert_gte(item_rows.size(), 2, "CONTROL: the battle item submenu listed the bag. Got %s" % str(built_ids))
	for row in item_rows:
		assert_ne(str(row.get("icon_id", "")), "", "battle item row %s has no icon_id" % row.get("label", ""))
	var popup := Win98MenuScript.new()
	add_child_autofree(popup)
	popup.battle_mode = true
	popup.setup("Item", item_rows, Vector2(80, 80), "fighter")
	_assert_menu_icons(popup, "battle item")


func test_equipment_rows_draw_an_icon() -> void:
	var menu: EquipmentMenu = EquipMenuScript.new()
	add_child_autofree(menu)
	var pc := Combatant.new()
	pc.combatant_name = "Bram"
	pc.equipped_weapon = "bronze_sword"
	add_child_autofree(pc)
	menu.character = pc
	menu.selected_slot = 0
	var row := menu._create_item_row("bronze_sword", 0)
	var icon := row.get_node_or_null("ItemIcon") as TextureRect
	assert_not_null(icon, "an equipment choice has no icon")
	assert_ne(icon.texture, null)
	assert_eq(icon.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(int(icon.size.y), 32)
	var choice_name := row.get_node_or_null("Name") as Label
	assert_true(_shares_a_line(icon, choice_name), "the weapon choice icon is not on the name's line")
	var slot := menu._create_slot_row(0)
	var slot_icon := slot.get_node_or_null("ItemIcon") as TextureRect
	var slot_name := slot.get_node_or_null("EquippedName") as Label
	assert_not_null(slot_icon, "the equipped weapon row has no icon")
	assert_true(_shares_a_line(slot_icon, slot_name), "the equipped slot icon is not on the name's line")


func test_a_chest_and_a_victory_drop_show_an_icon() -> void:
	var chest := TreasureChest.new()
	chest.chest_id = "item_icon_probe"
	chest.contents_type = "item"
	chest.contents_id = "potion"
	add_child_autofree(chest)
	chest._set_loot_icon("potion")
	var loot := chest.dialogue_box.get_node_or_null("LootIcon") as TextureRect
	assert_not_null(loot, "the chest popup has no icon")
	assert_eq(loot.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_true(FileAccess.get_file_as_string("res://src/exploration/TreasureChest.gd").contains("dialogue_label.position = Vector2(-112, -102)"),
		"the chest label geometry the layout test pins is still the one on disk")

	var overlay := VictoryOverlay.new()
	add_child_autofree(overlay)
	overlay._build_loot_strip({
		"item_drops": [{"item": "potion", "name": "Potion", "qty": 1}],
		"total_gold": 10,
		"injuries": [],
		"bonuses": [],
	}, false)
	var strip := overlay.get_node_or_null("LootStrip")
	assert_not_null(strip, "CONTROL: the loot strip was built")
	var drop_icon := strip.find_child("ItemIcon", true, false) as TextureRect
	assert_not_null(drop_icon, "the victory drop chip has no icon")
	assert_eq(drop_icon.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)


func _assert_menu_icons(menu: Win98Menu, where: String) -> void:
	assert_not_null(menu, "%s menu did not open" % where)
	var container := menu._get_items_container()
	assert_not_null(container, "%s has no row container" % where)
	assert_gt(menu.menu_items.size(), 0, "%s opened empty" % where)
	assert_eq(container.get_child_count(), menu.menu_items.size(), "%s did not draw every row" % where)
	for i in menu.menu_items.size():
		var row: Control = container.get_child(i)
		var icon := row.get_node_or_null("ItemIcon") as TextureRect
		assert_not_null(icon, "%s row '%s' has no icon" % [where, menu.menu_items[i].get("label", "")])
		assert_ne(icon.texture, null, "%s row '%s' icon has no texture" % [where, menu.menu_items[i].get("label", "")])
		assert_eq(icon.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "%s icon is filtered soft" % where)
		assert_eq(int(icon.size.y), 32, "%s icon should be the 16px art at 2x" % where)
		var label := row.find_child("Label", true, false) as Label
		assert_not_null(label, "%s row lost its name label" % where)
		assert_gt(label.text.length(), 0)
		assert_true(_shares_a_line(icon, label), "%s icon sits off the name's line" % where)


func _shares_a_line(icon: Control, label: Control) -> bool:
	if icon == null or label == null:
		return false
	var icon_top := icon.position.y
	var icon_bot := icon_top + icon.size.y
	var text_top := label.position.y
	var text_bot := text_top + maxf(label.size.y, 12.0)
	return icon_top < text_bot and text_top < icon_bot


func _has_ink(img: Image) -> bool:
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.1:
				return true
	return false
