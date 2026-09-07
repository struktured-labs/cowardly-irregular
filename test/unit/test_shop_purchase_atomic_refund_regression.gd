extends GutTest

## Regression: ShopScene._attempt_purchase must refund the spent gold
## when _add_item_to_inventory can't actually receive the item (empty
## player_party, unknown shop_type, etc.).
##
## Bug shape:
##   • _attempt_purchase did:
##       if game_state.spend_gold(cost):
##           _add_item_to_inventory(item_id)
##           description_label.text = "Purchased %s for %d G!"
##   • _add_item_to_inventory was void-returning. If player_party was
##     empty (or shop_type was unhandled), it silently no-op'd. The
##     gold was already deducted, the dialog showed "Purchased X!",
##     but no item appeared. Net: player loses gold, gets nothing.
##   • Reachable when the shop is opened during a brief mid-load
##     window where GameState.player_party has been cleared but not
##     yet rehydrated (save load race), or in test paths.
##
## Fix: _add_item_to_inventory now returns bool. _attempt_purchase
## checks the result; if false, it refunds via game_state.add_gold(cost)
## and surfaces a clear failure message instead of the success text.
##
## Tests:
##   • Source pin: _add_item_to_inventory returns bool
##   • Source pin: _attempt_purchase captures the return AND refunds
##     on failure (game_state.add_gold(cost) in the failure branch)
##   • Behavioural: drive _add_item_to_inventory on an empty party,
##     assert it returns false (the canary the refund branch depends on)
##   • Behavioural: drive _add_item_to_inventory on a real party,
##     assert it returns true and the inventory got the new entry

const SHOP_SCENE_PATH := "res://src/exploration/ShopScene.gd"
const ShopSceneScript := preload("res://src/exploration/ShopScene.gd")


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_add_item_to_inventory_returns_bool() -> void:
	var text := _read(SHOP_SCENE_PATH)
	var idx := text.find("func _add_item_to_inventory")
	assert_gt(idx, -1, "_add_item_to_inventory must exist")
	# Grab the signature line.
	var sig_end := text.find("\n", idx)
	var sig: String = text.substr(idx, sig_end - idx)
	assert_true(sig.contains("-> bool"),
		"_add_item_to_inventory must declare `-> bool` so callers can detect failure")


func test_attempt_purchase_refunds_on_failed_add() -> void:
	# Pin: _attempt_purchase reads the return of _add_item_to_inventory
	# AND has a refund branch using game_state.add_gold(cost).
	var text := _read(SHOP_SCENE_PATH)
	var idx := text.find("func _attempt_purchase")
	assert_gt(idx, -1, "_attempt_purchase must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# The return must be captured (e.g. `var added: bool = _add_item_to_inventory(item_id)`).
	assert_true(body.contains("= _add_item_to_inventory("),
		"_attempt_purchase must capture _add_item_to_inventory's return value")
	# A refund call against game_state.add_gold(cost) must appear in the
	# function body (the failure-recovery path).
	assert_true(body.contains("game_state.add_gold(cost)"),
		"_attempt_purchase must refund the spent gold (game_state.add_gold(cost)) when the add fails")


# ── Behavioural ──────────────────────────────────────────────────────────────

func test_add_returns_false_on_empty_party() -> void:
	# Drive _add_item_to_inventory on a live ShopScene wired to the
	# GameState autoload with an empty player_party. Snapshot + restore
	# so other tests don't see the mutation.
	var shop: ShopScene = ShopSceneScript.new()
	add_child_autofree(shop)
	var gs = GameState
	var prior_party: Array = gs.player_party.duplicate(true)
	# player_party is strictly typed Array[Dictionary] — assigning a plain
	# Array errors. Use a typed-empty literal.
	var empty_party: Array[Dictionary] = []
	gs.player_party = empty_party
	shop.game_state = gs
	shop.shop_type = shop.ShopType.ITEM
	var result: bool = shop._add_item_to_inventory("potion")
	assert_false(result,
		"_add_item_to_inventory must return false when player_party is empty")
	# Restore.
	var typed_party: Array[Dictionary] = []
	for e in prior_party:
		if e is Dictionary:
			typed_party.append(e.duplicate(true))
	gs.player_party = typed_party


func test_add_returns_true_on_real_party_and_inventory_updates() -> void:
	# Inverse case: with a real party member, the add must succeed AND
	# the inventory dict must reflect the new item.
	var shop: ShopScene = ShopSceneScript.new()
	add_child_autofree(shop)
	var gs = GameState
	var prior_party: Array = gs.player_party.duplicate(true)
	# Use a fresh typed party with one member that has an empty inventory.
	var fresh_party: Array[Dictionary] = [{"name": "Tester", "inventory": {}}]
	gs.player_party = fresh_party
	shop.game_state = gs
	shop.shop_type = shop.ShopType.ITEM
	var result: bool = shop._add_item_to_inventory("potion")
	assert_true(result,
		"_add_item_to_inventory must return true when a recipient exists")
	var leader: Dictionary = gs.player_party[0]
	var inv: Dictionary = leader.get("inventory", {})
	assert_eq(int(inv.get("potion", 0)), 1,
		"the recipient's inventory must reflect the new item (potion x1)")
	# Restore.
	var typed_party: Array[Dictionary] = []
	for e in prior_party:
		if e is Dictionary:
			typed_party.append(e.duplicate(true))
	gs.player_party = typed_party
