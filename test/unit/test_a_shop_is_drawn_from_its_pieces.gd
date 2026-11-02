extends GutTest

## struktured 2026-11-01: "the inside of village houses and shops need a major sprite rework". Harmonia's item shop and
## smithy are drawn from pieces cut and drawn off the approved style tiles; each piece must land WHOLE on the cells the room
## samples it by (x mod cols, y mod rows), and a drawn shelf carries its own stock.

const ShopInteriorScript := preload("res://src/maps/interiors/ShopInterior.gd")
const KINDS := ["floor", "wall", "counter", "shelf", "back_wall"]
const ROOMS := {ShopInteriorScript.ShopType.ITEM: "shop_item", ShopInteriorScript.ShopType.BLACKSMITH: "shop_blacksmith"}

func after_each() -> void:
	VillageProp.prop_art_override = null


func _shop(type: int) -> Node:
	var shop = ShopInteriorScript.new()
	shop.shop_type = type
	add_child_autofree(shop)
	return shop


func _painted_goods(shop: Node) -> int:
	var n := 0
	for c in shop.decorations.get_children():
		if c is Sprite2D and (c as Sprite2D).texture is ImageTexture and (c as Sprite2D).texture.get_size() == Vector2(96, 20):
			n += 1
	return n


func test_a_drawn_shelf_carries_its_own_stock() -> void:
	VillageProp.prop_art_override = {}
	assert_eq(_painted_goods(_shop(ShopInteriorScript.ShopType.ITEM)), 4, "CONTROL: a painted shop paints its four goods rows")
	VillageProp.prop_art_override = {"shelf_shop_item": {"path": "res://assets/sprites/interiors/harmonia/shelf_shop_item.png"}}
	assert_eq(_painted_goods(_shop(ShopInteriorScript.ShopType.ITEM)), 0, "painted goods were drawn over a drawn, stocked shelf")


func test_harmonia_shops_resolve_every_piece_to_harmonia_art() -> void:
	for type in ROOMS:
		for kind in KINDS:
			var p := InteriorArt.path(kind, ROOMS[type], "harmonia")
			assert_eq(p, "res://assets/sprites/interiors/harmonia/%s_%s.png" % [kind, ROOMS[type]], "%s %s is not drawn" % [ROOMS[type], kind])
		assert_eq(InteriorArt.path("counter", ROOMS[type], "frosthold"), "", "another village was handed Harmonia's %s counter" % ROOMS[type])


## Sum of colour jumps across the internal 32px cell boundaries of a cols x rows block, assembled cell by cell.
func _seam_cost(src: Image, origin: Vector2i, size: Vector2i, grid: Vector2i) -> float:
	var img := Image.create(size.x * 32, size.y * 32, false, Image.FORMAT_RGBA8)
	## blit_rect needs matching formats and copies NOTHING otherwise, which reads as zero seams on every sampling.
	src = src.duplicate()
	src.convert(Image.FORMAT_RGBA8)
	for y in range(size.y):
		for x in range(size.x):
			var c := Vector2i(posmod(origin.x + x, grid.x), posmod(origin.y + y, grid.y))
			img.blit_rect(src, Rect2i(c * 32, Vector2i(32, 32)), Vector2i(x, y) * 32)
	var cost := 0.0
	for bx in range(1, size.x):
		for py in range(img.get_height()):
			var a := img.get_pixel(bx * 32 - 1, py)
			var b := img.get_pixel(bx * 32, py)
			cost += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	for by in range(1, size.y):
		for px in range(img.get_width()):
			var a := img.get_pixel(px, by * 32 - 1)
			var b := img.get_pixel(px, by * 32)
			cost += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	return cost


func test_the_counter_and_shelves_land_whole_where_the_room_samples_them() -> void:
	for type in ROOMS:
		## The room's own drawn pieces, planted at room level: a test has no village origin to resolve "_harmonia" by.
		var room: String = ROOMS[type]
		VillageProp.prop_art_override = {
			"counter_" + room: {"path": "res://assets/sprites/interiors/harmonia/counter_%s.png" % room},
			"shelf_" + room: {"path": "res://assets/sprites/interiors/harmonia/shelf_%s.png" % room}}
		var shop := _shop(type)
		## Where each piece stands in ShopInterior.SHOP_LAYOUT: (origin cell, size in cells, source id).
		for piece in [[Vector2i(7, 3), Vector2i(3, 2), 2], [Vector2i(2, 2), Vector2i(3, 3), 3], [Vector2i(11, 6), Vector2i(3, 2), 3]]:
			var src := shop.tilemap.tile_set.get_source(piece[2]) as TileSetAtlasSource
			var img := src.texture.get_image()
			var grid := src.get_atlas_grid_size()
			assert_gt(grid.x * grid.y, 1, "CONTROL: %s source %d is a pattern, not one painted cell" % [ROOMS[type], piece[2]])
			var as_sampled := InteriorArt.cell_in(shop.tilemap, piece[2], piece[0])
			var whole := _seam_cost(img, as_sampled, piece[1], grid)
			## Each axis the piece was rolled on is judged against the same sampling NOT rolled on it.
			var controls: Array = []
			if as_sampled.x != 0:
				controls.append(Vector2i(0, as_sampled.y))
			if as_sampled.y != 0 and piece[1].y == grid.y:
				controls.append(Vector2i(as_sampled.x, 0))
			assert_gt(controls.size(), 0, "CONTROL: %s piece at %s has a rolled axis to judge" % [ROOMS[type], piece[0]])
			for c in controls:
				var unrolled := _seam_cost(img, c, piece[1], grid)
				assert_lt(whole, unrolled * 0.8, "%s: the piece at %s does not land whole (seams %.0f vs %.0f sampled from %s)" % [ROOMS[type], piece[0], whole, unrolled, c])
