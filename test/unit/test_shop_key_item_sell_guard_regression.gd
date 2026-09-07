extends GutTest

## Permanent-loss fix 2026-07-04: _get_sellable_inventory listed EVERY
## inventory item with no key/quest filter, so a player could sell
## returned_sword / chapter_three_pages / calibrant_token etc. — all
## ItemCategory.META (4), all cost:0 — for 0 gold and PERMANENTLY lose
## the quest item. The sell list now excludes META + 0-cost items, and
## _attempt_sell guards the same as defense-in-depth. Verified against
## real data: all 127 META items are cost<=0 (blocked), and no cost>0
## META item exists, so no legitimate sale is over-blocked.

const SHOP := "res://src/exploration/ShopScene.gd"


func _sellable_body() -> String:
	var src: String = FileAccess.get_file_as_string(SHOP)
	var fn: int = src.find("func _get_sellable_inventory")
	assert_gt(fn, -1)
	return src.substr(fn, src.find("\nfunc ", fn + 1) - fn)


func test_sell_list_excludes_meta_and_zero_cost() -> void:
	var body := _sellable_body()
	assert_true(body.contains("== 4") and body.contains("continue"),
		"_get_sellable_inventory must skip ItemCategory.META (4) — quest/key items")
	assert_true(body.contains("get(\"cost\", 0)) <= 0"),
		"must also skip 0-cost items (they sell for 0 and are the key-item signature)")


func test_attempt_sell_has_defense_in_depth_guard() -> void:
	var src: String = FileAccess.get_file_as_string(SHOP)
	var fn: int = src.find("func _attempt_sell")
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_true(body.contains("== 4") and body.contains("That item can't be sold"),
		"_attempt_sell must refuse a META/0-cost row even if it leaks into the menu")


func test_real_key_items_would_be_filtered() -> void:
	# Data premise: the actual key items are META + cost:0, so the filter catches them.
	var items = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	for kid in ["returned_sword", "chapter_three_pages", "overdue_guild_book"]:
		assert_true(items.has(kid), "key item %s must exist" % kid)
		assert_eq(int(items[kid].get("category", -1)), 4, "%s must be META so the sell filter blocks it" % kid)


func test_no_meta_item_is_legitimately_sellable() -> void:
	# If a META item ever gets cost>0, the blanket category-4 filter would
	# wrongly block a real sale — this catches that data drift.
	var items = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	var meta_with_value: Array = []
	for kid in items:
		var v = items[kid]
		if v is Dictionary and int(v.get("category", -1)) == 4 and int(v.get("cost", 0)) > 0:
			meta_with_value.append(kid)
	assert_eq(meta_with_value.size(), 0,
		"a META item with cost>0 would be over-blocked by the sell filter — give it a sellable category instead: %s" % str(meta_with_value))


func test_normal_consumable_still_sellable() -> void:
	var items = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	assert_true(items.has("potion"))
	assert_ne(int(items["potion"].get("category", -1)), 4, "potion must not be META")
	assert_gt(int(items["potion"].get("cost", 0)), 0, "potion must have a sell value")
