extends GutTest

## The footprint helpers @cowir-overworld's NPC-placement guard reads (cowir-main 21502: NPCs stood on drawn furniture).

const ShopInteriorScript := preload("res://src/maps/interiors/ShopInterior.gd")


func after_each() -> void:
	VillageProp.prop_art_override = null


func test_a_shop_layout_footprint_is_its_counter_and_shelves() -> void:
	var cells := InteriorArt.furniture_cells(ShopInteriorScript.SHOP_LAYOUT, "CS")
	assert_true(Vector2i(7, 3) in cells, "the counter's first cell is furniture")
	assert_true(Vector2i(2, 6) in cells and Vector2i(4, 7) in cells, "the lower-left shelf block is furniture")
	assert_false(Vector2i(5, 6) in cells, "CONTROL: the aisle between the shelves is floor")
	assert_eq(cells.size(), 36, "every C and S cell and nothing else: the counter 6 + two 3x3 and two 3x2 shelf blocks")


func test_the_outer_wall_rows_are_never_furniture() -> void:
	var layout := ["DDD", "D.D", "DDD"]
	assert_eq(InteriorArt.furniture_cells(layout, "D"), [Vector2i(0, 1), Vector2i(2, 1)] as Array[Vector2i], "a door glyph in the wall rows was read as furniture")


func test_drawn_pieces_report_their_rect_in_room_space() -> void:
	var room := Node2D.new()
	var deco := Node2D.new()
	deco.position = Vector2(10, 20)
	room.add_child(deco)
	add_child_autofree(room)
	VillageProp.prop_art_override = {"shelf_goods_shop_item": {"path": "res://assets/sprites/interiors/harmonia/counter_shop_item.png"}}
	InteriorArt.place_or_paint(deco, "shelf_goods", "shop_item", Vector2(100, 200), func() -> Node: return null)
	var rects := InteriorArt.drawn_piece_rects(room)
	assert_eq(rects.size(), 1, "the one drawn piece is reported")
	if rects.size() == 1:
		assert_almost_eq(rects[0].end.y, 220.0, 0.5, "its base is the base point plus its parent's offset")
		assert_almost_eq(rects[0].get_center().x, 110.0, 0.5, "it is centred on the base point plus its parent's offset")
