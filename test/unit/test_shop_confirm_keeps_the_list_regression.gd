extends GutTest

## Confirming a shop row always force-closes that Win98Menu, and ShopScene
## treated every close as Back. A buy the player cannot afford set
## "Insufficient gold!" and then the close opened Buy/Sell/Exit, so the
## explanation was gone in the same frame and the cursor with it. A sale
## did the same: the receipt flashed the welcome line, and half a second
## later the list rebuilt at the top. Back (no confirm) must still leave.

const SHOP_SCRIPT := "res://src/exploration/ShopScene.gd"

## Long enough that the buy list scrolls inside a 720p frame. These ids are
## real shelf stock, so the rows resolve and the last one has a price.
const SHELF := [
	"potion", "antidote", "eye_drops", "echo_herbs", "smoke_bomb",
	"hi_potion", "ether", "phoenix_down", "gold_needle",
	"power_drink", "speed_tonic", "defense_tonic", "magic_tonic",
	"bomb_fragment", "lightning_bolt", "holy_water",
	"remedy", "repel", "x_potion", "hi_ether",
	"arctic_wind", "mega_potion", "tent", "mega_ether", "elixir",
]

var _gold: int
var _party: Array


func before_each() -> void:
	_gold = GameState.party_gold
	_party = GameState.player_party.duplicate(true)


func after_each() -> void:
	GameState.party_gold = _gold
	var typed: Array[Dictionary] = []
	for entry in _party:
		if entry is Dictionary:
			typed.append((entry as Dictionary).duplicate(true))
	GameState.player_party = typed


func _shop() -> ShopScene:
	var shop: ShopScene = load(SHOP_SCRIPT).new()
	add_child_autofree(shop)
	return shop


func _party_with(inventory: Dictionary) -> void:
	var party: Array[Dictionary] = [{"name": "Tester", "inventory": inventory}]
	GameState.player_party = party


func _row(menu: Win98Menu, item_id: String) -> int:
	for i in range(menu.menu_items.size()):
		if str(menu.menu_items[i].get("id", "")) == item_id:
			return i
	return -1


func _land(menu: Win98Menu, index: int) -> void:
	menu.selected_index = index
	menu._update_selection()


## The player highlights a sword they cannot buy and presses confirm.
## They must still be on that row, reading why, not back at Buy/Sell/Exit.
func test_an_unaffordable_confirm_stays_on_that_row() -> void:
	GameState.party_gold = 0
	var shop := _shop()
	shop.setup(shop.ShopType.ITEM, "Mystic Remedies", SHELF, null)
	shop._open_buy_menu()
	await get_tree().process_frame
	var menu: Win98Menu = shop.current_menu
	var last := menu.menu_items.size() - 1
	_land(menu, last)
	var scroll: int = menu._scroll_offset
	var item_id := menu.get_selected_item_id()
	assert_gt(scroll, 0, "the fixture must scroll — a short list cannot catch a lost scroll offset")
	assert_eq(item_id, "elixir", "the cursor was aimed at the last shelf row")

	menu._submit_actions()
	await get_tree().process_frame

	assert_eq(shop.current_mode, shop.ShopMode.BUY,
		"confirming a buy you cannot afford must not leave the list")
	assert_true(str(shop.description_label.text).contains("Insufficient gold"),
		"the explanation has to stay on screen. Got: %s" % shop.description_label.text)
	assert_eq(shop.current_menu.get_selected_item_id(), item_id,
		"the cursor must stay on the row the player confirmed")
	assert_eq(shop.current_menu.selected_index, last,
		"the cursor index must not jump back to the top of the shelf")
	assert_eq(shop.current_menu._scroll_offset, scroll,
		"the list must stay scrolled to that row")
	assert_eq(GameState.get_gold(), 0, "a refused buy must not move gold")


## Buying something affordable used to flash the main menu, then rebuild the
## shelf at row 0. The receipt stays, and so does the place in the list,
## including after the owned-count refresh.
func test_a_purchase_keeps_the_cursor_through_the_refresh() -> void:
	GameState.party_gold = 50000
	_party_with({})
	var shop := _shop()
	shop.setup(shop.ShopType.ITEM, "Mystic Remedies", SHELF, null)
	shop._open_buy_menu()
	await get_tree().process_frame
	var menu: Win98Menu = shop.current_menu
	var last := menu.menu_items.size() - 1
	_land(menu, last)
	var scroll: int = menu._scroll_offset
	menu._submit_actions()
	await get_tree().process_frame

	assert_eq(shop.current_mode, shop.ShopMode.BUY,
		"a successful buy must stay on the shelf, not bounce through the main menu")
	assert_true(str(shop.description_label.text).contains("Purchased"),
		"the receipt must survive the menu close. Got: %s" % shop.description_label.text)
	assert_eq(shop.current_menu.selected_index, last, "cursor stays on the bought row")
	assert_eq(shop.current_menu._scroll_offset, scroll, "scroll stays with that row")

	await get_tree().create_timer(0.7).timeout
	assert_eq(shop.current_mode, shop.ShopMode.BUY, "the refresh must not kick the player out")
	assert_eq(shop.current_menu.selected_index, last,
		"the owned-count refresh must not send the cursor back to the top")
	assert_eq(shop.current_menu._scroll_offset, scroll,
		"the owned-count refresh must not jump the scroll back to the top")
	assert_eq(int(GameState.player_party[0].get("inventory", {}).get("elixir", 0)), 1,
		"the purchase still has to land")


