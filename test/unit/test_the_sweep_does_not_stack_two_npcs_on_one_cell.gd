extends GutTest

## `InteriorPlacementSweep` relocated two of Harmonia's librarians onto the SAME cell, and one of
## them could never be spoken to.
##
## The sweep snaps an NPC off walls and furniture by ring-searching for the nearest cell that is
## walkable and outside every furniture rect. It checked those two things and not a third: whether
## another NPC is already standing there. Yorick Pell (authored 9,9) and Cantor Vell (authored 9,10)
## were both blocked, both ring-searched, and both landed on cell (10,10) — global (336,336) for
## each. The interact probe picks NEAREST BY ANCHOR, their anchors were identical, so Cantor won all
## 24 of Yorick's approach cells and Yorick's five dialogue lines were unreachable.
##
## ⚠️ NO SOURCE-LEVEL CHECK COULD HAVE FOUND IT. The two are authored one cell apart, which is legal
## and common; the collision is created at runtime by the relocator. That is the same shape as the
## Maple Heights chest that muted a quest NPC, except that pair WAS authored on one coordinate — so
## a "two nodes share a coordinate" scan over source catches that one and is blind to this one.
##
## 🔑 The unit arm is deterministic rather than a replay of the library: one clear cell in a sea of
## wall, two NPCs that both want it. The fix has to leave the second somewhere else, and the file
## prefers leaving an NPC on furniture (cosmetic) over stacking it (unreachable).

const SweepScript = preload("res://src/maps/interiors/InteriorPlacementSweep.gd")
const INTERIOR_DIR := "res://src/maps/interiors/"
const LIB := "res://src/maps/interiors/HarmoniaLibraryInterior.gd"
const BODY_RADIUS := 8.0
const FACINGS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]


func _npc_at(container: Node, cell: Vector2i) -> Node2D:
	var n := Node2D.new()
	n.name = "npc_%d_%d" % [cell.x, cell.y]
	n.position = Vector2((cell.x + 0.5) * SweepScript.TILE_SIZE, (cell.y + 0.5) * SweepScript.TILE_SIZE)
	container.add_child(n)
	return n


## One walkable cell (2,2) in a 5x5 of wall. Both NPCs are on wall and both want that cell.
func test_the_sweep_does_not_relocate_onto_an_occupied_cell() -> void:
	var layout: Array = ["WWWWW", "WWWWW", "WWFWW", "WWWWW", "WWWWW"]
	var root := Node2D.new()
	add_child_autofree(root)
	var npcs := Node2D.new()
	root.add_child(npcs)
	var a := _npc_at(npcs, Vector2i(1, 2))
	var b := _npc_at(npcs, Vector2i(3, 2))

	SweepScript.sweep(root, npcs, null, layout, "probe")

	var clear := Vector2((2 + 0.5) * SweepScript.TILE_SIZE, (2 + 0.5) * SweepScript.TILE_SIZE)
	assert_true(a.position == clear or b.position == clear,
		"CONTROL: the one clear cell must be used by one of them, or this arm proves nothing")
	assert_ne(a.position, b.position,
		"the sweep put both NPCs on the same cell (%s). Standing on a table is cosmetic; standing " % str(a.position) +
		"inside another NPC makes one of the two unreachable, because the interact probe picks " +
		"nearest-by-anchor and identical anchors never tie in the loser's favour")


## The other half: reserving a cell must not cost a relocation that was possible.
func test_a_lone_npc_still_gets_relocated() -> void:
	var layout: Array = ["WWWWW", "WWWWW", "WWFWW", "WWWWW", "WWWWW"]
	var root := Node2D.new()
	add_child_autofree(root)
	var npcs := Node2D.new()
	root.add_child(npcs)
	var a := _npc_at(npcs, Vector2i(1, 2))
	var before: Vector2 = a.position

	SweepScript.sweep(root, npcs, null, layout, "probe")

	assert_ne(a.position, before, "an NPC on a wall with a clear cell beside it must still move")
	assert_eq(a.position, Vector2((2 + 0.5) * SweepScript.TILE_SIZE, (2 + 0.5) * SweepScript.TILE_SIZE),
		"and must move to the clear cell, not somewhere else")


## A stationary NPC is standing there whether or not the sweep touched it.
func test_a_mover_does_not_land_on_a_stationary_npc() -> void:
	var layout: Array = ["WWWWW", "WWWWW", "WWFWW", "WWWWW", "WWWWW"]
	var root := Node2D.new()
	add_child_autofree(root)
	var npcs := Node2D.new()
	root.add_child(npcs)
	var parked := _npc_at(npcs, Vector2i(2, 2))   # already clear — the sweep leaves it alone
	var mover := _npc_at(npcs, Vector2i(1, 2))    # on wall, and (2,2) is its only candidate

	SweepScript.sweep(root, npcs, null, layout, "probe")

	assert_eq(parked.position, Vector2((2 + 0.5) * SweepScript.TILE_SIZE, (2 + 0.5) * SweepScript.TILE_SIZE),
		"CONTROL: the already-clear NPC must not be moved")
	assert_ne(mover.position, parked.position,
		"a relocated NPC landed on one that never moved — reserving only the cells the sweep " +
		"assigns leaves the stationary ones unprotected")


