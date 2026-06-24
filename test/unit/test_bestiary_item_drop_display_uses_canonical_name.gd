extends GutTest

## tick 130 regression: BestiaryMenu must prefer the canonical
## ItemSystem display name for drops + one-shot rewards, falling
## back to snake_case → Title Case only when the lookup fails.
## Pre-fix, the bestiary used `replace+capitalize` directly — so
## "hi_potion" displayed as "Hi Potion" instead of the canonical
## "Hi-Potion" (with hyphen) from items.json.
##
## Equipment items (weapons / armor / accessories) come from
## EquipmentSystem, not ItemSystem — so the resolver falls through
## to that pool before the prettifier fallback.

const BESTIARY_MENU := "res://src/ui/BestiaryMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _format_drops_body() -> String:
	var src := _read(BESTIARY_MENU)
	var idx: int = src.find("func _format_drops")
	assert_gt(idx, -1, "_format_drops must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func _resolver_body() -> String:
	var src := _read(BESTIARY_MENU)
	var idx: int = src.find("func _resolve_item_display_name")
	assert_gt(idx, -1, "_resolve_item_display_name must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_drops_path_uses_resolver_helper() -> void:
	# Pin: the drop iteration uses _resolve_item_display_name, not
	# the raw replace+capitalize.
	var body := _format_drops_body()
	assert_true(body.contains("_resolve_item_display_name(item)"),
		"_format_drops must call _resolve_item_display_name(item) for each drop")
	# Negative pin: the OLD direct prettifier path must be gone.
	assert_false(body.contains("item.replace(\"_\", \" \").capitalize()"),
		"old direct `item.replace('_', ' ').capitalize()` must be gone — replaced by the resolver")


func test_one_shot_path_uses_resolver_helper() -> void:
	var body := _format_drops_body()
	assert_true(body.contains("_resolve_item_display_name(os_str)"),
		"_format_drops must call _resolve_item_display_name(os_str) for one-shot rewards")
	assert_false(body.contains("os_str.replace(\"_\", \" \").capitalize()"),
		"old direct `os_str.replace('_', ' ').capitalize()` must be gone")


func test_resolver_prefers_item_system_first() -> void:
	# Pin ordering: ItemSystem first (covers consumables + main item
	# table), then EquipmentSystem (covers weapons/armor/accessories),
	# then prettifier fallback.
	var body := _resolver_body()
	var item_idx: int = body.find("get_node_or_null(\"/root/ItemSystem\")")
	var equip_idx: int = body.find("get_node_or_null(\"/root/EquipmentSystem\")")
	var fallback_idx: int = body.find("return item_id.replace(\"_\", \" \").capitalize()")
	assert_gt(item_idx, -1, "ItemSystem lookup must exist")
	assert_gt(equip_idx, -1, "EquipmentSystem lookup must exist")
	assert_gt(fallback_idx, -1, "prettifier fallback must exist")
	assert_lt(item_idx, equip_idx,
		"ItemSystem must be queried BEFORE EquipmentSystem — consumables are the most common drop")
	assert_lt(equip_idx, fallback_idx,
		"EquipmentSystem must be queried BEFORE the prettifier fallback — equipment drops have canonical names too")


func test_resolver_iterates_three_equipment_pools() -> void:
	# Pin: weapons, armor, accessories — EquipmentSystem's three
	# top-level pool dicts. Missing one would leak the prettified id
	# for that category.
	var body := _resolver_body()
	for pool in ["weapons", "armor", "accessories"]:
		var quoted: String = "\"" + pool + "\""
		assert_true(body.contains(quoted),
			"resolver must check '%s' EquipmentSystem pool" % pool)


func test_resolver_empty_id_returns_empty_string() -> void:
	# Defensive: empty item_id is a no-op.
	var body := _resolver_body()
	assert_true(body.contains("if item_id == \"\":\n\t\treturn \"\""),
		"resolver must return \"\" on empty input — defensive")


func test_resolver_handles_missing_name_field() -> void:
	# Pin: ItemSystem.get_item returning a dict without "name" key
	# must still fall through (not return empty). The has("name")
	# guard catches that case.
	var body := _resolver_body()
	assert_true(body.contains("if not data.is_empty() and data.has(\"name\"):"),
		"ItemSystem branch must check has('name') — falls through if item exists but unnamed")


func test_existing_format_drops_skeleton_preserved() -> void:
	# Sanity: don't regress the structural format ("X N%, Y M%").
	var body := _format_drops_body()
	assert_true(body.contains("parts.append(\"%s %d%%\""),
		"format_drops skeleton must still produce '<name> <pct>%' parts")
	assert_true(body.contains("\"Drops: %s\""),
		"Drops: prefix preserved")
	assert_true(body.contains("(One-shot: %s)"),
		"One-shot parenthesis format preserved")
