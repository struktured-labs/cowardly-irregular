extends GutTest

## Shop UX (2026-07-09): two fixes pinned.
## 1. Blacksmith shelves in strict ascending cost — a 31-item flat catalog
##    (same in every world, flagged to struktured separately) at least reads
##    as a progression ladder. Ratchet: future additions must keep the order.
## 2. [on <name>] equipped markers in the buy list — owned-count reads
##    inventory only, so players re-bought gear their party was wearing.

const ShopSceneScript := preload("res://src/exploration/ShopScene.gd")
const VillageShopScript := preload("res://src/exploration/VillageShop.gd")


class GameStateStub:
	var player_party: Array = []


func test_blacksmith_shelves_sorted_by_cost() -> void:
	var eq = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))
	for pair in [["weapons", VillageShopScript.BLACKSMITH_WEAPONS], ["armors", VillageShopScript.BLACKSMITH_ARMOR]]:
		var table: Dictionary = eq.get(pair[0], {})
		var prev := -1
		for iid in pair[1]:
			assert_true(table.has(iid), "%s: shelf id '%s' must exist" % [pair[0], iid])
			var cost := int(table[iid].get("cost", 0))
			assert_true(cost >= prev,
				"%s shelf must stay cost-sorted: '%s' (%dG) placed after a %dG item" % [pair[0], iid, cost, prev])
			prev = cost


func test_equipped_by_names_the_wearers() -> void:
	var shop = ShopSceneScript.new()
	autofree(shop)
	var stub := GameStateStub.new()
	stub.player_party = [
		{"name": "Fighter", "equipped_weapon": "iron_sword", "equipped_armor": "leather_armor"},
		{"name": "Mage", "equipped_weapon": "oak_staff"},
		{"name": "Rogue", "equipped_weapon": "iron_sword"},
	]
	shop.game_state = stub
	assert_eq(shop._equipped_by("iron_sword"), "Fighter, Rogue", "both wearers named")
	assert_eq(shop._equipped_by("oak_staff"), "Mage", "single wearer named")
	assert_eq(shop._equipped_by("mythril_sword"), "", "unworn gear unmarked")
	shop.game_state = null
	assert_eq(shop._equipped_by("iron_sword"), "", "no game_state -> fail soft")