## Integration: the defect as the player meets it. No two interactables in any interior may share a
## position, because identical anchors make one of them unreachable.
func test_no_interior_puts_two_interactables_on_one_spot() -> void:
	var prior_mode7: bool = Mode7Overlay.is_active
	Mode7Overlay.is_active = false
	var stacked: Array = []
	var checked := 0
	var dir := DirAccess.open(INTERIOR_DIR)
	assert_not_null(dir, "CONTROL: the interiors directory opens")
	if dir == null:
		return
	var paths: Array = []
	dir.list_dir_begin()
	var e: String = dir.get_next()
	while e != "":
		if e.ends_with(".gd"):
			paths.append(INTERIOR_DIR + e)
		e = dir.get_next()
	dir.list_dir_end()
	paths.sort()

	for path in paths:
		var probe = load(path).new()
		if not (probe is Node2D) or not (probe as Object).has_method("spawn_player_at"):
			if probe is Node:
				(probe as Node).free()
			continue
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		vp.add_child(probe)
		await get_tree().physics_frame
		await get_tree().physics_frame

		var seen: Dictionary = {}
		var stack: Array = [probe]
		while not stack.is_empty():
			var n = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if not (n is Node2D and n.has_method("interact")):
				continue
			checked += 1
			var key: String = "%.0f,%.0f" % [(n as Node2D).global_position.x, (n as Node2D).global_position.y]
			var who: String = str(n.npc_name) if "npc_name" in n else str(n.name)
			if seen.has(key):
				stacked.append("%s: \"%s\" and \"%s\" both at %s — one of the two can never be reached" % [
					str(path).get_file(), str(seen[key]), who, key])
			else:
				seen[key] = who
		(probe as Node).queue_free()
		await get_tree().physics_frame
	Mode7Overlay.is_active = prior_mode7

	assert_gt(checked, 80,
		"CONTROL: only %d interior interactables collected — with a thin corpus the [] below is free" % checked)
	stacked.sort()
	assert_eq(stacked, [],
		"two interactables share one position: %s" % ", ".join(stacked))


## And the named case, end to end: Yorick answers a press from a cell beside him.
func test_yorick_pell_can_be_talked_to() -> void:
	var prior_mode7: bool = Mode7Overlay.is_active
	Mode7Overlay.is_active = false
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var lib = load(LIB).new()
	vp.add_child(lib)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var yorick: Node2D = null
	var stack: Array = [lib]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node2D and "npc_name" in n and str(n.npc_name) == "Yorick Pell":
			yorick = n
	assert_not_null(yorick, "PRECONDITION: the library carries Yorick Pell")
	if yorick == null:
		Mode7Overlay.is_active = prior_mode7
		return
	assert_gt((yorick.dialogue_lines as Array).size(), 0, "PRECONDITION: he has lines to say")

	var step := float(SweepScript.TILE_SIZE)
	var opens := 0
	var space := vp.world_2d.direct_space_state
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx == 0 and dy == 0:
				continue
			var feet: Vector2 = yorick.global_position + Vector2(dx * step, dy * step)
			var sq := PhysicsShapeQueryParameters2D.new()
			var circle := CircleShape2D.new()
			circle.radius = BODY_RADIUS
			sq.shape = circle
			sq.transform = Transform2D(0.0, feet)
			sq.collision_mask = 1
			if not space.intersect_shape(sq, 1).is_empty():
				continue
			for facing in FACINGS:
				for point in [feet + facing * InteractGeometry.PROBE_REACH_FLAT, feet]:
					var pq := PhysicsPointQueryParameters2D.new()
					pq.position = point
					pq.collide_with_areas = true
					pq.collide_with_bodies = false
					pq.collision_mask = 4
					var best: Node = null
					var bd := INF
					for hit in space.intersect_point(pq):
						var c = hit.get("collider")
						if c == null or not is_instance_valid(c) or not c.has_method("interact") or not (c is Node2D):
							continue
						var d: float = InteractGeometry.anchor(c).distance_squared_to(feet)
						if d < bd:
							bd = d
							best = c
					if best != null:
						if best == yorick:
							opens += 1
						break
	Mode7Overlay.is_active = prior_mode7
	assert_gt(opens, 0,
		"Yorick Pell answers no press from any standable cell within two of him — the sweep stacked " +
		"him on Cantor Vell and every approach went to Cantor")
