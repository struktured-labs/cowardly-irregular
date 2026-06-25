extends GutTest

## tick 130 + tick 135 regression: BestiaryMenu's drop display
## now delegates to the shared ItemNameResolver. Original tick-130
## fix prevented "Hi Potion" instead of canonical "Hi-Potion"
## from items.json. Tick 133 corrected the armors-plural typo.
## Tick 135 moved the body to ItemNameResolver, so this test now
## pins the wrapper-delegation shape + the live resolver
## guarantees the runtime-behavior pin tests still rely on.

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


func test_drops_path_uses_resolver_helper() -> void:
	var body := _format_drops_body()
	assert_true(body.contains("_resolve_item_display_name(item)"),
		"_format_drops must call _resolve_item_display_name(item)")
	assert_false(body.contains("item.replace(\"_\", \" \").capitalize()"),
		"old direct prettifier must be gone")


func test_one_shot_path_uses_resolver_helper() -> void:
	var body := _format_drops_body()
	assert_true(body.contains("_resolve_item_display_name(os_str)"),
		"_format_drops must call _resolve_item_display_name(os_str)")
	assert_false(body.contains("os_str.replace(\"_\", \" \").capitalize()"),
		"old direct prettifier must be gone for one-shot path")


func test_local_resolver_delegates_to_shared() -> void:
	# Tick 135: BestiaryMenu._resolve_item_display_name is now a
	# one-line wrapper over ItemNameResolver.resolve.
	var src := _read(BESTIARY_MENU)
	var idx: int = src.find("func _resolve_item_display_name")
	assert_gt(idx, -1, "wrapper must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("ItemNameResolver.resolve(item_id)"),
		"local resolver must delegate to shared ItemNameResolver.resolve")


func test_shared_resolver_iterates_three_equipment_pools() -> void:
	# Pin lives on the shared resolver now.
	var resolver_src := _read("res://src/items/ItemNameResolver.gd")
	for pool in ["weapons", "armors", "accessories"]:
		var quoted: String = "\"" + pool + "\""
		assert_true(resolver_src.contains(quoted),
			"shared resolver must check '%s' EquipmentSystem pool" % pool)
	# Negative pin: singular 'armor' typo must NOT return.
	assert_false(resolver_src.contains("\"armor\","),
		"singular 'armor' is a typo — must be 'armors' plural")


func test_shared_resolver_prefers_item_system_first() -> void:
	var resolver_src := _read("res://src/items/ItemNameResolver.gd")
	var item_idx: int = resolver_src.find("get_node_or_null(\"ItemSystem\")")
	var equip_idx: int = resolver_src.find("get_node_or_null(\"EquipmentSystem\")")
	var fallback_idx: int = resolver_src.find("return item_id.replace(\"_\", \" \").capitalize()")
	assert_gt(item_idx, -1, "ItemSystem lookup must exist")
	assert_gt(equip_idx, -1, "EquipmentSystem lookup must exist")
	assert_gt(fallback_idx, -1, "prettifier fallback must exist")
	assert_lt(item_idx, equip_idx,
		"ItemSystem checked before EquipmentSystem in shared resolver")
	assert_lt(equip_idx, fallback_idx,
		"EquipmentSystem checked before prettifier fallback")


func test_shared_resolver_handles_missing_name_field() -> void:
	var resolver_src := _read("res://src/items/ItemNameResolver.gd")
	assert_true(resolver_src.contains("if not data.is_empty() and data.has(\"name\"):"),
		"ItemSystem branch must check has('name')")


func test_existing_format_drops_skeleton_preserved() -> void:
	var body := _format_drops_body()
	assert_true(body.contains("parts.append(\"%s %d%%\""),
		"format must produce '<name> <pct>%' parts")
	assert_true(body.contains("\"Drops: %s\""),
		"Drops: prefix preserved")
	assert_true(body.contains("(One-shot: %s)"),
		"One-shot parenthesis format preserved")
