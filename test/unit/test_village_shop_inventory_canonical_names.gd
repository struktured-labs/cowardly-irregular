extends GutTest

## tick 134 regression: VillageShop's "Available: ..." dialogue
## must surface canonical names for the four kinds of things shops
## sell:
##   - Consumables (ItemSystem) — "Hi-Potion" not "Hi Potion"
##   - Spells (JobSystem.abilities) — "Fire" not "Fire" (happens to
##     match, but still must flow through canonical)
##   - Weapons (EquipmentSystem.weapons) — "Iron Sword" / canonical
##   - Armor (EquipmentSystem.armors) — "Leather Armor" / canonical
##
## Pre-fix every inventory entry went through replace+capitalize so
## the player saw prettified ids instead of designer-set names.
## High-visibility: every village × every shop type.

const VILLAGE_SHOP := "res://src/exploration/VillageShop.gd"


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


func _resolver_body() -> String:
	var src := _read(VILLAGE_SHOP)
	var idx: int = src.find("func _resolve_inventory_name")
	assert_gt(idx, -1, "_resolve_inventory_name must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_format_uses_resolver() -> void:
	var body := _format_body()
	assert_true(body.contains("_resolve_inventory_name(items[i])"),
		"_format_inventory must call _resolve_inventory_name(items[i])")
	# Negative pin: old direct prettifier path must be gone.
	assert_false(body.contains("items[i].replace(\"_\", \" \").capitalize()"),
		"old direct `items[i].replace+capitalize` must be gone — replaced by the resolver")


func test_resolver_checks_all_four_sources() -> void:
	var body := _resolver_body()
	# Pin: all four systems are consulted.
	assert_true(body.contains("get_node_or_null(\"/root/ItemSystem\")"),
		"resolver must check ItemSystem for consumables")
	assert_true(body.contains("get_node_or_null(\"/root/JobSystem\")"),
		"resolver must check JobSystem for spell-like inventory (Black/White Magic shops sell spells)")
	assert_true(body.contains("get_node_or_null(\"/root/EquipmentSystem\")"),
		"resolver must check EquipmentSystem for weapon/armor shops (Blacksmith)")
	assert_true(body.contains("return item_id.replace(\"_\", \" \").capitalize()"),
		"prettifier fallback must remain for ids none of the systems know")


func test_resolver_ordering_items_first() -> void:
	# Consumables are the most common shop type, so ItemSystem
	# checked first keeps the lookup cheap for the common case.
	var body := _resolver_body()
	var item_idx: int = body.find("get_node_or_null(\"/root/ItemSystem\")")
	var job_idx: int = body.find("get_node_or_null(\"/root/JobSystem\")")
	var equip_idx: int = body.find("get_node_or_null(\"/root/EquipmentSystem\")")
	assert_lt(item_idx, job_idx,
		"ItemSystem checked before JobSystem — consumables more common than spell-shops")
	assert_lt(job_idx, equip_idx,
		"JobSystem checked before EquipmentSystem — keeps the resolver fast for the magic-shop case")


func test_resolver_uses_armors_plural() -> void:
	# Same pin as tick 133's bestiary/chest fixes — must be plural
	# to match EquipmentSystem field declaration.
	var body := _resolver_body()
	assert_true(body.contains("\"armors\""),
		"resolver must use 'armors' plural")
	assert_false(body.contains("\"armor\","),
		"'armor' singular is a typo — EquipmentSystem.armors is plural")


func test_resolver_empty_id_short_circuits() -> void:
	var body := _resolver_body()
	assert_true(body.contains("if item_id == \"\":\n\t\treturn \"\""),
		"empty id must short-circuit to \"\"")


func test_resolver_guards_has_method() -> void:
	var body := _resolver_body()
	assert_true(body.contains("item_sys.has_method(\"get_item\")"),
		"ItemSystem branch must guard has_method")
	assert_true(body.contains("job_sys.has_method(\"get_ability\")"),
		"JobSystem branch must guard has_method")


func test_existing_inventory_format_preserved() -> void:
	# Don't regress the visible format ("- X\n", "...and more!").
	var body := _format_body()
	assert_true(body.contains("\"- %s\\n\""),
		"format must remain '- %s\\n' bullet per row")
	assert_true(body.contains("\"...and more!\""),
		"'...and more!' overflow message preserved")
	assert_true(body.contains("min(items.size(), 4)"),
		"4-row preview cap preserved")
