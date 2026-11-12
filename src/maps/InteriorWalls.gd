class_name InteriorWalls
extends RefCounted

## A room's walls, as something the player cannot walk through. Measured 2026-11-12 (cowir-overworld, .793): no
## interior had ANY collision but the inn's hearth, so the player walked through every wall and out of the picture;
## only the camera stopped at the room's edge. One builder, from the layout string every room already authors:
## its 'W' cells, the furniture glyphs the room names, and a ring outside the map, minus the cells its doors open.

const TILE: int = 32
const BODY_NAME := "RoomWalls"
const BODY_CLEARANCE: float = 8.0
const NEIGHBOURS: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## Every solid cell: walls, the named furniture glyphs (never on the outer rows, where a glyph is a door), and one
## ring of cells outside the layout so a door cell leads nowhere but its trigger. A cell an `open_rects` rect
## touches (a door's trigger, where the player stands) stays open.
static func solid_cells(layout: Array, glyphs: String = "", open_rects: Array = []) -> Dictionary:
	var out := {}
	var h: int = layout.size()
	var w: int = 0
	for row in layout:
		w = maxi(w, str(row).length())
	for y in h:
		var row: String = str(layout[y])
		for x in w:
			if x >= row.length() or row[x] == "W":
				out[Vector2i(x, y)] = true
	if glyphs != "":
		for c in InteriorArt.furniture_cells(layout, glyphs):
			out[c] = true
	for c in out.keys():
		var cell_rect := Rect2(Vector2(c) * TILE, Vector2(TILE, TILE)).grow(-2.0)
		for r in open_rects:
			if (r as Rect2).intersects(cell_rect):
				out.erase(c)
				break
	for x in range(-1, w + 1):
		out[Vector2i(x, -1)] = true
		out[Vector2i(x, h)] = true
	for y in range(-1, h + 1):
		out[Vector2i(-1, y)] = true
		out[Vector2i(w, y)] = true
	return out


## The cells a walker starting at `from` can reach without entering a solid one.
static func reach(solid: Dictionary, from: Vector2i, limit: int = 4000) -> Dictionary:
	var seen := {}
	if solid.has(from):
		return seen
	seen[from] = true
	var queue: Array = [from]
	while not queue.is_empty() and seen.size() < limit:
		var c: Vector2i = queue.pop_front()
		for d in NEIGHBOURS:
			var n: Vector2i = c + d
			if not solid.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


## Each door trigger's box in the room's own space (the Area2Ds under the room's `transitions`).
static func door_rects(room: Node) -> Array:
	var out: Array = []
	var holder = room.get("transitions")
	if holder == null or not is_instance_valid(holder):
		return out
	for area in holder.get_children():
		if not (area is Area2D):
			continue
		for cs in area.get_children():
			if not (cs is CollisionShape2D) or (cs as CollisionShape2D).shape == null:
				continue
			var at: Vector2 = (area as Area2D).position + (cs as CollisionShape2D).position
			var shape: Shape2D = (cs as CollisionShape2D).shape
			if shape is RectangleShape2D:
				out.append(Rect2(at - (shape as RectangleShape2D).size / 2.0, (shape as RectangleShape2D).size))
			elif shape is CircleShape2D:
				var r: float = (shape as CircleShape2D).radius
				out.append(Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0))
	return out


## The room a standing player needs: the body's radius plus the solver's safe margin, as the spawn guard measures it.
static func _body_rect(at: Vector2) -> Rect2:
	return Rect2(at - Vector2(BODY_CLEARANCE, BODY_CLEARANCE), Vector2(BODY_CLEARANCE, BODY_CLEARANCE) * 2.0)


## Build the room's wall body. Call it once the doors and the player exist: the cell the player starts in and the
## cells a door's trigger covers are left open, and so is every cell a NAMED spawn's body touches (GameLoop places
## the player at one after _ready, and some sit on a cell corner beside a desk, counter, bar or piano).
static func build(room: Node2D, layout: Array, glyphs: String = "") -> StaticBody2D:
	var open: Array = door_rects(room)
	var player = room.get("player")
	if player != null and is_instance_valid(player) and player is Node2D:
		open.append(_body_rect((player as Node2D).position))
	var spawns = room.get("spawn_points")
	if spawns is Dictionary:
		for v in (spawns as Dictionary).values():
			if v is Vector2:
				open.append(_body_rect((v as Vector2) * TILE))
	var solid := solid_cells(layout, glyphs, open)
	var body := StaticBody2D.new()
	body.name = BODY_NAME
	body.collision_layer = 1
	body.collision_mask = 0
	# One rectangle per horizontal run of solid cells.
	var rows := {}
	for c in solid:
		if not rows.has(c.y):
			rows[c.y] = []
		(rows[c.y] as Array).append(c.x)
	for y in rows:
		var xs: Array = rows[y]
		xs.sort()
		var start: int = xs[0]
		var prev: int = xs[0]
		for i in range(1, xs.size() + 1):
			if i < xs.size() and int(xs[i]) == prev + 1:
				prev = xs[i]
				continue
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2((prev - start + 1) * TILE, TILE)
			shape.shape = rect
			shape.position = Vector2((start + prev + 1) * TILE / 2.0, (int(y) + 0.5) * TILE)
			body.add_child(shape)
			if i < xs.size():
				start = xs[i]
				prev = xs[i]
	body.set_meta("solid_cells", solid)
	room.add_child(body)
	return body
