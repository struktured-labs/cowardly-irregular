extends GutTest

## Shop stickers are not drops. gold_multiplier is the drop-rate dial
## (RebalanceDaemon calls it that; battle loot and chests consume it).
## Buy already charges the number on the shelf, via spend_gold.
## Sell and the failed-purchase refund went through add_gold, which
## multiplies. With the dial at 2 a potion whose line says "25 G"
## paid 50, and a purchase that could not hand the item over refunded
## twice what it had just taken — the wallet moved while the sentence
## on screen stayed the sticker.

var _gold: int
var _mult: Variant
var _party: Array


func before_each() -> void:
	_gold = GameState.party_gold
	_mult = GameState.game_constants.get("gold_multiplier", null)
	_party = GameState.player_party.duplicate(true)
	GameState.game_constants["gold_multiplier"] = 2.0


func after_each() -> void:
	GameState.party_gold = _gold
	if _mult == null:
		GameState.game_constants.erase("gold_multiplier")
	else:
		GameState.game_constants["gold_multiplier"] = _mult
	var typed: Array[Dictionary] = []
	for entry in _party:
		if entry is Dictionary:
			typed.append((entry as Dictionary).duplicate(true))
	GameState.player_party = typed


func _item_shop() -> ShopScene:
	var shop := ShopScene.new()
	add_child_autofree(shop)
	shop.shop_type = shop.ShopType.ITEM
	return shop


func _potion() -> Dictionary:
	return ItemSystem.get_item("potion")


func test_a_sale_pays_the_sticker_when_the_drop_rate_is_raised() -> void:
	GameState.party_gold = 1000
	var party: Array[Dictionary] = [{"name": "Tester", "inventory": {"potion": 1}}]
	GameState.player_party = party
	var shop := _item_shop()
	var data := _potion()
	var sticker: int = int(int(data.get("cost", 0)) * 0.5)
	await shop._attempt_sell("potion", data)
	assert_eq(GameState.get_gold(), 1000 + sticker,
		"the confirmation names the sticker, but the wallet was paid sticker times gold_multiplier")
	assert_eq(str(shop.description_label.text), "Sold %s for %d G!" % [str(data.get("name", "item")), sticker],
		"the line the player reads is the amount the wallet must move")


func test_a_failed_purchase_refunds_exactly_the_coins_it_took() -> void:
	GameState.party_gold = 1000
	var empty: Array[Dictionary] = []
	GameState.player_party = empty
	var shop := _item_shop()
	var data := _potion()
	assert_gt(int(data.get("cost", 0)), 0, "the potion fixture must have a price")
	await shop._attempt_purchase("potion", data)
	assert_eq(GameState.get_gold(), 1000,
		"a purchase that handed nothing over must put back the coins spend_gold removed, not coins times gold_multiplier")
	assert_true(str(shop.description_label.text).contains("refunded"),
		"the player must be told the gold came back")


func test_a_purchase_still_charges_the_sticker_when_the_drop_rate_is_raised() -> void:
	GameState.party_gold = 1000
	var party: Array[Dictionary] = [{"name": "Tester", "inventory": {}}]
	GameState.player_party = party
	var shop := _item_shop()
	var data := _potion()
	var cost: int = int(data.get("cost", 0))
	await shop._attempt_purchase("potion", data)
	assert_eq(GameState.get_gold(), 1000 - cost,
		"buying already ignores the drop-rate dial; the shelf price is the charge")
	assert_eq(int(GameState.player_party[0].get("inventory", {}).get("potion", 0)), 1,
		"the paid item has to land in the party inventory")


func test_a_sale_at_the_authored_drop_rate_still_pays_the_sticker() -> void:
	GameState.game_constants["gold_multiplier"] = 1.0
	GameState.party_gold = 1000
	var party: Array[Dictionary] = [{"name": "Tester", "inventory": {"potion": 1}}]
	GameState.player_party = party
	var shop := _item_shop()
	var data := _potion()
	var sticker: int = int(int(data.get("cost", 0)) * 0.5)
	await shop._attempt_sell("potion", data)
	assert_eq(GameState.get_gold(), 1000 + sticker,
		"with the dial at 1 the sale must still pay the sticker, not zero")
