class_name InteriorPlacementSweep
extends RefCounted

## Interior NPC-vs-furniture collision sweep (struktured msg 2764 item 3:
## "characters are standing on tables... a general purpose algorithm").
##
## Callable from both BaseInterior-descended scenes AND the three legacy
## interiors that still extend Node2D directly (InnInterior, ShopInterior,
## TavernInterior). Sweeps a container of NPCs and snaps each off:
##   (a) impassable tile cells (identified by 'W' in the authored layout —
##       interiors' inline TileSets have no physics_layer, unlike villages);
##   (b) furniture footprints (Sprite2D children of a `decorations` node
##       whose visible texture is at least MIN_FURNITURE_SIZE_PX square).
##
## Emits push_warning on each relocation so authored offenders surface
## during suite runs; the ratchet in test_interior_furniture_collision
## _regression pins the invariant.

const TILE_SIZE: int = 32

## Sprites below this size in either axis stay decorative. 24 px = 3/4 of
## a tile; bells, quills, and other tiny decor don't block NPCs.
const MIN_FURNITURE_SIZE_PX: int = 24


## Entry point. Callers pass their npcs container, decorations container,
## the authored layout, and an area_id for diagnostic messages. The
## `scene_root` is the local origin used to derive furniture rects in the
## same coordinate space as the NPCs — pass the interior scene itself
## (self), not a child container.
static func sweep(scene_root: Node, npcs: Node, decorations: Node, layout: Array, area_id: String) -> void:
	if npcs == null:
		return
	var furniture := _collect_furniture_rects(scene_root, decorations)
	for n in npcs.get_children():
		if not (n is Node2D):
			continue
		var origin: Vector2 = (n as Node2D).position
		var fixed := _find_clear_near(origin, layout, furniture)
		if fixed != origin:
			push_warning("[%s] relocated '%s' off wall/furniture %s -> %s" % [
				area_id, n.name, origin, fixed])
			(n as Node2D).position = fixed


static func _collect_furniture_rects(scene_root: Node, decorations: Node) -> Array:
	var rects: Array = []
	if decorations != null:
		_walk_sprites_for_furniture(scene_root, decorations, rects)
	return rects


static func _walk_sprites_for_furniture(scene_root: Node, node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Sprite2D:
			var sp: Sprite2D = child
			if sp.texture != null and sp.visible:
				var raw: Vector2 = sp.texture.get_size()
				var size: Vector2 = raw * sp.scale
				if size.x >= MIN_FURNITURE_SIZE_PX and size.y >= MIN_FURNITURE_SIZE_PX:
					# Walk up the parent chain so composite furniture
					# (Node2D wrapper around several sprites) contributes
					# each sub-sprite at its scene-root origin.
					var world_pos: Vector2 = sp.position
					var p: Node = sp.get_parent()
					while p != null and p != scene_root:
						if p is Node2D:
							world_pos += (p as Node2D).position
						p = p.get_parent()
					var top_left: Vector2 = world_pos - (size * 0.5 if sp.centered else Vector2.ZERO)
					out.append(Rect2(top_left, size))
		_walk_sprites_for_furniture(scene_root, child, out)


## Walkability from the authored layout string. Legacy interiors +
## BaseInterior both write 'W' for walls; anything else is floor.
static func _is_cell_walkable(cell: Vector2i, layout: Array) -> bool:
	if cell.y < 0 or cell.y >= layout.size():
		return false
	var row: String = str(layout[cell.y])
	if cell.x < 0 or cell.x >= row.length():
		return false
	return row[cell.x] != "W"


## NPC sprites are ~32×48 with the origin near the sprite's chest. The
## visual base ("feet") sits well below the origin, and struktured's
## Dorian repro (msg 2769) is a sprite whose CENTER point is above the
## table but whose base clips into it. Probe a small footprint rect
## centered on the sprite base, not a bare point.
const NPC_FOOT_HALF_W: float = 8.0
const NPC_FOOT_TOP_OFFSET: float = 4.0
const NPC_FOOT_BOTTOM_OFFSET: float = 22.0


static func _npc_footprint(pos: Vector2) -> Rect2:
	return Rect2(
		Vector2(pos.x - NPC_FOOT_HALF_W, pos.y + NPC_FOOT_TOP_OFFSET),
		Vector2(NPC_FOOT_HALF_W * 2.0, NPC_FOOT_BOTTOM_OFFSET - NPC_FOOT_TOP_OFFSET))


static func _is_position_clear(pos: Vector2, layout: Array, furniture: Array) -> bool:
	var cell := Vector2i(int(floor(pos.x / TILE_SIZE)), int(floor(pos.y / TILE_SIZE)))
	if not _is_cell_walkable(cell, layout):
		return false
	var foot := _npc_footprint(pos)
	for r in furniture:
		if (r as Rect2).intersects(foot):
			return false
	return true


## Ring-search up to 8 tiles for the nearest cell that's both walkable
## and outside every furniture rect.
static func _find_clear_near(pos: Vector2, layout: Array, furniture: Array) -> Vector2:
	if _is_position_clear(pos, layout, furniture):
		return pos
	var start := Vector2i(int(floor(pos.x / TILE_SIZE)), int(floor(pos.y / TILE_SIZE)))
	for radius in range(1, 9):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var c := start + Vector2i(dx, dy)
				var probe := Vector2((c.x + 0.5) * TILE_SIZE, (c.y + 0.5) * TILE_SIZE)
				if _is_position_clear(probe, layout, furniture):
					return probe
	return pos
