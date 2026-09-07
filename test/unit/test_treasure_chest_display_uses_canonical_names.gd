extends GutTest

## tick 133 + tick 135 regression: TreasureChest's "Found X!" toast
## resolves canonical names via the shared ItemNameResolver.
## Tick 135 collapsed the local resolver to a delegation wrapper.

const TREASURE_CHEST := "res://src/exploration/TreasureChest.gd"
const RESOLVER := "res://src/items/ItemNameResolver.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _open_chest_body() -> String:
	var src := _read(TREASURE_CHEST)
	var idx: int = src.find("func _open_chest")
	assert_gt(idx, -1, "_open_chest must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_item_path_uses_local_helper() -> void:
	var body := _open_chest_body()
	assert_true(body.contains("_resolve_display_name(contents_id)"),
		"item branch must call _resolve_display_name(contents_id)")
	assert_false(body.contains("var item_name = contents_id.replace(\"_\", \" \").capitalize()"),
		"old direct prettifier must be gone for item name")


func test_equipment_path_uses_local_helper() -> void:
	var body := _open_chest_body()
	assert_false(body.contains("var equip_name = contents_id.replace(\"_\", \" \").capitalize()"),
		"old direct prettifier must be gone for equipment name")
	var count: int = 0
	var search_from: int = 0
	while true:
		var found: int = body.find("_resolve_display_name(contents_id)", search_from)
		if found < 0:
			break
		count += 1
		search_from = found + 1
	assert_gte(count, 2,
		"both item and equipment branches must call _resolve_display_name")


func test_local_resolver_delegates_to_shared() -> void:
	var src := _read(TREASURE_CHEST)
	var idx: int = src.find("func _resolve_display_name")
	assert_gt(idx, -1, "wrapper must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("ItemNameResolver.resolve(contents_id)"),
		"local resolver must delegate to shared ItemNameResolver.resolve")


func test_shared_resolver_uses_armors_plural() -> void:
	# Locked-in defense against the typo bug from ticks 130/133.
	var src := _read(RESOLVER)
	assert_true(src.contains("\"armors\""),
		"shared resolver must use 'armors' plural")
	assert_false(src.contains("\"armor\","),
		"singular 'armor' is a typo — EquipmentSystem.armors is plural")


func test_shared_resolver_iterates_all_three_pools() -> void:
	var src := _read(RESOLVER)
	for pool in ["weapons", "armors", "accessories"]:
		var quoted: String = "\"" + pool + "\""
		assert_true(src.contains(quoted),
			"shared resolver must check '%s' pool" % pool)


func test_shared_resolver_empty_id_short_circuits() -> void:
	var src := _read(RESOLVER)
	assert_true(src.contains("if item_id == \"\":\n\t\treturn \"\""),
		"empty id must return empty string in shared resolver")


func test_shared_resolver_guards_dict_shape() -> void:
	var src := _read(RESOLVER)
	assert_true(src.contains("pool[item_id] is Dictionary"),
		"shared resolver must type-guard pool entries")


func test_shared_resolver_uses_has_method_guard() -> void:
	var src := _read(RESOLVER)
	assert_true(src.contains("item_sys.has_method(\"get_item\")"),
		"ItemSystem branch must use has_method guard")
