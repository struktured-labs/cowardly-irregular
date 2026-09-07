extends GutTest

## Regression test for monster drop routing (slice 47bf8a49).
##
## Pre-fix:
##   - speed_boots had a category-4 stub in items.json AND an accessory entry
##     in equipment.json. Six monsters dropped speed_boots → went into the
##     consumable inventory dict as an unusable lore item.
##   - BattleManager dropped ALL items through add_item, even resolved equipment.
##
## Post-fix:
##   - items.json stub deleted
##   - BattleManager.gd has _route_drop_to_equipment_pool routing equipment
##     IDs to GameLoop.equipment_pool BEFORE falling back to add_item.

const ITEMS_PATH := "res://data/items.json"
const EQUIPMENT_PATH := "res://data/equipment.json"
const BM_PATH := "res://src/battle/BattleManager.gd"


func _load_json(path: String) -> Dictionary:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var t = f.get_as_text()
	f.close()
	var p = JSON.parse_string(t)
	return p if p is Dictionary else {}


func _src(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


func test_speed_boots_no_longer_in_items_stub() -> void:
	var items = _load_json(ITEMS_PATH)
	assert_false(items.has("speed_boots"),
		"speed_boots must NOT have an items.json stub — it lives in equipment.json now")


func test_speed_boots_still_in_equipment() -> void:
	var eq = _load_json(EQUIPMENT_PATH)
	var accessories = eq.get("accessories", {})
	assert_true(accessories.has("speed_boots"),
		"speed_boots must remain in equipment.json accessories (canonical source)")


func test_battle_manager_has_equipment_pool_routing() -> void:
	var src = _src(BM_PATH)
	assert_string_contains(src, "_route_drop_to_equipment_pool",
		"BattleManager must define _route_drop_to_equipment_pool to route equipment drops correctly")
	assert_string_contains(src, "equipment_pool",
		"BattleManager must reference GameLoop.equipment_pool when routing drops")


func test_drop_routing_called_before_add_item_fallback() -> void:
	var src = _src(BM_PATH)
	# Find the routing block — must check equipment FIRST, fall back to add_item.
	var route_idx = src.find("_route_drop_to_equipment_pool(item_id)")
	var add_idx = src.find("player_party[0].add_item(item_id)")
	assert_gt(route_idx, -1, "Drop routing must call _route_drop_to_equipment_pool")
	assert_gt(add_idx, -1, "Drop routing must still have an add_item fallback for consumables")
	assert_lt(route_idx, add_idx,
		"Equipment routing must be CHECKED before falling back to add_item (else equipment lands in inventory dict)")
