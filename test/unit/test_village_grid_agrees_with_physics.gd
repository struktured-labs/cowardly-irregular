extends GutTest

## THE CLASS OF BUG, not one instance of it. struktured 2026-09-06: "collision detection is
## better than ever but still not spot on, its prob better in mode 7 than in villagds though
## irioncally". The first cause found was VillageProp: art and collision were built from two
## separate expressions of one footprint and disagreed by half a tile for 2-wide props.
##
## That is a SHAPE, and villages are full of it. A village decides "solid" twice:
##   GRID    _is_cell_walkable -- tile has no collision polygon, no derived cliff face,
##           no prop footprint. Used for NPC spawns, wanderer paths, quest placement.
##   PHYSICS what a CharacterBody2D actually hits during move_and_slide. What the PLAYER feels.
## Nothing forces those to agree. Every place they disagree is either a spot the player walks
## through something solid, or bumps something that is not there -- and both read to him as
## "collision is off", never as "two subsystems hold different opinions".
##
## WHY A BODY QUERY AND NOT A CELL LOOKUP: the same reason test_overworld_spawn_overlap
## gives -- a body has radius and margin, so "the cell is open" and "the body fits" are
## different claims. This asks the physics server the question the player's body asks.
##
## SCOPE, stated because a green here is narrower than it looks: this samples the elevated
## villages (the ones with derived cliff faces, which is the new machinery) and compares the
## two authorities cell by cell. It does NOT prove the art matches either of them -- that is
## test_village_prop_art_matches_collision's job, and the prop bug passed this check.

const PLAYER_RADIUS := 4.0
const SAFE_RADIUS := 8.0
const PLAYER_MASK := 1

const VILLAGES := {
	"harmonia": "res://src/maps/villages/HarmoniaVillage.gd",
	"grimhollow": "res://src/maps/villages/GrimhollowVillage.gd",
	"frosthold": "res://src/maps/villages/FrostholdVillage.gd",
}


func _build(path: String) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var v = load(path).new()
	vp.add_child(v)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return {"village": v, "viewport": vp}


func _body_blocked(space: PhysicsDirectSpaceState2D, pos: Vector2, radius: float) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	q.shape = shape
	q.transform = Transform2D(0.0, pos)
	q.collision_mask = PLAYER_MASK
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return not space.intersect_shape(q, 1).is_empty()


func test_the_placement_grid_and_the_physics_world_agree_about_solid() -> void:
	var report: Array = []
	var villages_measured := 0
	var cells_sampled := 0

	for name in VILLAGES:
		var built: Dictionary = await _build(VILLAGES[name])
		var v = built["village"]
		if v == null or v.tile_map == null:
			continue
		var space: PhysicsDirectSpaceState2D = built["viewport"].world_2d.direct_space_state
		var ts: int = int(v.TILE_SIZE)
		var walk_but_blocked: Array = []
		var solid_but_free: Array = []
		var used: Array = v.tile_map.get_used_cells()
		if used.is_empty():
			continue
		villages_measured += 1

		for cell in used:
			cells_sampled += 1
			var centre := Vector2(cell.x * ts + ts / 2.0, cell.y * ts + ts / 2.0)
			var grid_walkable: bool = v._is_cell_walkable(cell)
			# The player's own clearance, matching the shipped solver.
			var phys_blocked: bool = _body_blocked(space, centre, PLAYER_RADIUS)
			if grid_walkable and phys_blocked:
				walk_but_blocked.append(cell)
			elif not grid_walkable and not phys_blocked:
				solid_but_free.append(cell)

		if not walk_but_blocked.is_empty():
			report.append("%s: %d cells the GRID calls walkable that the player's body cannot enter %s"
				% [name, walk_but_blocked.size(), str(walk_but_blocked.slice(0, 6))])
		if not solid_but_free.is_empty():
			report.append("%s: %d cells the GRID calls solid that the player walks straight through %s"
				% [name, solid_but_free.size(), str(solid_but_free.slice(0, 6))])

	# CONTROLS. Without these an empty sweep reports perfect agreement.
	assert_gt(villages_measured, 1, "only %d villages built -- the probe is not instantiating them" % villages_measured)
	assert_gt(cells_sampled, 500, "only %d cells sampled -- the maps did not paint" % cells_sampled)

	assert_eq(report, [],
		"the two authorities disagree; every one of these is a place he feels bad collision:\n  %s"
			% "\n  ".join(report))
