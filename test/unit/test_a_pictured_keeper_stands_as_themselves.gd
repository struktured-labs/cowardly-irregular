extends GutTest

## Every shop keeper stood behind the counter as the generic MERCHANT walk sheet (a dark-haired man in a green apron),
## whatever their portrait showed. Brutus is the blacksmith sheet and Sister Lenora the priestess sheet. Willow and
## Mortimer had NO sheet and stood as that mustached merchant behind a young woman's and a dark-haired man's face
## (struktured 2026-10-30: "npc looks like mario with the mustache"); keeper_willow/keeper_mortimer are drawn from
## their portraits. A keeper who is not pictured still walks and speaks as the merchant.

const ShopInteriorScript := preload("res://src/maps/interiors/ShopInterior.gd")
const ShopSceneScript := preload("res://src/exploration/ShopScene.gd")


func _keeper(shop_type: int, keeper: String) -> Node:
	var shop = ShopInteriorScript.new()
	shop.shop_type = shop_type
	shop.keeper_name = keeper
	add_child_autofree(shop)
	await get_tree().process_frame
	for n in shop.find_children("*", "Area2D", true, false):
		if str(n.get("npc_name")) == keeper:
			return n
	return null


func test_brutus_and_lenora_stand_as_the_sheet_that_is_their_picture() -> void:
	for spec in [[3, "Brutus", "blacksmith", "keeper_brutus"], [2, "Sister Lenora", "priestess", "keeper_lenora"]]:
		var n: Node = await _keeper(spec[0], spec[1])
		assert_not_null(n, "CONTROL: %s stands in the shop" % spec[1])
		if n == null:
			continue
		assert_eq(str(n.get("_archetype_id")), spec[2], "%s is DRAWN from the %s sheet" % [spec[1], spec[2]])
		assert_eq(str(n._portrait_key()), spec[3], "%s still speaks with their own portrait" % spec[1])


func test_willow_and_mortimer_stand_as_their_own_picture() -> void:
	for spec in [[0, "Willow", "keeper_willow"], [1, "Mortimer", "keeper_mortimer"]]:
		var n: Node = await _keeper(spec[0], spec[1])
		assert_not_null(n, "CONTROL: %s stands in the shop" % spec[1])
		if n == null:
			continue
		assert_eq(str(n.get("_archetype_id")), spec[2], "%s is DRAWN from their own sheet, not the merchant's" % spec[1])
		assert_eq(str(n._portrait_key()), spec[2], "%s's face and body are the same person" % spec[1])


func test_another_villages_smith_is_not_dressed_as_brutus() -> void:
	var n: Node = await _keeper(3, "Greg")
	assert_not_null(n, "CONTROL: Greg stands in the shop")
	if n == null:
		return
	assert_eq(str(n.get("_archetype_id")), "merchant", "an unpictured keeper keeps the sheet whose face they speak with")
	assert_eq(str(n._portrait_key()), "merchant")


func test_every_named_sheet_exists() -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var sheets: Dictionary = m.get("overworld_npc_sheets", {})
	var unsheeted: Array = []
	for t in ShopSceneScript.PICTURED_KEEPERS:
		var who: Array = ShopSceneScript.PICTURED_KEEPERS[t]
		var sheet := str(who[2])
		if sheet == "":
			unsheeted.append(str(who[0]))
			continue
		assert_true(sheets.has(sheet), "the %s sheet is registered" % sheet)
	assert_gt(ShopSceneScript.PICTURED_KEEPERS.size(), 0, "CONTROL: there are pictured keepers to judge")
	assert_eq(unsheeted, [], "a PICTURED keeper with no sheet stands as the merchant behind their own face")
