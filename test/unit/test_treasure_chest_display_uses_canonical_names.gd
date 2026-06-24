extends GutTest

## tick 133 regression: TreasureChest's "Found X!" toast must
## resolve canonical names from ItemSystem (consumables) or
## EquipmentSystem (weapons/armors/accessories). Pre-fix it
## prettified the raw id, so "hi_potion" surfaced as "Hi Potion"
## instead of canonical "Hi-Potion", and equipment names dropped
## their JSON-defined modifiers ("iron_sword" → "Iron Sword"
## instead of e.g. "Iron Longsword").
##
## Also pins the armor-pool naming fix: EquipmentSystem field is
## `armors` (plural), not `armor`. Tick 130 originally pinned the
## singular form in the bestiary resolver which silently never
## fired for armor drops.

const TREASURE_CHEST := "res://src/exploration/TreasureChest.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _resolver_body() -> String:
	var src := _read(TREASURE_CHEST)
	var idx: int = src.find("func _resolve_display_name")
	assert_gt(idx, -1, "_resolve_display_name must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func _open_chest_body() -> String:
	var src := _read(TREASURE_CHEST)
	var idx: int = src.find("func _open_chest")
	assert_gt(idx, -1, "_open_chest must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_item_path_uses_resolver() -> void:
	var body := _open_chest_body()
	assert_true(body.contains("_resolve_display_name(contents_id)"),
		"item branch must call _resolve_display_name(contents_id)")
	# Negative pin: old prettifier-on-id path must be gone.
	assert_false(body.contains("var item_name = contents_id.replace(\"_\", \" \").capitalize()"),
		"old direct prettifier for item name must be gone")


func test_equipment_path_uses_resolver() -> void:
	var body := _open_chest_body()
	# Equipment branch should also resolve through the same helper.
	assert_false(body.contains("var equip_name = contents_id.replace(\"_\", \" \").capitalize()"),
		"old direct prettifier for equipment name must be gone")
	# Confirm two distinct _resolve_display_name calls exist (one for
	# item, one for equipment).
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


func test_resolver_prefers_item_system_first() -> void:
	# Item lookup ordering: ItemSystem → EquipmentSystem → prettifier.
	var body := _resolver_body()
	var item_idx: int = body.find("get_node_or_null(\"/root/ItemSystem\")")
	var equip_idx: int = body.find("get_node_or_null(\"/root/EquipmentSystem\")")
	var fallback_idx: int = body.find("return contents_id.replace(\"_\", \" \").capitalize()")
	assert_gt(item_idx, -1, "ItemSystem lookup must exist")
	assert_gt(equip_idx, -1, "EquipmentSystem lookup must exist")
	assert_gt(fallback_idx, -1, "prettifier fallback must exist")
	assert_lt(item_idx, equip_idx,
		"ItemSystem queried BEFORE EquipmentSystem — consumables more common in chests")
	assert_lt(equip_idx, fallback_idx,
		"EquipmentSystem queried BEFORE prettifier fallback")


func test_resolver_uses_armors_plural_not_singular() -> void:
	# CRITICAL: EquipmentSystem.gd defines `armors` (plural) at line
	# 11. The bestiary resolver originally used "armor" singular —
	# silently dead branch. Tick 133 fixed both.
	var body := _resolver_body()
	assert_true(body.contains("\"armors\""),
		"resolver must use 'armors' plural to match EquipmentSystem field")
	assert_false(body.contains("\"armor\","),
		"singular 'armor' is a typo — EquipmentSystem.armors is plural")


func test_resolver_iterates_all_three_pools() -> void:
	var body := _resolver_body()
	for pool in ["weapons", "armors", "accessories"]:
		var quoted: String = "\"" + pool + "\""
		assert_true(body.contains(quoted),
			"resolver must check '%s' pool" % pool)


func test_resolver_empty_id_short_circuits() -> void:
	var body := _resolver_body()
	assert_true(body.contains("if contents_id == \"\":\n\t\treturn \"\""),
		"empty id must return empty string")


func test_resolver_guards_dict_shape() -> void:
	# Defensive pin: pool entries must be Dictionary before .get is
	# called. Some pools might have non-Dict entries during initial
	# load.
	var body := _resolver_body()
	assert_true(body.contains("pool[contents_id] is Dictionary"),
		"resolver must type-guard pool entries — defensive")


func test_resolver_uses_has_method_guard() -> void:
	var body := _resolver_body()
	assert_true(body.contains("item_sys.has_method(\"get_item\")"),
		"ItemSystem branch must use has_method guard")
