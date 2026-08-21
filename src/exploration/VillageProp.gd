class_name VillageProp
extends Node2D
## Y-sorted procedural prop: origin at the bottom-centre of its base cell, art drawn upward, footprint cells become a StaticBody2D on the wall layer.

enum Kind { TREE, LAMP_POST, BARREL, CRATE, STALL, FENCE, WELL, BANNER, CART, PLANTER }

const TILE := 32

## Footprint offsets from the base cell; BANNER hangs on a wall and blocks nothing
const FOOTPRINTS := {
	Kind.TREE: [Vector2i(0, 0)], Kind.LAMP_POST: [Vector2i(0, 0)], Kind.BARREL: [Vector2i(0, 0)],
	Kind.CRATE: [Vector2i(0, 0)], Kind.STALL: [Vector2i(0, 0), Vector2i(1, 0)], Kind.FENCE: [Vector2i(0, 0)],
	Kind.WELL: [Vector2i(0, 0), Vector2i(1, 0)], Kind.BANNER: [], Kind.CART: [Vector2i(0, 0), Vector2i(1, 0)],
	Kind.PLANTER: [Vector2i(0, 0)],
}
## Drawn size in tiles (w, h); the art grows UP from the base row
const SIZES := {
	Kind.TREE: Vector2i(1, 3), Kind.LAMP_POST: Vector2i(1, 2), Kind.BARREL: Vector2i(1, 1), Kind.CRATE: Vector2i(1, 1),
	Kind.STALL: Vector2i(2, 2), Kind.FENCE: Vector2i(1, 1), Kind.WELL: Vector2i(2, 2), Kind.BANNER: Vector2i(1, 2),
	Kind.CART: Vector2i(2, 2), Kind.PLANTER: Vector2i(1, 1),
}

const WOOD := Color(0.45, 0.30, 0.16)
const WOOD_LIGHT := Color(0.62, 0.44, 0.24)
const IRON := Color(0.22, 0.22, 0.26)
const LEAF := Color(0.22, 0.50, 0.20)
const LEAF_LIGHT := Color(0.36, 0.66, 0.28)
const STONE := Color(0.58, 0.56, 0.52)
const STONE_DARK := Color(0.38, 0.36, 0.34)
const CLOTH_A := Color(0.80, 0.22, 0.20)
const CLOTH_B := Color(0.92, 0.88, 0.80)
const GLASS := Color(1.0, 0.85, 0.50)

var kind: int = Kind.BARREL
## Manifest key of the world's tile sheet; "" = always procedural
var sheet_key: String = ""
## Local point a lamp should sit at (lamp posts: the glass head)
var light_anchor: Vector2 = Vector2.ZERO


static func create(k: int, base_cell: Vector2i) -> VillageProp:
	var p := VillageProp.new()
	p.kind = k
	p.name = "Prop_%s_%d_%d" % [Kind.keys()[k], base_cell.x, base_cell.y]
	p.position = Vector2((base_cell.x + 0.5) * TILE, (base_cell.y + 1) * TILE)
	return p


func footprint_cells(base_cell: Vector2i) -> Array:
	var out: Array = []
	for off in FOOTPRINTS[kind]:
		out.append(base_cell + off)
	return out


func _ready() -> void:
	var size: Vector2i = SIZES[kind]
	var img: Image = TileSheetManifest.region(sheet_key, "props", Kind.keys()[kind], size) if sheet_key != "" else null
	if img == null:
		img = Image.create(size.x * TILE, size.y * TILE, false, Image.FORMAT_RGBA8)
		_paint(img, size)
	elif kind == Kind.LAMP_POST:
		light_anchor = Vector2(0, -50.0)
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.centered = false
	spr.texture = ImageTexture.create_from_image(img)
	spr.position = Vector2(-size.x * TILE / 2.0, -size.y * TILE)
	add_child(spr)
	if not FOOTPRINTS[kind].is_empty():
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		for off in FOOTPRINTS[kind]:
			var cs := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(TILE, TILE)
			cs.shape = rect
			cs.position = Vector2(off.x * TILE, -TILE / 2.0)
			body.add_child(cs)
		add_child(body)


