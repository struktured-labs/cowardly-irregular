extends GutTest

## Feature 2026-07-04: the buy menu listed every item at full price with no
## affordability cue — the player only learned they were short AFTER selecting
## (the "Insufficient gold!" message). Now each unaffordable row shows the exact
## gold shortfall, e.g. "Flame Sword - 1800G (need 300g)". Affordable rows stay
## unadorned. Helper ShopScene._affordability_suffix is pure.

const SHOP := preload("res://src/exploration/ShopScene.gd")


func _shop() -> ShopScene:
	var s: ShopScene = SHOP.new()
	autofree(s)  # pure helper, no _ready / tree needed
	return s


func test_unaffordable_shows_exact_shortfall() -> void:
	assert_eq(_shop()._affordability_suffix(1800, 1500), " (need 300g)",
		"an unaffordable item must show precisely how much more gold is needed")


func test_exactly_affordable_is_unadorned() -> void:
	assert_eq(_shop()._affordability_suffix(1800, 1800), "",
		"an item you can exactly afford shows no shortfall hint")


func test_comfortably_affordable_is_unadorned() -> void:
	assert_eq(_shop()._affordability_suffix(50, 9999), "",
		"a cheap item shows no hint when the player is flush")


func test_broke_player_shows_full_cost_as_shortfall() -> void:
	assert_eq(_shop()._affordability_suffix(120, 0), " (need 120g)",
		"with zero gold the shortfall equals the full price")


## struktured 2026-08-15: "(need Xg)" on the ROW truncated labels. The row now
## communicates by colour (grey = can't afford, green = already have) and the
## shortfall text moved to the description panel. Rows stay selectable.
func test_row_labels_no_longer_carry_the_truncating_suffix() -> void:
	var src := FileAccess.get_file_as_string("res://src/exploration/ShopScene.gd")
	var fn_idx := src.find("func _open_buy_menu")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body := src.substr(fn_idx, next_fn - fn_idx)
	assert_false("_affordability_suffix" in body,
		"the buy-row label must NOT append the shortfall suffix — it truncated")
	assert_true('"text_color"' in body, "rows carry the tint cue instead")


func test_shortfall_moved_to_the_description_panel() -> void:
	var src := FileAccess.get_file_as_string("res://src/exploration/ShopScene.gd")
	var fn_idx := src.find("func _update_description_for_item")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body := src.substr(fn_idx, next_fn - fn_idx)
	assert_true("_affordability_suffix" in body,
		"the description panel must surface the exact shortfall the row no longer shows")


func test_owned_and_unaffordable_tints_are_distinct() -> void:
	var shop = _shop()
	assert_ne(shop.BUY_ROW_OWNED_COLOR, shop.BUY_ROW_UNAFFORDABLE_COLOR,
		"already-have and can't-afford must read differently at a glance (struktured: 'but differently')")
	# Owned wins when both apply: knowing/wearing it matters more than today's gold.
	var src := FileAccess.get_file_as_string("res://src/exploration/ShopScene.gd")
	var fn_idx := src.find("func _open_buy_menu")
	var body := src.substr(fn_idx, src.find("\nfunc ", fn_idx + 1) - fn_idx)
	assert_lt(body.find("BUY_ROW_OWNED_COLOR"), body.find("BUY_ROW_UNAFFORDABLE_COLOR"),
		"owned tint branch precedes the affordability elif — owned wins when both apply")


func test_win98_menu_honors_text_color_without_breaking_disabled() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	assert_gte(src.count('item.get("text_color", null) is Color'), 2,
		"both render paths (row build + selection repaint) honor the per-row tint")
	# disabled grey must outrank the tint in both paths (tint is an elif after it)
	var i := 0
	while true:
		i = src.find('item.get("text_color", null) is Color', i + 1)
		if i < 0:
			break
		var before := src.substr(maxi(0, i - 220), 220)
		assert_true("disabled" in before,
			"the tint branch must sit AFTER the disabled check — disabled grey outranks it")
