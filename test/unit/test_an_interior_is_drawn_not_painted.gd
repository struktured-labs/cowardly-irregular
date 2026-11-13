extends GutTest

## struktured 2026-11-01: "the inside of village houses and shops need a major sprite rework". The seam: prop_art
## "<kind>_<room>_<village>" -> "<kind>_<room>" -> "<kind>_<world>" -> "<kind>"; a tile entry may be a PATTERN (any multiple
## of 32px, sampled by x mod cols, y mod rows); no entry keeps the room's own painter.

const ShopInteriorScript := preload("res://src/maps/interiors/ShopInterior.gd")
## Two committed PNGs with different sizes stand in for drawn art.
const ART_A := "res://assets/sprites/buildings/medieval/harmonia_library.png"
const ART_B := "res://assets/sprites/buildings/medieval/harmonia_arms.png"


func after_each() -> void:
	VillageProp.prop_art_override = null


func test_the_most_specific_drawing_wins() -> void:
	VillageProp.prop_art_override = {"counter_shop_item_harmonia": {"path": ART_A}, "counter_shop_item": {"path": ART_B}, "counter": {"path": ART_B}}
	assert_eq(InteriorArt.path("counter", "shop_item", "harmonia"), ART_A, "the village's own counter lost")
	assert_eq(InteriorArt.path("counter", "shop_item", "frosthold"), ART_B, "another village did not fall back to the room's counter")
	assert_eq(InteriorArt.path("shelf", "shop_item", "harmonia"), "", "a kind with no entry found art")
	VillageProp.prop_art_override = {"floor": {"path": "res://assets/sprites/props/no_such_floor.png"}}
	assert_eq(InteriorArt.path("floor", "inn"), "", "a missing file was handed out as art")


func test_a_tile_is_drawn_when_there_is_art_and_painted_when_not() -> void:
	var painted := [false]
	var painter := func(img: Image) -> void:
		painted[0] = true
		img.fill(Color.MAGENTA)
	VillageProp.prop_art_override = {}
	var img := InteriorArt.tile("floor", "inn", painter)
	assert_true(painted[0], "CONTROL: with no art the room's painter ran")
	assert_eq(img.get_pixel(5, 5), Color.MAGENTA, "the painted tile is not the painter's")
	painted[0] = false
	VillageProp.prop_art_override = {"floor_inn": {"path": ART_A}}
	var drawn := InteriorArt.tile("floor", "inn", painter)
	assert_false(painted[0], "the painter ran although the floor is drawn")
	var src := (load(ART_A) as Texture2D).get_image()
	assert_eq(drawn.get_size(), Vector2i(src.get_width() / 32, src.get_height() / 32) * 32, "the drawn tile was not trimmed to whole 32px cells")
	assert_eq(drawn.get_pixel(40, 40), src.get_pixel(40, 40), "the drawn tile is not the art's pixels")


func test_a_pattern_repeats_every_cols_by_rows() -> void:
	var img := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	var src := InteriorArt.source(img)
	assert_eq(src.get_atlas_grid_size(), Vector2i(4, 2), "a 128x64 pattern is not a 4x2 grid of cells")
	assert_eq(InteriorArt.cell(src, Vector2i(5, 3)), Vector2i(1, 1), "cell (5,3) did not wrap to (1,1)")
	var one := InteriorArt.source(Image.create(32, 32, false, Image.FORMAT_RGBA8))
	assert_eq(InteriorArt.cell(one, Vector2i(9, 7)), Vector2i.ZERO, "a single-cell tile does not stay at (0,0)")


