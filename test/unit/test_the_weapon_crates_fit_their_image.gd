extends GutTest

## Regression (struktured's 2026-10-05 21:21 play log): 152 "Index p_y = 40..43 is out of bounds (height = 40)" on entering
## the blacksmith. _create_weapon_crates stacked two 22px crates into a 40px image, so the lower crate's last 4 rows were
## written out of bounds and never drawn. The image is now sized to the stack, so the lower crate is whole.

const ShopInteriorScript := preload("res://src/maps/interiors/ShopInterior.gd")


func _crates() -> Sprite2D:
	var shop = ShopInteriorScript.new()
	shop.shop_type = ShopInteriorScript.ShopType.BLACKSMITH
	add_child_autofree(shop)
	return shop.find_child("WeaponCrates", true, false) as Sprite2D


func test_the_crate_image_holds_both_crates() -> void:
	var c := _crates()
	assert_not_null(c, "SCOPE: the blacksmith builds its weapon crates")
	if c == null:
		return
	var img := c.texture.get_image()
	assert_gte(img.get_height(), ShopInteriorScript.WEAPON_CRATE_H * 2, "the image must hold both stacked crates, or the lower one writes out of bounds")


func test_the_lower_crate_reaches_its_last_row() -> void:
	var c := _crates()
	if c == null:
		fail_test("SCOPE: no weapon crates")
		return
	var img := c.texture.get_image()
	var y := ShopInteriorScript.WEAPON_CRATE_H * 2 - 1
	assert_gt(img.get_pixel(10, y).a, 0.5, "the lower crate's bottom plank is drawn, not clipped")


func test_the_item_shop_has_no_crates() -> void:
	var shop = ShopInteriorScript.new()
	add_child_autofree(shop)
	assert_null(shop.find_child("WeaponCrates", true, false), "CONTROL: crates belong to the blacksmith only")
