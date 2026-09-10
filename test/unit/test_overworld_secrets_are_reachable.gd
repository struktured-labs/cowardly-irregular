extends GutTest

## A chest you cannot stand next to can never be opened, and it looks exactly like one you have not
## walked to yet.
##
## FOUND 2026-09-10: the 200x140 W1 re-author moved the land under six chest coordinates — four
## inside mountain, one in water, one behind a wall that was itself inside mountain. Nothing errored.
##
## ⚠️ THIS TEST IS A PHYSICS QUERY BECAUSE THE MAP MODEL WAS WRONG, and that is the whole story of
## how it got here. My first version read the shipped PNG and asked whether the chest's cell was
## walkable terrain. That is a fourth grid model of this question and it disagreed with the engine on
## 3 of 12 chests, IN BOTH DIRECTIONS — it cleared two chests that are inside colliders and condemned
## one that is not. The reason is the Mode 7 terrain clone: colliders are displaced +140.6 px, so the
## body standing at row N collides against row N-4.4, and no amount of care with the PNG can see
## that. test_village_dungeon_spawn_overlap_regression's header already said this — "four grid models
## were tried and all four were wrong, including two that agreed with each other" — and I wrote
## another one anyway, six hours after reading it.
##
## 🔑 THE MODE 7 DEPTH RULE, measured here and not previously written down: because the clone is
## displaced 4.4 tiles, a dead-end pocket SHALLOWER than five tiles cannot be entered at all — you
## are blocked by whatever lies past it while still outside it. W1's only articulation point seals
## exactly four tiles, which is why OverworldScene now ships an empty hidden-passage list. Anyone
## adding a secret to a Mode 7 world needs a pocket at least six tiles deep.

const WORLDS := {
	"medieval": "res://src/exploration/OverworldScene.gd",
	"suburban": "res://src/exploration/SuburbanOverworld.gd",
	"steampunk": "res://src/exploration/SteampunkOverworld.gd",
	"industrial": "res://src/exploration/IndustrialOverworld.gd",
	"futuristic": "res://src/exploration/FuturisticOverworld.gd",
	"abstract": "res://src/exploration/AbstractOverworld.gd",
}
## OverworldPlayer's own radius plus its solver margin — the clearance a real body needs.
const BODY_RADIUS := 8.0


func test_no_overworld_chest_is_sealed_inside_terrain() -> void:
	var sealed: Array = []
	var worlds_built := 0
	var chests_probed := 0

	for label in WORLDS:
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()   # own space: villages and worlds all sit at (0,0) otherwise
		add_child_autofree(vp)
		var w = load(WORLDS[label]).new()
		vp.add_child(w)
		await get_tree().physics_frame
		await get_tree().physics_frame
		worlds_built += 1

		var space := vp.world_2d.direct_space_state
		var shape := CircleShape2D.new()
		shape.radius = BODY_RADIUS
		for n in w.get_children():
			if n.get_script() == null or not ("chest_id" in n) or not (n is Node2D):
				continue
			chests_probed += 1
			var q := PhysicsShapeQueryParameters2D.new()
			q.shape = shape
			q.transform = Transform2D(0.0, (n as Node2D).global_position)
			q.collision_mask = 1
			q.collide_with_bodies = true
			var hits := space.intersect_shape(q, 1)
			if not hits.is_empty():
				sealed.append("%s/%s at %s" % [label, str(n.chest_id), str((n as Node2D).global_position)])
	sealed.sort()

	assert_eq(worlds_built, WORLDS.size(), "built %d of %d overworlds" % [worlds_built, WORLDS.size()])
	assert_gt(chests_probed, 10, "CONTROL: only %d chests probed across every overworld -- the scan is broken and the zero below is free" % chests_probed)
	assert_eq(sealed, [],
		"a treasure chest is inside terrain collision -- it renders normally and can never be opened: %s" % str(sealed))


func test_the_probe_can_see_a_chest_inside_a_wall() -> void:
	# CONTROL: the query must report an overlap for a point that IS inside terrain, or the sweep
	# above proves nothing. (12,4) in PNG cells is the mountain shelf beside W1's north wall.
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var w = load(WORLDS["medieval"]).new()
	vp.add_child(w)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var shape := CircleShape2D.new()
	shape.radius = BODY_RADIUS
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	# A position the engine has ALREADY reported as blocked — W1's old w1_cave_hipotion cell. Picking
	# a control point off the PNG is how the first version of this control failed: the collider is
	# displaced, so "the map says mountain here" does not mean a body collides here.
	q.transform = Transform2D(0.0, Vector2(4 * 2 * 32 + 16, 40 * 2 * 32 + 16))
	q.collision_mask = 1
	assert_false(vp.world_2d.direct_space_state.intersect_shape(q, 1).is_empty(),
		"CONTROL: a point known to sit in terrain must report an overlap, or every clear result above is free")