## Leaving during the receipt window used to get overwritten when the
## half-second refresh opened the buy list again.
func test_leaving_during_the_receipt_is_not_pulled_back() -> void:
	GameState.party_gold = 50000
	_party_with({})
	var shop := _shop()
	shop.setup(shop.ShopType.ITEM, "Mystic Remedies", ["potion", "ether"], null)
	shop._open_buy_menu()
	await get_tree().process_frame
	shop.current_menu._submit_actions()
	await get_tree().process_frame
	var stayed: bool = shop.current_mode == shop.ShopMode.BUY
	assert_true(stayed, "the receipt has to leave the buy list open so Back is a real choice")
	if stayed:
		shop._on_menu_closed()
		assert_eq(shop.current_mode, shop.ShopMode.MAIN, "Back from the shelf returns to Buy/Sell/Exit")
		await get_tree().create_timer(0.7).timeout
		assert_eq(shop.current_mode, shop.ShopMode.MAIN,
			"the post-purchase refresh must not pull the player back into the list")
	else:
		await get_tree().create_timer(0.7).timeout


## Selling the last copy of a row must pay the sticker, say so, and land the
## cursor on a row that still exists — not on the main menu, and not past the end.
func test_selling_the_last_copy_keeps_a_real_row() -> void:
	GameState.party_gold = 100
	_party_with({"potion": 2, "ether": 1})
	var shop := _shop()
	shop.setup(shop.ShopType.ITEM, "Mystic Remedies", ["potion"], null)
	shop._open_sell_menu()
	await get_tree().process_frame
	var menu: Win98Menu = shop.current_menu
	var ether_at := _row(menu, "ether")
	assert_gt(ether_at, 0, "ether has to be a later sell row so the cursor has somewhere to fall")
	_land(menu, ether_at)
	var ether: Dictionary = ItemSystem.get_item("ether")
	var sticker: int = int(int(ether.get("cost", 0)) * 0.5)
	menu._submit_actions()
	await get_tree().process_frame

	assert_eq(shop.current_mode, shop.ShopMode.SELL,
		"selling must not dump the player on Buy/Sell/Exit")
	assert_eq(str(shop.description_label.text), "Sold %s for %d G!" % [str(ether.get("name", "item")), sticker],
		"the receipt is the sticker, and the close must not replace it. Got: %s" % shop.description_label.text)
	assert_eq(GameState.get_gold(), 100 + sticker, "the wallet is paid the sticker for the last copy")
	assert_eq(int(GameState.player_party[0].get("inventory", {}).get("ether", 0)), 0,
		"the last copy is gone")
	assert_eq(int(GameState.player_party[0].get("inventory", {}).get("potion", 0)), 2,
		"the other stack is untouched")
	var rebuilt: Win98Menu = shop.current_menu
	assert_gt(rebuilt.menu_items.size(), 0, "the other stack is still for sale")
	assert_true(rebuilt.selected_index >= 0 and rebuilt.selected_index < rebuilt.menu_items.size(),
		"the cursor must sit on a row that still exists")
	assert_false(_row(rebuilt, "ether") >= 0, "the sold-out row must leave the list")
	assert_eq(rebuilt.get_selected_item_id(), "potion",
		"the cursor settles on the row that slid into the gap")

	await get_tree().create_timer(0.7).timeout
	assert_eq(shop.current_mode, shop.ShopMode.SELL, "the refresh stays on the sell list")
	assert_eq(shop.current_menu.get_selected_item_id(), "potion",
		"the refresh must not throw the cursor at a row that was sold")


## Back, with nothing confirmed, still leaves. The hold is only for a confirm.
func test_cancel_without_a_confirm_still_leaves_the_list() -> void:
	var shop := _shop()
	shop.setup(shop.ShopType.ITEM, "Mystic Remedies", ["potion"], null)
	shop._open_buy_menu()
	await get_tree().process_frame
	shop._on_menu_closed()
	assert_eq(shop.current_mode, shop.ShopMode.MAIN, "Back from the shelf still returns to Buy/Sell/Exit")
