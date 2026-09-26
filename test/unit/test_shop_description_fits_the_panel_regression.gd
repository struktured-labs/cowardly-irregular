extends GutTest

## The description panel was 120px tall. Item text starts 16px down and each
## line is 25px plus the theme's 3px gap, so a general-store row (name,
## effect, blank, blank, "Cost: 50 G") already ends past the frame, and the
## Label does not clip. Blacksmith comparisons and magic (MP cost) are longer.
## The last line of every shelf description has to stay inside the panel, and
## the buy list still has to stop above that panel.

const ShopSceneScript := preload("res://src/exploration/ShopScene.gd")

var _prior_party: Array = []
var _prior_gold: int = 0


func before_each() -> void:
	_prior_party = GameState.player_party.duplicate(true)
	_prior_gold = GameState.party_gold
	var wearing: Array[Dictionary] = [{
		"name": "Fighter",
		"equipped_weapon": "iron_sword",
		"equipped_armor": "iron_armor",
		"equipped_accessory": "",
		"inventory": {"potion": 2, "ether": 1, "elixir": 1},
	}]
	GameState.player_party = wearing
	# Broke, so the gold-shortfall lines are in the text. That is the tallest
	# form _update_description_for_item paints for a given item.
	GameState.party_gold = 0


func after_each() -> void:
	var typed: Array[Dictionary] = []
	for entry in _prior_party:
		if entry is Dictionary:
			typed.append((entry as Dictionary).duplicate(true))
	GameState.player_party = typed
	GameState.party_gold = _prior_gold


func _block_bottom(label: Label) -> float:
	var lines := label.get_line_count()
	if lines <= 0:
		return label.position.y
	var line_h := float(label.get_line_height())
	var gap := float(label.get_theme_constant("line_spacing"))
	return label.position.y + line_h * float(lines) + gap * float(lines - 1)


func _open(shop_type: int, title: String, inventory: Array, sell: bool) -> ShopScene:
	var shop: ShopScene = ShopSceneScript.new()
	add_child_autofree(shop)
	shop.setup(shop_type, title, inventory)
	if sell:
		shop._open_sell_menu()
	else:
		shop._open_buy_menu()
	return shop


func _assert_every_description_fits(shop: ShopScene, ids: Array, where: String) -> void:
	var panel: Control = shop.description_panel
	var label: Label = shop.description_label
	assert_not_null(panel, "%s has a description panel" % where)
	assert_not_null(label, "%s has a description label" % where)
	var tallest_id := ""
	var tallest_bottom := -1.0
	var tallest_lines := 0
	for raw_id in ids:
		var item_id := str(raw_id)
		if item_id.is_empty():
			continue
		shop._update_description_for_item(item_id)
		var bottom := _block_bottom(label)
		if bottom > tallest_bottom:
			tallest_bottom = bottom
			tallest_id = item_id
			tallest_lines = label.get_line_count()
		assert_lte(bottom, panel.size.y,
			"%s %s last line bottom %.1f must stay inside the panel (h=%.1f). text:\n%s" % [
				where, item_id, bottom, panel.size.y, label.text])
	assert_gt(tallest_lines, 4,
		"CONTROL: %s still paints a multi-line description (got %d on %s)" % [where, tallest_lines, tallest_id])
	assert_gt(tallest_bottom, 120.0,
		"CONTROL: %s text is taller than the old 120px panel, else this cannot catch the overflow" % where)
	var menu: Win98Menu = shop.current_menu
	assert_not_null(menu, "%s opened a menu" % where)
	assert_lte(menu.position.y + menu.size.y, panel.position.y,
		"%s list must stop above the description. bottom=%s panel_y=%s" % [
			where, menu.position.y + menu.size.y, panel.position.y])
	if menu.menu_items.size() > menu._max_visible_rows and menu._max_visible_rows > 0:
		assert_gt(menu._max_visible_rows, 1,
			"%s shelf still shows a window of whole rows" % where)


func test_buy_descriptions_stay_inside_the_panel_for_every_shop_type() -> void:
	var shelves: Array = [
		[ShopScene.ShopType.ITEM, "General Store", VillageShop.ITEM_INVENTORY.duplicate()],
		[ShopScene.ShopType.BLACK_MAGIC, "Magic Shop", VillageShop.BLACK_MAGIC_INVENTORY.duplicate()],
		[ShopScene.ShopType.WHITE_MAGIC, "White Magic", VillageShop.WHITE_MAGIC_INVENTORY.duplicate()],
		[ShopScene.ShopType.BLACKSMITH, "Blacksmith", (VillageShop.BLACKSMITH_WEAPONS + VillageShop.BLACKSMITH_ARMOR).duplicate()],
	]
	for shelf in shelves:
		var shop := _open(shelf[0], shelf[1], shelf[2], false)
		_assert_every_description_fits(shop, shelf[2], shelf[1])
		var sample: String = ""
		shop._update_description_for_item(str(shelf[2][0]))
		sample = shop.description_label.text
		assert_true(sample.contains("Cost:"),
			"%s buy text still names the cost. Got:\n%s" % [shelf[1], sample])
	await get_tree().create_timer(0.05, true, false, true).timeout


func test_sell_descriptions_stay_inside_the_panel() -> void:
	var shop := _open(ShopScene.ShopType.ITEM, "General Store", VillageShop.ITEM_INVENTORY.duplicate(), true)
	var ids: Array = []
	for entry in shop._get_sellable_inventory():
		ids.append(entry["id"])
	assert_gte(ids.size(), 2, "CONTROL: the party has items to sell")
	_assert_every_description_fits(shop, ids, "Sell")
	shop._update_description_for_item("potion")
	assert_true(shop.description_label.text.contains("Sell:"),
		"sell text still names the sell price. Got:\n%s" % shop.description_label.text)
	assert_true(shop.description_label.text.contains("Restores 500 HP"),
		"potion wording is unchanged. Got:\n%s" % shop.description_label.text)
	await get_tree().create_timer(0.05, true, false, true).timeout
