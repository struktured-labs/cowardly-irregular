extends GutTest

## Item-shop buy rows read only the first bag. Sell and the pause menu already add every member's stack.

const SHOP_PATH := "res://src/exploration/ShopScene.gd"
const ShopScript = preload(SHOP_PATH)

const _STUB_GAMELOOP := """
extends Node
var party: Array = []
"""

var _prior_party: Array = []
var _stub: Node = null


func before_each() -> void:
	_prior_party = GameState.player_party.duplicate(true)


func after_each() -> void:
	if _stub != null and is_instance_valid(_stub):
		_stub.free()
		_stub = null
	_restore_party(_prior_party)


func _restore_party(prior: Array) -> void:
	var typed: Array[Dictionary] = []
	for entry in prior:
		if entry is Dictionary:
			typed.append((entry as Dictionary).duplicate(true))
	GameState.player_party = typed


func _make_stub(live_party: Array) -> Node:
	var script := GDScript.new()
	script.source_code = _STUB_GAMELOOP
	script.reload()
	var stub := Node.new()
	stub.set_script(script)
	stub.name = "GameLoop"
	stub.party = live_party
	get_tree().root.add_child(stub)
	_stub = stub
	return stub


func _combatant(who: String, stock: Dictionary) -> Object:
	var live: Object = (load("res://src/battle/Combatant.gd") as GDScript).new()
	add_child_autofree(live)
	live.combatant_name = who
	live.inventory = stock
	return live


func _item_shop() -> ShopScene:
	var shop := ShopScript.new()
	add_child_autofree(shop)
	shop.shop_type = ShopScript.ShopType.ITEM
	return shop


func _row_label(shop: ShopScene, item_id: String) -> String:
	for row in shop.current_menu.menu_items:
		if str(row.get("id", "")) == item_id:
			return str(row.get("label", ""))
	return ""


func _sell_qty(shop: ShopScene, item_id: String) -> int:
	for row in shop._get_sellable_inventory():
		if str(row.get("id", "")) == item_id:
			return int(row.get("quantity", 0))
	return 0


func test_floor_the_readers_this_file_calls() -> void:
	var shop := ShopScript.new()
	for m in ["_get_owned_count", "_inventory_sources", "_open_buy_menu", "_get_sellable_inventory"]:
		assert_true(shop.has_method(m), "ShopScene must still expose %s()" % m)
	shop.free()


func test_the_buy_row_counts_every_members_stack() -> void:
	var potion: Dictionary = ItemSystem.get_item("potion")
	var phoenix: Dictionary = ItemSystem.get_item("phoenix_down")
	assert_false(potion.is_empty(), "CONTROL: potion is in the catalog")
	assert_false(phoenix.is_empty(), "CONTROL: phoenix_down is in the catalog")
	# Stale snapshot still says the leader holds one potion. Character creation put three on each person, plus a Phoenix Down each.
	var snap: Array[Dictionary] = [
		{"name": "Fighter", "inventory": {"potion": 1}},
		{"name": "Mage", "inventory": {}},
	]
	GameState.player_party = snap
	var leader := _combatant("Fighter", {"potion": 3, "phoenix_down": 1})
	var ally := _combatant("Mage", {"potion": 3, "phoenix_down": 1})
	_make_stub([leader, ally])
	var shop := _item_shop()

	var potions: int = shop._get_owned_count("potion")
	var downs: int = shop._get_owned_count("phoenix_down")
	var sell_potions: int = _sell_qty(shop, "potion")
	shop.shop_inventory = ["potion", "phoenix_down"] as Array[String]
	shop._open_buy_menu()
	var potion_label := _row_label(shop, "potion")
	var phoenix_label := _row_label(shop, "phoenix_down")

	assert_eq(potions, 6, "three potions on each of two members is six, not the leader's three")
	assert_eq(downs, 2, "each member's Phoenix Down counts")
	assert_eq(potions, sell_potions, "the buy row and the sell list must name the same stack")
	assert_true(" (6)" in potion_label, "the shelf must show the party total. Got: %s" % potion_label)
	assert_false(" (3)" in potion_label, "the leader's stack alone must not be the number on the row. Got: %s" % potion_label)
	assert_true(" (2)" in phoenix_label, "the shelf must show both Phoenix Downs. Got: %s" % phoenix_label)


func test_without_a_live_party_every_snapshot_bag_still_counts() -> void:
	assert_null(get_tree().root.get_node_or_null("GameLoop"), "this arm is the no-live-party fallback")
	var snap: Array[Dictionary] = [
		{"name": "Fighter", "inventory": {"potion": 3}},
		{"name": "Mage", "inventory": {"potion": 4}},
	]
	GameState.player_party = snap
	var shop := _item_shop()
	assert_eq(shop._get_owned_count("potion"), 7, "with no live party the buy count still adds every snapshot bag")
