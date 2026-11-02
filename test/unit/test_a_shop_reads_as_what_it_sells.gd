extends GutTest

## struktured 2026-11-01 (via cowir-main 21164), on the Harmonia pilot shots: "notice that crappy looking little what looks
## like black magic shop ... and to the right of that I think is the holy magic but it's the wrong color set". The dark-magic
## shop (Mortimer's Arcana) stood off every block as a painted stall, while the WHITE-magic shop sat on the purple arcana
## building, so the purple shop was the holy one. The two swap places, and an open-air shop shows its drawn stall.

const HARMONIA := "res://src/maps/villages/HarmoniaVillage.gd"


func _built(path: String) -> Node:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var v = load(path).new()
	vp.add_child(v)
	await get_tree().process_frame
	await get_tree().process_frame
	return v


func _shops(v: Node) -> Dictionary:
	var out := {}
	for b in v.get("buildings").get_children():
		if b is VillageShop:
			out[(b as VillageShop).shop_type] = b
	return out


func _art_path(shop: VillageShop) -> String:
	return str(VillageProp.prop_art_entry("shop_stall_" + VillageShop.stall_key_for(shop.shop_type), "medieval").get("path", ""))


func test_the_dark_magic_shop_is_the_arcana_building() -> void:
	var v = await _built(HARMONIA)
	var shops := _shops(v)
	assert_true(shops.has(VillageShop.ShopType.BLACK_MAGIC), "CONTROL: Harmonia has a dark-magic shop")
	var dark: VillageShop = shops[VillageShop.ShopType.BLACK_MAGIC]
	assert_false(dark.sprite.visible, "the dark-magic shop must stand in the purple arcana building, its stall hidden by the art")


func test_the_holy_shop_is_its_drawn_stall() -> void:
	var v = await _built(HARMONIA)
	var holy: VillageShop = _shops(v).get(VillageShop.ShopType.WHITE_MAGIC)
	assert_not_null(holy, "CONTROL: Harmonia has a white-magic shop")
	assert_true(holy.sprite.visible, "the white-magic shop stands in the open, so its stall must show")
	assert_ne(_art_path(holy), "", "a medieval white-magic stall must be drawn")
	assert_eq(holy.sprite.texture.resource_path, _art_path(holy), "the white-magic shop must show its drawn holy stall")


func test_no_harmonia_shop_shows_the_painted_stall() -> void:
	var v = await _built(HARMONIA)
	var shops := _shops(v)
	assert_eq(shops.size(), 4, "FLOOR: Harmonia's four shops")
	var painted: Array = []
	for t in shops:
		var s: VillageShop = shops[t]
		if s.sprite.visible and s.sprite.texture.resource_path != _art_path(s):
			painted.append(s.shop_name)
	assert_eq(painted, [], "these shops still show the painted stall: %s" % [painted])


func test_a_world_without_stall_art_keeps_the_painted_stall() -> void:
	## CONTROL: the drawn stall is keyed by world, so a shop elsewhere is not handed medieval art.
	var shop := VillageShop.new()
	shop.shop_type = VillageShop.ShopType.WHITE_MAGIC
	shop.art_world = "futuristic"
	add_child_autofree(shop)
	await get_tree().process_frame
	assert_true(shop.sprite.texture is ImageTexture, "a futuristic shop with no drawn stall must keep its painted one")
