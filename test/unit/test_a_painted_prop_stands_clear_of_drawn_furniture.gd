extends GutTest

## .766 follow-up (cowir-overworld's shots): in Harmonia's drawn shops the painted anvil stood on the smithy's lower-left
## shelf block and the painted barrels on the item shop's right one. A drawn shelf or counter is the room's furniture;
## nothing painted may sit on its cells.

const ShopInteriorScript := preload("res://src/maps/interiors/ShopInterior.gd")
const ROOMS := {ShopInteriorScript.ShopType.ITEM: "shop_item", ShopInteriorScript.ShopType.BLACKSMITH: "shop_blacksmith"}
const T := 32.0

func after_each() -> void:
	VillageProp.prop_art_override = null


func _shop(type: int) -> Node:
	var shop = ShopInteriorScript.new()
	shop.shop_type = type
	add_child_autofree(shop)
	return shop


## Every painted sprite under decorations, as "name@rect" for each one whose rect covers a C/S cell.
func _on_furniture(shop: Node) -> Array[String]:
	var cells := InteriorArt.furniture_cells(ShopInteriorScript.SHOP_LAYOUT, "CS")
	var out: Array[String] = []
	for n in shop.decorations.find_children("*", "Sprite2D", true, false):
		var spr := n as Sprite2D
		if spr.texture == null or not spr.is_visible_in_tree():
			continue
		var r := spr.get_rect()
		r.position += spr.global_position - shop.global_position
		for c in cells:
			if r.intersects(Rect2(Vector2(c) * T, Vector2(T, T))):
				out.append("%s@%s" % [spr.get_parent().name if spr.name.begins_with("@") else spr.name, r])
				break
	return out


func _drawn(type: int) -> Dictionary:
	var room: String = ROOMS[type]
	var o := {}
	for kind in ["counter", "shelf"]:
		o["%s_%s" % [kind, room]] = {"path": "res://assets/sprites/interiors/harmonia/%s_%s.png" % [kind, room]}
	return o


func test_the_detector_sees_painted_goods_on_painted_shelves() -> void:
	VillageProp.prop_art_override = {}
	assert_gt(_on_furniture(_shop(ShopInteriorScript.ShopType.ITEM)).size(), 0, "CONTROL: a painted shop's goods sit on its shelves, and the detector must see them")


func test_nothing_painted_stands_on_a_drawn_shops_furniture() -> void:
	for type in ROOMS:
		VillageProp.prop_art_override = _drawn(type)
		var hits := _on_furniture(_shop(type))
		assert_eq(hits.size(), 0, "%s: painted props on drawn furniture: %s" % [ROOMS[type], hits])


func test_a_drawn_counter_carries_its_own_top() -> void:
	## The painted counter trim was placed at x=5.5 tiles, off the counter (cols 7-9) and onto the left shelf.
	VillageProp.prop_art_override = {}
	assert_not_null(_shop(ShopInteriorScript.ShopType.ITEM).decorations.find_child("CounterTrim", false, false), "CONTROL: a painted counter is dressed with its trim")
	VillageProp.prop_art_override = _drawn(ShopInteriorScript.ShopType.ITEM)
	assert_null(_shop(ShopInteriorScript.ShopType.ITEM).decorations.find_child("CounterTrim", false, false), "a painted trim was laid over a drawn counter")
