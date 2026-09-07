extends GutTest

## Regression test for: ShopScene description panel never updates as the
## buy/sell cursor moves (stuck on the first item).
##
## Win98Menu emits no cursor-moved/highlight signal — only item_selected (on
## confirm) and menu_closed. Previously ShopScene painted the description panel
## exactly once at menu-open time (for item index 0) and never refreshed it
## while the player navigated the buy/sell list, so price / description /
## stat-comparison stayed frozen on item 0.
##
## Fix: ShopScene._process polls current_menu.get_selected_item_id() each frame
## (only in BUY/SELL mode) and calls _update_description_for_item when the
## highlighted row changes. These tests drive that poll directly.

const SHOP_SCRIPT := "res://src/exploration/ShopScene.gd"

var _game_state: Node


func before_all() -> void:
	_game_state = get_tree().root.get_node_or_null("GameState")


func _make_buy_shop(inventory: Array) -> Node:
	# Build a fully-initialized ITEM shop sitting in BUY mode.
	var ShopSceneScript = load(SHOP_SCRIPT)
	var shop = add_child_autofree(ShopSceneScript.new())
	# _ready ran on add_child: UI built, main menu open. Configure + open buy.
	shop.setup(shop.ShopType.ITEM, "Test Shop", inventory, null)
	shop._open_buy_menu()
	return shop


func test_description_updates_when_cursor_moves_in_buy_menu() -> void:
	var shop := _make_buy_shop(["potion", "hi_potion", "ether"])

	# On open, the description reflects the first item (Potion).
	assert_true(
		shop.description_label.text.findn("Potion") != -1,
		"Buy menu should open describing the first item (Potion). Got: %s" % shop.description_label.text
	)

	# Move the menu cursor to the second row (Hi-Potion) like a ui_down press,
	# then run the per-frame poll that ShopScene uses in lieu of a signal.
	shop.current_menu.selected_index = 1
	shop._process(0.0)

	assert_true(
		shop.description_label.text.findn("Hi-Potion") != -1,
		"Description should follow the cursor to Hi-Potion. Got: %s" % shop.description_label.text
	)
	# And it must NOT still be showing the original first item.
	assert_eq(
		shop.description_label.text.findn("Welcome"), -1,
		"Description should no longer show the welcome/open text after cursor move"
	)


func test_description_reflects_third_item_after_navigating_down() -> void:
	var shop := _make_buy_shop(["potion", "hi_potion", "ether"])

	shop.current_menu.selected_index = 2
	shop._process(0.0)

	assert_true(
		shop.description_label.text.findn("Ether") != -1,
		"Description should update to Ether when cursor lands on row 2. Got: %s" % shop.description_label.text
	)


func test_process_is_noop_when_cursor_unchanged() -> void:
	var shop := _make_buy_shop(["potion", "hi_potion", "ether"])

	# Force a sentinel into the label, leave the cursor on the same row, and
	# verify the poll does NOT repaint (it only fires on a real selection change).
	shop.current_menu.selected_index = 1
	shop._process(0.0)  # paints Hi-Potion, syncs tracker
	shop.description_label.text = "SENTINEL"
	shop._process(0.0)  # cursor unchanged -> must not overwrite

	assert_eq(
		shop.description_label.text, "SENTINEL",
		"Poll must be a no-op while the highlighted row is unchanged"
	)


func test_process_ignored_outside_buy_sell_mode() -> void:
	var ShopSceneScript = load(SHOP_SCRIPT)
	var shop = add_child_autofree(ShopSceneScript.new())
	shop.setup(shop.ShopType.ITEM, "Test Shop", ["potion", "hi_potion"], null)
	# Stay in MAIN mode (Buy/Sell/Exit menu). The poll must not touch the panel.
	shop.current_mode = shop.ShopMode.MAIN
	shop.description_label.text = "MAIN_TEXT"
	shop._process(0.0)

	assert_eq(
		shop.description_label.text, "MAIN_TEXT",
		"Description poll should be inert outside BUY/SELL mode"
	)


func test_process_skips_placeholder_none_row() -> void:
	# An empty shop yields a single disabled 'none' row; the poll must not try
	# to describe it (which would early-return on empty item data anyway).
	var shop := _make_buy_shop([])
	shop.description_label.text = "PLACEHOLDER"
	# Selected row id is 'none'.
	assert_eq(shop.current_menu.get_selected_item_id(), "none", "empty shop should select the 'none' placeholder")
	# Force the tracker to differ so the poll reaches the 'none' guard
	# (rather than short-circuiting on the unchanged-id check).
	shop._last_described_item_id = "stale"
	shop._process(0.0)

	assert_eq(
		shop.description_label.text, "PLACEHOLDER",
		"Poll must skip the 'none' placeholder row without repainting"
	)