func _paint(img: Image, size: Vector2i) -> void:
	var w := size.x * TILE
	var h := size.y * TILE
	match kind:
		Kind.TREE:
			img.fill_rect(Rect2i(w / 2 - 3, h - 22, 6, 22), WOOD)
			_disc(img, Vector2i(w / 2, h - 44), 15, LEAF)
			_disc(img, Vector2i(w / 2 - 6, h - 56), 11, LEAF)
			_disc(img, Vector2i(w / 2 + 7, h - 58), 12, LEAF)
			_disc(img, Vector2i(w / 2 + 2, h - 68), 10, LEAF_LIGHT)
		Kind.LAMP_POST:
			img.fill_rect(Rect2i(w / 2 - 4, h - 4, 8, 4), IRON)
			img.fill_rect(Rect2i(w / 2 - 1, h - 44, 3, 40), IRON)
			img.fill_rect(Rect2i(w / 2 - 6, h - 56, 12, 12), IRON)
			img.fill_rect(Rect2i(w / 2 - 4, h - 54, 8, 8), GLASS)
			light_anchor = Vector2(0, -50.0)
		Kind.BARREL:
			img.fill_rect(Rect2i(6, 4, 20, 26), WOOD)
			img.fill_rect(Rect2i(6, 8, 20, 2), IRON)
			img.fill_rect(Rect2i(6, 22, 20, 2), IRON)
			img.fill_rect(Rect2i(10, 6, 3, 22), WOOD_LIGHT)
		Kind.CRATE:
			img.fill_rect(Rect2i(4, 6, 24, 24), WOOD)
			img.fill_rect(Rect2i(4, 6, 24, 2), WOOD_LIGHT)
			img.fill_rect(Rect2i(4, 6, 2, 24), WOOD_LIGHT)
			for i in range(24):
				img.set_pixel(4 + i, 6 + i, IRON)
		Kind.STALL:
			img.fill_rect(Rect2i(4, h - 22, w - 8, 22), WOOD)
			img.fill_rect(Rect2i(4, h - 22, w - 8, 3), WOOD_LIGHT)
			img.fill_rect(Rect2i(6, h - 44, 3, 22), WOOD)
			img.fill_rect(Rect2i(w - 9, h - 44, 3, 22), WOOD)
			for i in range(0, w, 8):
				img.fill_rect(Rect2i(i, h - 52, 8, 10), CLOTH_A if (i / 8) % 2 == 0 else CLOTH_B)
		Kind.FENCE:
			img.fill_rect(Rect2i(2, 10, 4, 22), WOOD)
			img.fill_rect(Rect2i(26, 10, 4, 22), WOOD)
			img.fill_rect(Rect2i(0, 14, 32, 3), WOOD_LIGHT)
			img.fill_rect(Rect2i(0, 24, 32, 3), WOOD_LIGHT)
		Kind.WELL:
			img.fill_rect(Rect2i(8, h - 26, w - 16, 26), STONE)
			img.fill_rect(Rect2i(8, h - 26, w - 16, 3), STONE_DARK)
			img.fill_rect(Rect2i(14, h - 20, w - 28, 14), IRON)
			img.fill_rect(Rect2i(10, h - 56, 3, 32), WOOD)
			img.fill_rect(Rect2i(w - 13, h - 56, 3, 32), WOOD)
			img.fill_rect(Rect2i(6, h - 62, w - 12, 8), WOOD_LIGHT)
		Kind.BANNER:
			img.fill_rect(Rect2i(w / 2 - 8, 2, 16, 3), WOOD)
			img.fill_rect(Rect2i(w / 2 - 6, 5, 12, 40), CLOTH_A)
			img.fill_rect(Rect2i(w / 2 - 3, 14, 6, 6), CLOTH_B)
		Kind.CART:
			img.fill_rect(Rect2i(6, h - 30, w - 12, 16), WOOD)
			img.fill_rect(Rect2i(6, h - 30, w - 12, 3), WOOD_LIGHT)
			_disc(img, Vector2i(14, h - 10), 8, IRON)
			_disc(img, Vector2i(w - 14, h - 10), 8, IRON)
			img.fill_rect(Rect2i(w - 8, h - 22, 10, 3), WOOD)
		Kind.PLANTER:
			img.fill_rect(Rect2i(4, 16, 24, 14), STONE)
			img.fill_rect(Rect2i(4, 16, 24, 2), STONE_DARK)
			_disc(img, Vector2i(10, 12), 5, LEAF)
			_disc(img, Vector2i(18, 10), 6, LEAF_LIGHT)
			_disc(img, Vector2i(24, 13), 4, CLOTH_A)


func _disc(img: Image, c: Vector2i, r: int, col: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				var px := c + Vector2i(x, y)
				if px.x >= 0 and px.y >= 0 and px.x < img.get_width() and px.y < img.get_height():
					img.set_pixel(px.x, px.y, col)
