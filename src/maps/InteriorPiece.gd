class_name InteriorPiece
extends RefCounted

## One standing piece of drawn furniture: its feet on `base`, a contact shadow on the floor layer, and (given `solid`)
## a body at its feet. With no drawn art the room's own `painter` runs exactly as before and this returns null.

const SHADOW_NAME := "Shadow"
static var _shadows: Dictionary = {}


## A painter for a piece that exists only as drawn art: a painted room simply goes without it.
static func none() -> Callable:
	return func() -> Node: return null


## Stand `kind` in `decorations`. `solid` is the footprint's size, resting on `base` unless `solid_at` places its centre.
static func stand(decorations: Node, floor_layer: Node, kind: String, room: String, base: Vector2, painter: Callable, village: String = "", solid: Vector2 = Vector2.ZERO, with_shadow: bool = true, solid_at: Vector2 = Vector2.ZERO) -> Sprite2D:
	var holder := Node2D.new()
	holder.name = "Piece_" + kind
	holder.position = base
	decorations.add_child(holder, true)
	var art := InteriorArt.place_or_paint(holder, kind, room, Vector2.ZERO, painter, village) as Sprite2D
	if art == null or art.get_parent() != holder:
		holder.queue_free()  # painted: the painter put its own nodes where it always has
		return null
	if with_shadow and floor_layer != null:
		shadow(floor_layer, base, art.texture.get_width())
	if solid != Vector2.ZERO:
		var body := StaticBody2D.new()
		body.name = "Footprint"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = solid
		shape.shape = rect
		shape.position = solid_at if solid_at != Vector2.ZERO else Vector2(0, -solid.y / 2.0)
		body.add_child(shape)
		holder.add_child(body)
	return art


## A flat piece underfoot (a mat): on the floor layer, walkable, never sorted above anyone.
static func lay(floor_layer: Node, kind: String, room: String, base: Vector2, village: String = "") -> Node:
	return InteriorArt.place_or_paint(floor_layer, kind, room, base, none(), village)


## A soft dark ellipse under a standing piece.
static func shadow(floor_layer: Node, base: Vector2, piece_width: int) -> void:
	var w: int = maxi(12, int(piece_width * 0.9))
	if not _shadows.has(w):
		var h: int = clampi(w / 5, 6, 14)
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in range(h):
			for x in range(w):
				var d: float = Vector2((x + 0.5 - w / 2.0) / (w / 2.0), (y + 0.5 - h / 2.0) / (h / 2.0)).length()
				img.set_pixel(x, y, Color(0, 0, 0, 0.32 * clampf(1.0 - d * d, 0.0, 1.0)))
		_shadows[w] = ImageTexture.create_from_image(img)
	var sh := Sprite2D.new()
	sh.name = SHADOW_NAME
	sh.texture = _shadows[w]
	sh.position = base + Vector2(0, -2)
	floor_layer.add_child(sh, true)
