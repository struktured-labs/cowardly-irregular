extends GutTest

## Data-integrity guard (2026-07-05): every id listed in a shop's inventory
## (VillageShop.*_INVENTORY consts) must resolve against its owning system. A
## phantom id degrades to a graceful "???"/name-fallback in the UI but is
## unbuyable/dead — the shop offers something that doesn't exist. Weapons + armor
## resolve via EquipmentSystem, magic (magic shops sell spells) via JobSystem,
## consumables via ItemSystem.


func test_item_shop_ids_resolve() -> void:
	for id in VillageShop.ITEM_INVENTORY:
		assert_false(ItemSystem.get_item(str(id)).is_empty(),
			"ITEM_INVENTORY '%s' must resolve in ItemSystem" % id)


func test_magic_shop_ids_resolve() -> void:
	var magic: Array = VillageShop.BLACK_MAGIC_INVENTORY + VillageShop.WHITE_MAGIC_INVENTORY
	for id in magic:
		assert_false(JobSystem.get_ability(str(id)).is_empty(),
			"magic-shop ability '%s' must resolve in JobSystem" % id)


func test_blacksmith_weapon_ids_resolve() -> void:
	for id in VillageShop.BLACKSMITH_WEAPONS:
		assert_false(EquipmentSystem.get_weapon(str(id)).is_empty(),
			"BLACKSMITH_WEAPONS '%s' must resolve in EquipmentSystem" % id)


func test_blacksmith_armor_ids_resolve() -> void:
	for id in VillageShop.BLACKSMITH_ARMOR:
		assert_false(EquipmentSystem.get_armor(str(id)).is_empty(),
			"BLACKSMITH_ARMOR '%s' must resolve in EquipmentSystem" % id)
