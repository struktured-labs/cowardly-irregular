extends GutTest

## The Mode 7 collision alignment must actually RUN. Nothing checked that.
##
## `TileMapCollision` — the displaced duplicate that carries ALL terrain physics on every
## Mode 7 map — is named by 0 of 1231 test files. `test_mode7_terrain_displacement_regression`
## pins the displacement's MAGNITUDE from source constants without instantiating a map, so if
## `apply_terrain_collision_alignment` silently stopped being called, that file would stay
## green while every Mode 7 world regained the 4.39-tile visual/physical mismatch the whole
## compensation stack exists to hide.
##
## SCOPE. This file deliberately does NOT re-check the displacement arithmetic or preset
## uniformity — `test_mode7_terrain_displacement_regression` owns both, and a second
## derivation would have inherited the same offset error a fourth time (cowir-sfx caught
## exactly that before this was written). What is here is the part nothing covered: does the
## alignment run, and are the camera values it depends on what the code actually sets.

const Mode7 := preload("res://src/exploration/Mode7Overlay.gd")

const EXPLORATION_DIR := "res://src/exploration"
const NOT_MAPS := ["OverworldNPC.gd", "OverworldPlayer.gd", "OverworldController.gd", "OverworldMinimap.gd"]
## Below this a "collider" is present but empty, which is the same as absent to a player.
const MIN_BLOCKING_CELLS := 50


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


## Counts cells that actually STOP A BODY, via the same query the spawn-overlap ratchet uses.
## Reading TileData polygons instead reports the TILESET's shape and is blind to the layer's
## `collision_enabled` — which is the single line that would silently retire the alignment.
func _blocking_cells(map: Node, layer: TileMapLayer) -> int:
	var space := (map.get_viewport() as SubViewport).world_2d.direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = 4.0
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collision_mask = 1
	var hits := 0
	for cell in layer.get_used_cells():
		q.transform = Transform2D(0.0, Vector2(cell.x * 32 + 16, cell.y * 32 + 16))
		# Count ONLY colliders belonging to the displaced layer. `_create_map_boundaries()`
		# puts StaticBody2D walls on the same mask, and counting those made this pass with
		# the alignment fully disabled — the mutation went green until this filter existed.
		for hit in space.intersect_shape(q, 8):
			if hit.get("collider") == layer:
				hits += 1
				break
		if hits >= MIN_BLOCKING_CELLS * 2:
			break
	return hits


func test_the_overworld_corpus_is_real() -> void:
	var paths := _map_paths()
	assert_gt(paths.size(), 4, "found %d overworld maps — a small count means the scan broke" % paths.size())
	assert_true("res://src/exploration/OverworldScene.gd" in paths, "W1 is in the corpus")
	assert_false("res://src/exploration/ZzzNotAMap.gd" in paths, "a fabricated name is absent, so membership means something")


## The displacement test MIRRORS the camera values as its own consts ("mirrored from the
## live call sites"), so a change to apply_camera() would leave it green and wrong. This
## drives the real function instead, which is the join those consts assume and never check.
func test_the_camera_values_the_displacement_depends_on_come_from_apply_camera() -> void:
	var cam := Camera2D.new()
	add_child_autofree(cam)
	Mode7.apply_camera(cam, true)
	assert_almost_eq(cam.zoom.y, 0.85, 0.001, "Mode 7 camera zoom — the displacement divides by this")
	assert_almost_eq(cam.offset.y, -20.0, 0.001,
		"Mode 7 camera offset. WORLD units — measured in-engine, zoom-invariant across 0.5/0.85/2.0 — so it scales INTO screen space by zoom rather than being divided by it.")

	# control: the flat arm must differ, or apply_camera is ignoring its parameter and
	# both readings above are of whatever the default happens to be
	var flat := Camera2D.new()
	add_child_autofree(flat)
	Mode7.apply_camera(flat, false)
	assert_ne(flat.zoom.y, cam.zoom.y, "the mode7 and flat arms must differ, or the flag is ignored")


## Keyed on each map's own `mode7_enabled` rather than an exemption list. W6 Abstract is
## deliberately flat ("the overworld mechanic itself breaks — no ground plane"), so it must
## NOT build the duplicate; that makes Abstract covered rather than excused, and catches
## Mode 7 being silently switched on for it as loudly as the alignment switching off.
func test_every_mode7_world_builds_a_populated_displaced_collider() -> void:
	var checked := 0
	var mode7_worlds := 0
	var offenders: Array = []
	for path in _map_paths():
		var script = load(path)
		if script == null:
			continue
		var m = script.new()
		if not (m is Node):
			continue
		if not ("mode7_enabled" in m):
			continue
		var wants_mode7: bool = m.mode7_enabled
		_isolated_viewport().add_child(m)
		await get_tree().physics_frame

		var displaced: TileMapLayer = null
		for c in m.get_children():
			if c is TileMapLayer and str(c.name) == "TileMapCollision":
				displaced = c
		checked += 1

		if not wants_mode7:
			if displaced != null:
				offenders.append("%s has mode7_enabled=false but built a TileMapCollision — a flat world with a displaced collider blocks 4.39 tiles from where it draws" % path.get_file())
			continue
		mode7_worlds += 1
		if displaced == null:
			offenders.append("%s is a Mode 7 world with NO TileMapCollision — terrain physics is back on the authored layer, unaligned with the warp" % path.get_file())
			continue
		# PHYSICS, not tile data. `collision_enabled = false` on the layer stops it blocking
		# anything while every TileData still reports its polygons — a tileset-shaped count
		# reads identically before and after, and a mutation of that line passed this test.
		var solid := _blocking_cells(m, displaced)
		if solid < MIN_BLOCKING_CELLS:
			offenders.append("%s built a TileMapCollision that blocks only %d cells in the physics space — the layer exists but is not colliding" % [path.get_file(), solid])

	assert_gt(checked, 4, "checked %d overworlds — too few to be a sweep" % checked)
	# without this, a corpus that somehow reported every map as flat would pass for free
	assert_gt(mode7_worlds, 3, "only %d Mode 7 worlds found — the alignment check covered almost nothing" % mode7_worlds)
	assert_true(offenders.is_empty(), "Mode 7 alignment problem(s):\n  %s" % "\n  ".join(offenders))
