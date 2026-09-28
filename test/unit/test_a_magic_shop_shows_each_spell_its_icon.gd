extends GutTest

## Magic-shop rows set `icon_id` to the SPELL id and nothing else, so Win98Menu resolved it through
## ItemIcons — which maps any id it does not know to the generic item scroll. Every spell in Harmonia's
## magic shops wore the same scroll while the Abilities screen and the battle menu showed its own icon.
## Same wrong-resolver shape round 1 guarded in battle; the shop was a row builder it never saw.
## Derived from VillageShop's own inventories, so a spell added to a shelf is covered the day it lands.

const ShopSceneScript := preload("res://src/exploration/ShopScene.gd")
const VillageShopScript := preload("res://src/exploration/VillageShop.gd")


func _open_buy(type: int, inventory: Array) -> Node:
	var shop = ShopSceneScript.new()
	add_child_autofree(shop)
	await get_tree().process_frame
	shop.setup(type, "Test Shop", inventory, null)
	await get_tree().process_frame
	shop._open_buy_menu()
	await get_tree().process_frame
	return shop


func _row_icons(shop: Node) -> Dictionary:
	## id -> the TextureRect the row drew, read off the live menu.
	var out := {}
	var menu = shop.current_menu
	if menu == null:
		return out
	var container: Node = menu._get_items_container()
	for i in menu.menu_items.size():
		var item: Dictionary = menu.menu_items[i]
		var row: Node = container.get_child(i)
		var icon: TextureRect = null
		for c in row.find_children("*Icon*", "TextureRect", true, false):
			icon = c
			break
		out[str(item.get("id", ""))] = icon
	return out


func test_every_spell_on_a_magic_shelf_wears_its_own_icon() -> void:
	var vs = VillageShopScript.new()
	var shelves := {
		ShopSceneScript.ShopType.BLACK_MAGIC: vs.BLACK_MAGIC_INVENTORY,
		ShopSceneScript.ShopType.WHITE_MAGIC: vs.WHITE_MAGIC_INVENTORY,
	}
	vs.free()
	var bad: Array = []
	var judged := 0
	for type in shelves:
		var inventory: Array = shelves[type]
		assert_gt(inventory.size(), 0, "CONTROL: the shelf has spells")
		var shop = await _open_buy(type, inventory)
		var icons := _row_icons(shop)
		for id in inventory:
			if not icons.has(str(id)):
				continue
			judged += 1
			var icon: TextureRect = icons[str(id)]
			if icon == null:
				bad.append("%s: no icon" % id)
			elif icon.texture == ItemIcons.tinted(str(id)):
				bad.append("%s: the item scroll" % id)
			elif icon.texture != AbilityIcons.tinted(str(id)):
				bad.append("%s: not its ability icon" % id)
	assert_gt(judged, 6, "CONTROL: spell rows were drawn and judged (%d)" % judged)
	assert_eq(bad, [], "magic-shop rows without their spell's icon: %s" % str(bad))


func test_an_item_shop_keeps_its_item_icons() -> void:
	var shop = await _open_buy(ShopSceneScript.ShopType.ITEM, ["potion", "ether"])
	var icons := _row_icons(shop)
	assert_true(icons.has("potion"), "CONTROL: the potion row was drawn")
	var icon: TextureRect = icons.get("potion")
	assert_not_null(icon, "an item row keeps its icon")
	if icon:
		assert_eq(icon.texture, ItemIcons.tinted("potion"), "items stay on the item resolver")
