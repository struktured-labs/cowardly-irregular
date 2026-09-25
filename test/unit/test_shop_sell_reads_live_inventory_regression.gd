extends GutTest

## The field menu, chests, and battle drops write Combatant.inventory.
## GameState.player_party is a snapshot copied on menu-open and on save.
## Entering a shop is an interior transition, so it does not autosave, and
## the sell list kept reading that snapshot.
##
## Use the last potion in the pause menu, walk into the shop: the snapshot
## still says 1, the sell pays gold, and the live remove is ignored.
## Pick up a potion from a chest in the same village: the snapshot says 0,
## so the sell list never offers it.

const SHOP_PATH := "res://src/exploration/ShopScene.gd"

const _STUB_GAMELOOP_SCRIPT := """
extends Node
var party: Array = []
"""


func _make_stub_gameloop(live_party: Array) -> Node:
	var stub_script := GDScript.new()
	stub_script.source_code = _STUB_GAMELOOP_SCRIPT
	stub_script.reload()
	var stub: Node = Node.new()
	stub.set_script(stub_script)
	stub.name = "GameLoop"
	stub.party = live_party
	get_tree().root.add_child(stub)
	return stub


func _sell_ids(shop: Object) -> Array:
	var ids: Array = []
	for row in shop._get_sellable_inventory():
		ids.append(str(row.get("id", "")))
	return ids


func _restore_party(prior: Array) -> void:
	var typed: Array[Dictionary] = []
	for entry in prior:
		if entry is Dictionary:
			typed.append((entry as Dictionary).duplicate(true))
	GameState.player_party = typed


func test_a_used_potion_cannot_be_sold_from_the_stale_snapshot() -> void:
	var prior: Array = GameState.player_party.duplicate(true)
	var gold_before: int = GameState.get_gold()
	var snap: Array[Dictionary] = [{"name": "Tester", "inventory": {"potion": 1}}]
	GameState.player_party = snap

	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var live: Object = combatant_script.new()
	add_child_autofree(live)
	live.inventory = {}

	var stub: Node = _make_stub_gameloop([live])
	var shop: Object = load(SHOP_PATH).new()
	add_child_autofree(shop)
	shop.shop_type = 0

	var ids: Array = _sell_ids(shop)
	var owned: int = shop._get_owned_count("potion")
	var removed: bool = shop._remove_item_from_inventory("potion")
	shop._attempt_sell("potion", ItemSystem.get_item("potion"))
	var snap_left: int = int(GameState.player_party[0].get("inventory", {}).get("potion", 0))
	var refusal: String = str(shop.description_label.text)
	stub.free()
	_restore_party(prior)

	assert_false(ids.has("potion"),
		"sell list must follow the live inventory — the potion was already used")
	assert_eq(owned, 0,
		"buy-menu owned count must follow the live inventory, not the pre-menu snapshot")
	assert_false(removed,
		"a snapshot copy is not stock; the sale must be refused")
	assert_eq(GameState.get_gold(), gold_before,
		"confirming the sale of a potion the party already used must not pay gold")
	assert_eq(refusal, "You don't have that item!",
		"the shop must say the sale was refused")
	assert_eq(snap_left, 1,
		"refusing the sale must leave the stale snapshot alone — the next sync overwrites it from live")
	assert_eq(int(live.inventory.get("potion", 0)), 0, "live inventory stays empty")


func test_a_live_only_potion_is_sellable() -> void:
	var prior: Array = GameState.player_party.duplicate(true)
	var snap: Array[Dictionary] = [{"name": "Tester", "inventory": {}}]
	GameState.player_party = snap

	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var live: Object = combatant_script.new()
	add_child_autofree(live)
	live.inventory = {"potion": 1}

	var stub: Node = _make_stub_gameloop([live])
	var shop: Object = load(SHOP_PATH).new()
	add_child_autofree(shop)
	shop.shop_type = 0

	var ids: Array = _sell_ids(shop)
	var owned: int = shop._get_owned_count("potion")
	var removed: bool = shop._remove_item_from_inventory("potion")
	stub.free()
	_restore_party(prior)

	assert_true(ids.has("potion"),
		"a chest or battle drop on the live party must appear in the sell list before the next menu-open sync")
	assert_eq(owned, 1, "buy-menu owned count must see the live potion")
	assert_true(removed, "the sale must consume the live potion")
	assert_eq(int(live.inventory.get("potion", 0)), 0, "live stock is the copy that leaves")
