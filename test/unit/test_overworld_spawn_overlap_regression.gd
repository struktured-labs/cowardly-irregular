extends GutTest

## No overworld spawn point may place the player inside a collider.
##
## Found 2026-08-08 reproducing struktured's "got stuck after teleporting to some
## overworlds" report. 15 of 59 authored spawns across 5 of 6 overworlds put the player
## body inside solid geometry on arrival.
##
## THE MECHANISM. `Mode7Overlay.apply_terrain_collision_alignment` duplicates the tilemap,
## shifts the copy down by `MODE7_GROUND_DISPLACEMENT_PX` (140.6) and disables collision on
## the authored layer. So a body at row R meets whatever was authored at row R - 4.39.
## Asked to name what it hit, physics said `TileMapCollision` — the displaced duplicate —
## for 14 of the 15. The 15th was Abstract, which has no displaced layer at all and whose
## spawn simply sat on a solid tile. In 12 of 12 cases where the two frames disagreed, the
## spawn's own cell was open and the cell 4.39 rows above it was solid.
##
## WHY THIS IS A BODY QUERY AND NOT A GRID CHECK. 140.6 = 4x32 + 12.6, so the displacement
## is not a whole number of tiles: every tile-centre spawn lands 3.4px into its displaced
## cell, and the body's radius is 4.0. Every spawn in the game therefore already reaches
## into the row above its own — it only becomes an overlap when that row is solid.
## `node_prime_entrance` was exactly that case: both cells open, body straddling the
## boundary, overlapping anyway. No cell model can see it. Four grid models were tried
## against this question over one evening and all four were wrong; the physics query has no
## grid parameter to get wrong.
##
## THE RADIUS IS radius + safe_margin, NOT AN ARBITRARY CUSHION. `OverworldPlayer` sets
## `safe_margin = 4.0` (50x Godot's default) on top of its 4.0 radius, so 8.0 is the
## clearance the shipped solver actually requires. Measured: a query margin of 4.0 adds
## zero overlaps to a margin-free one, and a control at margin 30.0 adds 13 — so the knob
## works and the zero is a real absence, not an inert parameter.

const PLAYER_RADIUS := 4.0
## OverworldPlayer:257 radius + :232 safe_margin — the shipped solver's real clearance.
const SAFE_RADIUS := 8.0
const PLAYER_MASK := 1
const EXPLORATION_DIR := "res://src/exploration"
const NOT_MAPS := ["OverworldNPC.gd", "OverworldPlayer.gd", "OverworldController.gd", "OverworldMinimap.gd"]


func _map_paths() -> Array:
	var out: Array = []
	var dir := DirAccess.open(EXPLORATION_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd") and f.contains("Overworld") and not f in NOT_MAPS:
			out.append(EXPLORATION_DIR + "/" + f)
	out.sort()
	return out


func _isolated_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	return vp


func _clear_at(space: PhysicsDirectSpaceState2D, p: Vector2, r: float) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var s := CircleShape2D.new()
	s.radius = r
	q.shape = s
	q.collision_mask = PLAYER_MASK
	q.transform = Transform2D(0.0, p)
	return space.intersect_shape(q, 1).is_empty()


## Returns {"spawns": int, "blocking": int, "offenders": Array}.
## `blocking` is the per-map control: a scene whose colliders never built reports zero
## overlaps for free, which is the vacuous shape this suite keeps producing.
func _measure(path: String) -> Dictionary:
	var out := {"spawns": 0, "blocking": 0, "offenders": []}
	var script = load(path)
	if script == null:
		return out
	var m = script.new()
	if not (m is Node):
		return out
	var vp := _isolated_viewport()
	vp.add_child(m)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := vp.world_2d.direct_space_state
	var tls: Array[TileMapLayer] = []
	for c in m.get_children():
		if c is TileMapLayer:
			tls.append(c)
	for tl in tls:
		for cell in tl.get_used_cells():
			if not _clear_at(space, Vector2(cell.x * 32 + 16, cell.y * 32 + 16), PLAYER_RADIUS):
				out["blocking"] = int(out["blocking"]) + 1

	if not ("spawn_points" in m and m.spawn_points is Dictionary):
		return out
	var names: Array = m.spawn_points.keys()
	names.sort()
	for k in names:
		var p = m.spawn_points[k]
		if not (p is Vector2):
			continue
		out["spawns"] = int(out["spawns"]) + 1
		if _clear_at(space, p as Vector2, SAFE_RADIUS):
			continue
		var tight := not _clear_at(space, p as Vector2, PLAYER_RADIUS)
		out["offenders"].append("%s spawn '%s' at %s: %s" % [
			path.get_file(), k, str(p),
			"INSIDE a collider" if tight else "within the shipped safe_margin of one"])
	return out


## The corpus must be real before any absence assertion below means anything.
func test_the_overworld_corpus_is_present_and_collides() -> void:
	var paths := _map_paths()
	assert_gt(paths.size(), 4, "found %d overworld maps — a small count means the scan broke" % paths.size())
	# named member, not a count: W1 is the map struktured plays most and it carried 5 of the 15
	assert_true("res://src/exploration/OverworldScene.gd" in paths, "W1's OverworldScene is in the corpus")
	assert_false("res://src/exploration/ZzzNotAMap.gd" in paths, "a fabricated name is absent, so membership means something")


func test_no_overworld_spawn_places_the_player_inside_a_collider() -> void:
	var paths := _map_paths()
	var offenders: Array = []
	var total_spawns := 0
	var thin: Array = []
	for path in paths:
		var r: Dictionary = await _measure(path)
		total_spawns += int(r["spawns"])
		offenders.append_array(r["offenders"])
		# a map with no blocking cells cannot fail, so it must not be counted as covered
		if int(r["blocking"]) < 50:
			thin.append("%s (%d blocking cells)" % [path.get_file(), int(r["blocking"])])
	assert_true(thin.is_empty(),
		"map(s) built too little collision for the probe to mean anything: %s" % ", ".join(thin))
	assert_gt(total_spawns, 40,
		"probed %d spawn points — too few; spawn_points did not populate and the check is vacuous" % total_spawns)
	assert_true(offenders.is_empty(),
		"%d overworld spawn(s) place the player in solid geometry:\n  %s" % [
			offenders.size(), "\n  ".join(offenders)])
