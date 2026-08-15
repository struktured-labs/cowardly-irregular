extends GutTest

## Every map transition must be reachable by the player's body.
##
## Found 2026-08-15. SteampunkOverworld's BackPortal -- the return route to W2 -- sat at
## y = -92.6 with 3.4px of its 192px box inside the map, while the lowest y a body can
## occupy in that column is 38.0. The player arrives from W2 standing at y=48 and can never
## re-enter the portal they arrived through.
##
## THE MECHANISM IS GENERAL, WHICH IS WHY THIS IS A RATCHET AND NOT A ONE-LINE FIX. Trigger
## geometry is pushed NORTH by `MODE7_TRIGGER_Y_OFFSET` (-140.6). Any trigger anchored within
## ~140px of the map's top edge is pushed off the map by that recipe. Steampunk's was
## anchored at y=48 because that is where the player ARRIVES; the other three back portals
## are anchored near their maps' bottom edges, so the identical recipe is harmless for them.
## Nothing distinguishes the two cases at the call site -- all 16 sites are the same line.
##
## REACHABILITY, NOT BOUNDS. "Is the box inside the map rect" is the model, and models have
## lost every round in this area. A box can be fully in-bounds and still sit inside solid
## terrain; it can also poke out of the map and still be enterable. The question a player
## asks is whether a body can stand somewhere that overlaps it, so that is what is measured:
## sample positions across the box, keep the ones where a radius-4 body hits no collider,
## and require at least one.

const PLAYER_RADIUS := 4.0
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


func _body_fits(space: PhysicsDirectSpaceState2D, p: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var s := CircleShape2D.new()
	s.radius = PLAYER_RADIUS
	q.shape = s
	q.collision_mask = PLAYER_MASK
	q.transform = Transform2D(0.0, p)
	return space.intersect_shape(q, 1).is_empty()


func _rect_of(t: Node2D) -> Rect2:
	for ch in t.get_children():
		if ch is CollisionShape2D and (ch as CollisionShape2D).shape is RectangleShape2D:
			var e: Vector2 = ((ch as CollisionShape2D).shape as RectangleShape2D).size
			return Rect2(t.position - e * 0.5, e)
	return Rect2()


## Returns {"checked": int, "offenders": Array, "sampled": int}
func _measure(path: String) -> Dictionary:
	var out := {"checked": 0, "offenders": [], "sampled": 0}
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
	var map_w := float(int(m.MAP_WIDTH) * 32)
	var map_h := float(int(m.MAP_HEIGHT) * 32)
	for c in m.get_children():
		if str(c.name) != "Transitions":
			continue
		for t in c.get_children():
			if not (t is Node2D):
				continue
			var r := _rect_of(t)
			if r.size == Vector2.ZERO:
				continue
			out["checked"] = int(out["checked"]) + 1
			var standable := 0
			# sample the box on an 8px lattice; the body radius is 4, so this cannot step
			# over a standable gap wide enough for the player to occupy
			var y := r.position.y
			while y <= r.end.y:
				var x := r.position.x
				while x <= r.end.x:
					out["sampled"] = int(out["sampled"]) + 1
					# IN BOUNDS **AND** CLEAR. Clear alone is fail-open: off-map space
					# contains no colliders, so a box pushed above y=0 reads as perfectly
					# standable everywhere. The first version of this test did exactly that
					# and its mutation stayed green on a portal the player cannot reach.
					if x >= 0.0 and y >= 0.0 and x <= map_w and y <= map_h and _body_fits(space, Vector2(x, y)):
						standable += 1
					x += 8.0
				y += 8.0
			if standable == 0:
				out["offenders"].append("%s '%s' box %s: NO position in it can hold the player's body" % [
					path.get_file(), t.name, str(r)])
	return out


func test_the_corpus_and_the_probe_are_real() -> void:
	var paths := _map_paths()
	assert_gt(paths.size(), 4, "found %d overworlds -- the scan broke" % paths.size())
	assert_true("res://src/exploration/SteampunkOverworld.gd" in paths,
		"W3 is in the corpus -- it is the map this regression was found in")
	assert_false("res://src/exploration/ZzzNotAMap.gd" in paths,
		"a fabricated name is absent, so membership means something")


func test_every_map_transition_can_be_reached_by_the_player_body() -> void:
	var offenders: Array = []
	var checked := 0
	var sampled := 0
	for path in _map_paths():
		var r: Dictionary = await _measure(path)
		checked += int(r["checked"])
		sampled += int(r["sampled"])
		offenders.append_array(r["offenders"])

	# Controls: an absence is only meaningful if the probe ran over real geometry.
	assert_gt(checked, 10, "only %d transitions found -- the corpus did not build its Transitions" % checked)
	assert_gt(sampled, 1000, "only %d body samples taken -- the lattice did not run" % sampled)
	assert_true(offenders.is_empty(),
		"%d transition(s) the player cannot reach:\n  %s" % [offenders.size(), "\n  ".join(offenders)])
