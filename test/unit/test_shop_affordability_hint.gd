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
