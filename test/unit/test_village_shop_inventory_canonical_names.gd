extends GutTest

## tick 134 + tick 135 regression: VillageShop's inventory dialogue
## now delegates through the shared ItemNameResolver.

const VILLAGE_SHOP := "res://src/exploration/VillageShop.gd"
const RESOLVER := "res://src/items/ItemNameResolver.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _format_body() -> String:
	var src := _read(VILLAGE_SHOP)
	var idx: int = src.find("func _format_inventory")
	assert_gt(idx, -1, "_format_inventory must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_format_uses_resolver() -> void:
	var body := _format_body()
	assert_true(body.contains("_resolve_inventory_name(items[i])"),
		"_format_inventory must call _resolve_inventory_name(items[i])")
	assert_false(body.contains("items[i].replace(\"_\", \" \").capitalize()"),
		"old direct prettifier must be gone")


func test_local_resolver_delegates_to_shared() -> void:
	var src := _read(VILLAGE_SHOP)
	var idx: int = src.find("func _resolve_inventory_name")
	assert_gt(idx, -1, "wrapper must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("ItemNameResolver.resolve(item_id)"),
		"local helper must delegate to shared ItemNameResolver.resolve")


func test_shared_resolver_checks_all_three_sources() -> void:
	# Pin: shared resolver consults Item → Job → Equipment. Shops
	# sell consumables, spells, and weapons/armor — all three needed.
	var src := _read(RESOLVER)
	assert_true(src.contains("get_node_or_null(\"ItemSystem\")"),
		"shared resolver must check ItemSystem for consumables")
	assert_true(src.contains("get_node_or_null(\"JobSystem\")"),
		"shared resolver must check JobSystem for spell-like inventory")
	assert_true(src.contains("get_node_or_null(\"EquipmentSystem\")"),
		"shared resolver must check EquipmentSystem for weapon/armor")
	assert_true(src.contains("return item_id.replace(\"_\", \" \").capitalize()"),
		"prettifier fallback must remain")


func test_shared_resolver_ordering_items_first() -> void:
	var src := _read(RESOLVER)
	var item_idx: int = src.find("get_node_or_null(\"ItemSystem\")")
	var job_idx: int = src.find("get_node_or_null(\"JobSystem\")")
	var equip_idx: int = src.find("get_node_or_null(\"EquipmentSystem\")")
	assert_lt(item_idx, job_idx,
		"ItemSystem checked before JobSystem")
	assert_lt(job_idx, equip_idx,
		"JobSystem checked before EquipmentSystem")


func test_shared_resolver_uses_armors_plural() -> void:
	var src := _read(RESOLVER)
	assert_true(src.contains("\"armors\""),
		"shared resolver must use 'armors' plural")
	assert_false(src.contains("\"armor\","),
		"singular 'armor' is a typo")


func test_existing_inventory_format_preserved() -> void:
	var body := _format_body()
	assert_true(body.contains("\"- %s\\n\""),
		"format must remain '- %s\\n' bullet per row")
	assert_true(body.contains("\"...and more!\""),
		"'...and more!' overflow message preserved")
	assert_true(body.contains("min(items.size(), 4)"),
		"4-row preview cap preserved")
