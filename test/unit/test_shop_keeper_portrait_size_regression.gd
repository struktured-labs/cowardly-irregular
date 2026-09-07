extends GutTest

## Regression: the shop keeper portrait rendered at 256x256 instead of 64x64, hanging 132px
## off the bottom of a 720p screen and running under the description text. Found in
## smoke/shop.png (only the keeper's forehead and eyes were visible) and pinned by a runtime
## probe of the panel's child rects:
##
##   @TextureRect pos=(16,16) size=(256,256) global=[P: (36,596), S: (256,256)]
##
## Cause is assignment ORDER, not arithmetic. The code set:
##     texrect.size = Vector2(64, 64)
##     texrect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # one line too late
## While expand_mode is still the default, a TextureRect's minimum size is its texture's
## size (the keeper PNGs are all 256x256), so assigning 64 is clamped straight back up.
## Setting expand_mode first makes the 64 stick.
##
## Assert the RELATIONSHIP — the portrait must fit inside the panel it is parented to —
## rather than the literal 64, so a deliberate resize of the panel or the portrait stays
## green while an overflow of any size fails.

const KEEPER_DIR := "res://assets/sprites/portraits/keepers/"


func _shop_with_panel(shop_type: int) -> Node:
	var ShopSceneScript = load("res://src/exploration/ShopScene.gd")
	var shop = ShopSceneScript.new()
	add_child_autofree(shop)
	shop.setup(shop_type, "Test Shop", [], null)
	return shop


func _portrait_of(shop: Node) -> Control:
	var panel: Control = shop.description_panel
	if panel == null:
		return null
	for c in panel.get_children():
		if c is TextureRect:
			return c
	return null


func test_control_the_keeper_pngs_are_larger_than_the_slot() -> void:
	# CONTROL: the whole defect depends on the texture being bigger than 64. If the art is
	# ever redrawn at 64x64 the clamp cannot fire and the assertions below go vacuous.
	var tex: Texture2D = load(KEEPER_DIR + "mortimer.png")
	assert_not_null(tex, "keeper portrait must exist")
	assert_gt(tex.get_width(), 64,
		"CONTROL: texture must exceed the 64px slot, else the min-size clamp cannot occur")


func test_portrait_fits_inside_its_panel() -> void:
	var shop := _shop_with_panel(1)  # BLACK_MAGIC — the type the render smoke exercises
	var portrait := _portrait_of(shop)
	assert_not_null(portrait, "black-magic shop must render a keeper portrait")
	var panel: Control = shop.description_panel
	assert_true(portrait.size.x <= panel.size.x and portrait.size.y <= panel.size.y,
		"portrait %s must fit inside panel %s — 256x256 hung 132px off a 720p screen" % [str(portrait.size), str(panel.size)])


func test_portrait_does_not_run_under_the_description_text() -> void:
	var shop := _shop_with_panel(1)
	var portrait := _portrait_of(shop)
	assert_not_null(portrait, "precondition: portrait present")
	var label: Control = shop.description_label
	assert_not_null(label, "precondition: description label present")
	assert_true(portrait.position.x + portrait.size.x <= label.position.x,
		"portrait right edge %s must clear the text at x=%s — the layout budgets 16+64+12" % [
			str(portrait.position.x + portrait.size.x), str(label.position.x)])