func test_furniture_stands_on_its_base_when_drawn_and_is_built_when_not() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	var built := [0]
	var painter := func() -> Node:
		built[0] += 1
		var n := Node2D.new()
		parent.add_child(n)
		return n
	VillageProp.prop_art_override = {}
	InteriorArt.place_or_paint(parent, "shelf_goods", "shop_item", Vector2(100, 200), painter)
	assert_eq(built[0], 1, "CONTROL: with no art the builder ran")
	VillageProp.prop_art_override = {"shelf_goods_shop_item": {"path": ART_A}}
	var spr := InteriorArt.place_or_paint(parent, "shelf_goods", "shop_item", Vector2(100, 200), painter) as Sprite2D
	assert_eq(built[0], 1, "the builder ran although the furniture is drawn")
	assert_not_null(spr, "no drawn sprite was placed")
	var r: Rect2 = spr.get_rect() if spr else Rect2()
	r.position += spr.position if spr else Vector2.ZERO
	assert_almost_eq(r.end.y, 200.0, 0.5, "the drawn piece does not stand on its base")
	assert_almost_eq(r.get_center().x, 100.0, 0.5, "the drawn piece is not centred on its base")


func _shop(planted: Dictionary) -> Node:
	VillageProp.prop_art_override = planted
	var shop = ShopInteriorScript.new()
	shop.shop_type = ShopInteriorScript.ShopType.ITEM
	add_child_autofree(shop)
	return shop


func _art_nodes(n: Node, kind: String) -> int:
	var c := 1 if str(n.name).begins_with("Art_" + kind) else 0
	for ch in n.get_children():
		c += _art_nodes(ch, kind)
	return c


func test_the_shop_reads_its_counter_tile_and_shelf_goods() -> void:
	var plain := _shop({})
	assert_eq(_art_nodes(plain, "shelf_goods"), 0, "CONTROL: a shop with no art grew drawn shelves")
	var shop := _shop({"counter_shop_item": {"path": ART_A}, "shelf_goods_shop_item": {"path": ART_B}})
	assert_eq(shop.art_room(), "shop_item", "the item shop does not name its room")
	assert_eq(_art_nodes(shop, "shelf_goods"), 4, "the four shelf rows did not draw their stock")
	var src := shop.tilemap.tile_set.get_source(2) as TileSetAtlasSource
	var art := (load(ART_A) as Texture2D).get_image()
	assert_eq(src.texture.get_image().get_pixel(40, 40), art.get_pixel(40, 40), "the counter tile is not the drawn counter")


func test_every_interior_key_names_a_real_kind_and_room() -> void:
	assert_true(InteriorArt.accepts_key("floor_inn"), "a room floor key was refused")
	assert_true(InteriorArt.accepts_key("counter_shop_item_harmonia"), "a village variant was refused")
	assert_true(InteriorArt.accepts_key("wall_harmonia_library"), "a BaseInterior room's own key was refused")
	assert_false(InteriorArt.accepts_key("floor_nowhere"), "a key no room asks for was accepted")
	assert_false(InteriorArt.accepts_key("throne_inn"), "a kind no room wires was accepted")


func test_a_back_wall_strip_stands_on_the_top_wall_row_across_the_room() -> void:
	var plain := _shop({})
	assert_eq(_art_nodes(plain, "back_wall"), 0, "CONTROL: a shop with no back wall art grew one")
	var shop := _shop({"back_wall_shop_item": {"path": ART_A}})
	assert_eq(_art_nodes(shop, "back_wall"), 1, "the shop did not stand its back wall")
	var spr: Sprite2D = shop.find_child("Art_back_wall", true, false)
	var r: Rect2 = spr.get_rect()
	r.position += spr.position
	assert_almost_eq(r.end.y, float(InteriorArt.TILE), 0.5, "the back wall does not stand on the top wall row's base")
	assert_almost_eq(r.get_center().x, ShopInteriorScript.MAP_WIDTH * InteriorArt.TILE / 2.0, 0.5, "the back wall is not centred on the room")


func test_each_shelf_row_of_stock_is_centred_on_its_shelf() -> void:
	## cowir-sprites 21175: the left goods sat at 2.5 tiles while the left shelf spans cols 2-4.
	var centres: Array = ShopInteriorScript.shelf_centres()
	assert_eq(centres.size(), 2, "CONTROL: the layout has two shelf runs per row")
	assert_almost_eq(float(centres[0]), 3.5 * InteriorArt.TILE, 0.5, "the left stock is not on the left shelf's centre")
	assert_almost_eq(float(centres[1]), 12.5 * InteriorArt.TILE, 0.5, "the right stock is not on the right shelf's centre")
	var shop := _shop({"shelf_goods_shop_item": {"path": ART_B}})
	var xs: Array = []
	for n in shop.find_children("Art_shelf_goods*", "", true, false):
		var spr := n as Sprite2D
		xs.append(spr.position.x + spr.texture.get_width() / 2.0)
	xs.sort()
	assert_eq(xs.size(), 4, "CONTROL: four drawn stock rows")
	assert_almost_eq(float(xs[0]), 3.5 * InteriorArt.TILE, 0.5, "drawn stock on the left is off its shelf")


