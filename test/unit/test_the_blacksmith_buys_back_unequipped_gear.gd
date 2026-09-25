extends GutTest

## The blacksmith offered "Sell", but built its list from party item inventories. Gear never
## lands there: purchases, chests and drops all go to GameLoop.equipment_pool. So the Sell menu
## always read "(No items to sell)", and a replaced sword could never be turned back into gold.
## The blacksmith now lists and sells the pool's unequipped pieces. Other shops still sell
## from inventory.

const SHOP := "res://src/exploration/ShopScene.gd"

const _STUB_GAMELOOP := """
extends Node
var equipment_pool: Dictionary = {}
var party: Array = []
"""

var _stub: Node = null
var _saved_gold: int = 0


func before_each() -> void:
	_saved_gold = GameState.party_gold


func after_each() -> void:
	GameState.party_gold = _saved_gold
	if _stub != null and is_instance_valid(_stub):
		if _stub.get_parent() != null:
			_stub.get_parent().remove_child(_stub)
		_stub.free()
	_stub = null


func _make_stub(pool: Dictionary, party: Array) -> Node:
	var script := GDScript.new()
	script.source_code = _STUB_GAMELOOP
	script.reload()
	var stub := Node.new()
	stub.set_script(script)
	stub.name = "GameLoop"
	stub.equipment_pool = pool
	stub.party = party
	get_tree().root.add_child(stub)
	_stub = stub
	return stub


func _first_priced(catalog: Dictionary) -> String:
	for id in catalog:
		if int(catalog[id].get("cost", 0)) > 0:
			return str(id)
	return ""


func _shop(type: int) -> Node:
	var shop = load(SHOP).new()
	add_child_autofree(shop)
	shop.shop_type = type
	return shop


func _counts(sellable: Array) -> Dictionary:
	var out := {}
	for e in sellable:
		out[str(e["id"])] = int(e["quantity"])
	return out


func test_floor_the_shop_this_file_drives() -> void:
	var shop = load(SHOP).new()
	for m in ["_get_sellable_inventory", "_attempt_sell", "_remove_from_equipment_pool", "_get_item_data"]:
		assert_true(shop.has_method(m), "ShopScene must still expose %s()" % m)
	shop.free()


func test_the_blacksmith_lists_unequipped_gear_from_the_pool() -> void:
	var w := _first_priced(EquipmentSystem.weapons)
	var a := _first_priced(EquipmentSystem.armors)
	var acc := _first_priced(EquipmentSystem.accessories)
	assert_ne(w, "", "CONTROL: the catalog needs a priced weapon")
	assert_ne(acc, "", "CONTROL: the catalog needs a priced accessory")
	_make_stub({"weapons": [w, w], "armors": [a], "accessories": [acc]}, [])
	var shop = _shop(load(SHOP).ShopType.BLACKSMITH)
	var got := _counts(shop._get_sellable_inventory())
	assert_eq(got.get(w, 0), 2, "the blacksmith did not offer the two spare %s in the pool" % w)
	assert_eq(got.get(a, 0), 1, "the blacksmith did not offer the spare %s" % a)
	assert_eq(got.get(acc, 0), 1, "an accessory in the pool was not offered — _get_item_data knew only weapons and armor")


func test_selling_takes_one_piece_from_the_pool_and_pays() -> void:
	var w := _first_priced(EquipmentSystem.weapons)
	var stub := _make_stub({"weapons": [w, w], "armors": [], "accessories": []}, [])
	var shop = _shop(load(SHOP).ShopType.BLACKSMITH)
	var gold_before: int = GameState.party_gold
	shop._attempt_sell(w, shop._get_item_data(w))
	assert_eq((stub.equipment_pool["weapons"] as Array).count(w), 1, "a sale must take exactly one %s from the pool" % w)
	assert_gt(GameState.party_gold, gold_before, "the blacksmith took the %s and paid nothing" % w)


func test_a_misfiled_piece_is_still_sold() -> void:
	var a := _first_priced(EquipmentSystem.armors)
	var stub := _make_stub({"weapons": [a], "armors": [], "accessories": []}, [])
	var shop = _shop(load(SHOP).ShopType.BLACKSMITH)
	assert_eq(_counts(shop._get_sellable_inventory()).get(a, 0), 1, "CONTROL: a misfiled piece is listed")
	shop._attempt_sell(a, shop._get_item_data(a))
	assert_eq((stub.equipment_pool["weapons"] as Array).count(a), 0,
		"an old save's armor filed under weapons was listed for sale and then refused")


func test_decoy_an_item_shop_still_sells_from_inventory_not_the_pool() -> void:
	var w := _first_priced(EquipmentSystem.weapons)
	var holder := Combatant.new()
	autofree(holder)
	holder.inventory = {"potion": 2}
	_make_stub({"weapons": [w], "armors": [], "accessories": []}, [holder])
	var shop = _shop(load(SHOP).ShopType.ITEM)
	var got := _counts(shop._get_sellable_inventory())
	assert_eq(got.get("potion", 0), 2, "CONTROL: the item shop lost the party's potions")
	assert_false(got.has(w), "the item shop offered pool gear — only the blacksmith buys it back")
