extends GutTest

## The shop screen chose its keeper portrait by SHOP TYPE, and the keeper standing behind the counter spoke with the
## generic merchant face. So in Harmonia, Brutus greeted you as a merchant and then became Brutus when the wares
## opened; and in every other village the keeper (Greg, Dune, CACHE-1, Brother Frost) greeted you as a merchant and
## then became Harmonia's Brutus, Willow, Mortimer or Sister Lenora. One visit, one face: the four pictured keepers
## speak with their own portrait, and anyone else's shop screen shows the face they spoke with.

const ShopInteriorScript := preload("res://src/maps/interiors/ShopInterior.gd")
const ShopSceneScript := preload("res://src/exploration/ShopScene.gd")
const Dialogue := preload("res://src/cutscene/CutsceneDialogue.gd")
const PICTURED := {0: "Willow", 1: "Mortimer", 2: "Sister Lenora", 3: "Brutus"}
const STRANGERS := {0: "Shifty", 1: "Slag", 2: "Brother Frost", 3: "Greg"}


func _keeper_face(shop_type: int, keeper: String) -> String:
	## The portrait PATH the keeper behind the counter speaks with, through the real interior.
	var shop = ShopInteriorScript.new()
	shop.shop_type = shop_type
	shop.keeper_name = keeper
	add_child_autofree(shop)
	await get_tree().process_frame
	for n in shop.find_children("*", "Area2D", true, false):
		if str(n.get("npc_name")) == keeper:
			return str(Dialogue.PORTRAIT_SPRITES.get(str(n._portrait_key()), ""))
	return "<no keeper found>"


func test_a_pictured_keeper_speaks_with_the_face_their_shop_screen_shows() -> void:
	for t in PICTURED:
		var spoken: String = await _keeper_face(t, PICTURED[t])
		var shown: String = ShopSceneScript.keeper_portrait_path(t, PICTURED[t])
		assert_eq(shown, str(ShopSceneScript.KEEPER_PORTRAIT_PATHS[t]), "CONTROL: %s's shop screen shows their own portrait" % PICTURED[t])
		assert_eq(spoken, shown, "%s greets you with the face the wares screen shows" % PICTURED[t])


func test_another_villages_keeper_does_not_turn_into_harmonias() -> void:
	for t in STRANGERS:
		var spoken: String = await _keeper_face(t, STRANGERS[t])
		var shown: String = ShopSceneScript.keeper_portrait_path(t, STRANGERS[t])
		assert_true(FileAccess.file_exists(shown), "CONTROL: %s's shop screen has a portrait on disk (%s)" % [STRANGERS[t], shown])
		assert_ne(shown, str(ShopSceneScript.KEEPER_PORTRAIT_PATHS[t]), "%s is not shown as %s" % [STRANGERS[t], PICTURED[t]])
		assert_eq(spoken, shown, "%s keeps one face from the greeting to the wares" % STRANGERS[t])


func test_a_shop_opened_with_no_keeper_named_keeps_the_types_portrait() -> void:
	for t in PICTURED:
		assert_eq(ShopSceneScript.keeper_portrait_path(t, ""), str(ShopSceneScript.KEEPER_PORTRAIT_PATHS[t]), "an unnamed keeper is the type's own")