func test_the_tavern_reads_its_floor_wall_and_hearth_tiles() -> void:
	VillageProp.prop_art_override = {}
	var plain := TavernInterior.new()
	add_child_autofree(plain)
	var plain_floor := plain.tilemap.tile_set.get_source(0) as TileSetAtlasSource
	assert_eq(plain_floor.get_atlas_grid_size(), Vector2i.ONE, "CONTROL: an undrawn tavern floor is one painted cell")
	VillageProp.prop_art_override = {"floor_tavern": {"path": ART_A}, "wall_tavern": {"path": ART_B}, "hearth_tavern": {"path": ART_A}}
	var tav := TavernInterior.new()
	add_child_autofree(tav)
	for pair in [[0, ART_A], [1, ART_B], [4, ART_A]]:
		var src := tav.tilemap.tile_set.get_source(pair[0]) as TileSetAtlasSource
		var art := (load(pair[1]) as Texture2D).get_image()
		assert_eq(src.texture.get_image().get_pixel(40, 40), art.get_pixel(40, 40), "tavern source %d is not the drawn tile" % pair[0])
	var floor_src := tav.tilemap.tile_set.get_source(0) as TileSetAtlasSource
	var off_origin := 0
	var wrong := 0
	for at in tav.tilemap.get_used_cells_by_id(0):
		var got := tav.tilemap.get_cell_atlas_coords(at)
		off_origin += 1 if got != Vector2i.ZERO else 0
		wrong += 1 if got != InteriorArt.cell(floor_src, at) else 0
	assert_gt(off_origin, 0, "the drawn floor pattern was stamped at one cell instead of repeating across the room")
	assert_eq(wrong, 0, "%d floor cells do not sample the pattern by their position" % wrong)


func test_a_drawn_tavern_back_wall_replaces_the_painted_wall_art() -> void:
	var wall_art := ["WallBanner", "WallPainting", "Dartboard", "CopperPots"]
	VillageProp.prop_art_override = {}
	var plain := TavernInterior.new()
	add_child_autofree(plain)
	assert_eq(_art_nodes(plain, "back_wall"), 0, "CONTROL: a tavern with no back wall art grew one")
	for n in wall_art:
		assert_not_null(plain.decorations.get_node_or_null(n), "CONTROL: the painted tavern hangs its %s" % n)
	assert_eq(plain.camera.limit_top, 0, "CONTROL: a painted tavern's camera stops at the map's edge")
	VillageProp.prop_art_override = {"back_wall_tavern": {"path": ART_A}}
	var tav := TavernInterior.new()
	add_child_autofree(tav)
	assert_eq(_art_nodes(tav, "back_wall"), 1, "the tavern did not stand its back wall")
	var spr: Sprite2D = tav.find_child("Art_back_wall", true, false)
	var r: Rect2 = spr.get_rect() if spr else Rect2()
	r.position += spr.position if spr else Vector2.ZERO
	assert_almost_eq(r.end.y, float(InteriorArt.TILE), 0.5, "the back wall does not stand on the top wall row's base")
	assert_almost_eq(r.get_center().x, TavernInterior.MAP_WIDTH * InteriorArt.TILE / 2.0, 0.5, "the back wall is not centred on the room")
	for n in wall_art:
		assert_null(tav.decorations.get_node_or_null(n), "the painted %s still hangs over the drawn back wall" % n)
	assert_gt(tav.decorations.get_child_count(), 0, "the drawn back wall took the rest of the room with it")
	assert_eq(tav.camera.limit_top, -InteriorArt.TILE, "the camera cannot show the part of the wall above the map")
