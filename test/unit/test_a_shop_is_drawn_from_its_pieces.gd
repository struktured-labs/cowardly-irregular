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


## The layout cell a block starts at: its glyph is there, and not to its left nor above it.
func _is_block_top_left(layout: Array, cell: Vector2i, glyph: String) -> bool:
	var row: String = layout[cell.y]
	if row[cell.x] != glyph:
		return false
	var left := cell.x > 0 and row[cell.x - 1] == glyph
	var above := cell.y > 0 and str(layout[cell.y - 1])[cell.x] == glyph
	return not left and not above


func test_each_drawn_pattern_was_rolled_for_where_the_room_puts_it() -> void:
	## A counter or shelf pattern is ROLLED so its piece lands whole at the block it was cut for (the seam samples
	## x mod cols, y mod rows). Its manifest entry names those blocks; if the layout moves a block, the art is mis-rolled.
	## (A seam-roughness oracle was tried first and measured unable to tell right from wrong on these busy pieces.)
	var sec: Dictionary = VillageProp._prop_art_section()
	var glyphs := {"counter": "C", "shelf": "S"}
	var checked := 0
	for type in ROOMS:
		for kind in glyphs:
			var e: Dictionary = sec.get("%s_%s_harmonia" % [kind, ROOMS[type]], {})
			var cells: Array = e.get("drawn_for", [])
			assert_gt(cells.size(), 0, "%s %s names no layout block it was rolled for" % [ROOMS[type], kind])
			for c in cells:
				var cell := Vector2i(int(c[0]), int(c[1]))
				assert_true(_is_block_top_left(ShopInteriorScript.SHOP_LAYOUT, cell, glyphs[kind]), "%s %s was rolled for a block at %s that SHOP_LAYOUT no longer starts there" % [ROOMS[type], kind, cell])
				checked += 1
	assert_gte(checked, 10, "FLOOR: counters and shelves across both shops (checked %d)" % checked)
