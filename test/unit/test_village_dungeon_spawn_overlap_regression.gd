extends GutTest

## No village, dungeon or interior spawn point may place the player inside a collider.
##
## `test_overworld_spawn_overlap_regression` asks this question of the 6 overworlds and is
## green. It scans `src/exploration` only, so 60 files carrying 179 `spawn_points[...]`
## writes have never been asked at all -- and the symptom that produced the overworld ratchet
## named these too ("the village/dungeons still as well").
##
## THESE MAPS ARE NOT MODE 7. `apply_terrain_collision_alignment` is called by exactly the 6
## overworlds, so there is no displaced duplicate here and no 4.39-tile frame question. A
## spawn that overlaps here overlaps on the authored grid, which makes this the SIMPLER half
## of the problem and the reason it can be measured without settling the displacement
## dispute.
##
## PHYSICS, NOT A GRID MODEL. The overworld work established this the expensive way: four
## grid models were tried against "is this spawn inside something" and all four were wrong,
## in both directions, including two that agreed with each other. A body query has no grid
## parameter to get wrong. Kept here even though these maps are undisplaced, because the
## body still has extent and a spawn can straddle a cell boundary.
##
## RIG: ONE ISOLATED VIEWPORT PER MAP. Godot's shared default World2D lets bodies from
## different scenes overlap each other -- villages instantiated together all sit at (0,0) and
## report each other's geometry as their own. That produced a false "stranded" result for
## another lane tonight. Each map gets its own SubViewport and its own space.

const PLAYER_RADIUS := 4.0
## OverworldPlayer:257 radius + :232 safe_margin -- the shipped solver's real clearance.
const SAFE_RADIUS := 8.0
const PLAYER_MASK := 1

const DIRS := ["res://src/maps/villages", "res://src/maps/dungeons", "res://src/maps/interiors"]
## Bases, not maps: instantiating an abstract base measures nothing and its spawn table is empty.
const NOT_MAPS := ["BaseVillage.gd", "DragonCave.gd", "BaseInterior.gd"]


func _map_paths() -> Array:
	var out: Array = []
	for d in DIRS:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".gd") and not f in NOT_MAPS:
				out.append(d + "/" + f)
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


## Returns {"spawns": int, "blocking": int, "offenders": Array, "instantiated": bool}.
## `blocking` is the per-map control: a scene whose colliders never built reports zero
## overlaps for free, which is the vacuous shape this suite keeps producing.
func _measure(path: String) -> Dictionary:
	var out := {"spawns": 0, "blocking": 0, "offenders": [], "instantiated": false}
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
	out["instantiated"] = true

	var space := vp.world_2d.direct_space_state
	for c in m.get_children():
		if c is TileMapLayer:
			for cell in (c as TileMapLayer).get_used_cells():
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
		out["offenders"].append("%s '%s' at %s: %s" % [
			path.get_file(), k, str(p),
			"INSIDE a collider" if tight else "within the shipped safe_margin of one"])
	return out


func test_the_corpus_is_real_and_disjoint_from_the_overworld_ratchet() -> void:
	var paths := _map_paths()
	assert_gt(paths.size(), 30, "found %d village/dungeon/interior maps -- the scan broke" % paths.size())
	# named members from each of the three directories, not a count
	assert_true("res://src/maps/villages/HarmoniaVillage.gd" in paths, "the W1 hub village is in the corpus")
	assert_true("res://src/maps/dungeons/WhisperingCave.gd" in paths, "the tutorial dungeon is in the corpus")
	assert_false("res://src/exploration/OverworldScene.gd" in paths,
		"the overworlds are NOT here -- they have their own ratchet, and overlap would double-count")
	assert_false("res://src/maps/villages/ZzzNotAVillage.gd" in paths,
		"a fabricated name is absent, so membership means something")


func test_no_village_dungeon_or_interior_spawn_places_the_player_inside_a_collider() -> void:
	var paths := _map_paths()
	var offenders: Array = []
	var total_spawns := 0
	var instantiated := 0
	var with_collision := 0

	for path in paths:
		var r: Dictionary = await _measure(path)
		if bool(r["instantiated"]):
			instantiated += 1
		total_spawns += int(r["spawns"])
		if int(r["blocking"]) > 0:
			with_collision += 1
		offenders.append_array(r["offenders"])

	# Three controls, because an absence here is only meaningful if the probe ran.
	assert_gt(instantiated, 25, "only %d of %d maps instantiated -- the rest measured nothing" % [instantiated, paths.size()])
	assert_gt(total_spawns, 30, "probed %d spawn points -- too few; spawn_points did not populate" % total_spawns)
	assert_gt(with_collision, 10,
		"only %d maps built ANY blocking geometry -- a map with no colliders cannot fail, so a clean result would be free" % with_collision)

	assert_true(offenders.is_empty(),
		"%d village/dungeon/interior spawn(s) place the player in solid geometry:\n  %s" % [
			offenders.size(), "\n  ".join(offenders)])
