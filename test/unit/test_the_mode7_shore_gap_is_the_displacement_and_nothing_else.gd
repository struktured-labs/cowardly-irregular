extends GutTest

## struktured, 2026-09-06: "the water/mountain edge is a bit off". This measures how far off, on a
## terrain feature nobody chose for the purpose, and pins WHY rather than the number.
##
## ⚠️ I PUBLISHED A WRONG ANSWER TO THIS QUESTION ONCE AND WITHDREW IT. That version walked from a
## start row my own script derived from the edge row, so start-minus-edge was a constant by
## construction in all five worlds, and the "uniform 148.2" it produced was arithmetic I had authored
## into the coordinates. This one is different in the way that matters: the edge is a water inlet
## already on the W1 map at tiles (38..41, 24..29), the start is a round number well south of it, and
## the stop is found by driving the real body until it stops moving. Nothing here derives one input
## from the other.
##
## MEASURED: the body stops 148.2 px short of the last land tile's north face — 4.63 tiles of real,
## ordinary grass it can see and cannot step onto. That is the complaint, and it is not a bug in the
## map: 148.2 = MODE7_GROUND_DISPLACEMENT_PX (140.6) + the body's own radius. The terrain collider
## clone is displaced south so that collisions line up with the ground drawn UNDER THE SPRITE, which
## is not the ground at the player's world position — the sprite is drawn at 0.75 of the viewport
## while its own ground projects near the bottom of the frame.
##
## 🛑 SO THE CONSTANT IS NOT WRONG AND THIS TEST DOES NOT PIN IT. It asserts the RELATIONSHIP:
## whatever the displacement is, the shore gap must equal it plus the body radius. Change 140.6
## deliberately and this stays green because the behaviour follows. What it catches is the
## correspondence breaking — the clone not displaced, displaced twice, or a body whose collider
## stops tracking its radius.

const SCENE := "res://src/exploration/OverworldScene.gd"
## A water inlet that was already on the map: tiles x38..41 are water for y24..29, land from y30.
const LANE_X := 39.5
const START_Y := 36.0
const LAND_EDGE_Y := 30.0
const TILE := 32.0
## OverworldPlayer's capsule radius. The solver leaves a sub-pixel margin, hence the tolerance.
const BODY_RADIUS := 8.0
const TOLERANCE_PX := 3.0


func test_the_body_stops_exactly_one_displacement_short_of_the_water() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var scene = load(SCENE).new()
	vp.add_child(scene)
	await get_tree().physics_frame

	var p = scene.get("player")
	assert_not_null(p, "CONTROL: the overworld must expose a player body")
	if p == null:
		return

	var start := Vector2(LANE_X * TILE, START_Y * TILE)
	p.global_position = start
	await get_tree().physics_frame

	var last: Vector2 = p.global_position
	var still := 0
	var steps := 0
	for i in range(400):
		p.velocity = Vector2(0, -110)
		p.move_and_slide()
		await get_tree().physics_frame
		steps += 1
		if p.global_position.distance_to(last) < 0.05:
			still += 1
			if still >= 5:
				break
		else:
			still = 0
		last = p.global_position

	var stopped: float = p.global_position.y
	assert_lt(stopped, start.y - TILE,
		"CONTROL: the body never moved north at all — it is blocked at the start, so the gap below is not a shore measurement")
	assert_gt(steps, 5, "CONTROL: the walk ended immediately")

	var gap_px: float = stopped - LAND_EDGE_Y * TILE
	var expected: float = InteractGeometry.MODE7_GROUND_DISPLACEMENT_PX + BODY_RADIUS
	assert_almost_eq(gap_px, expected, TOLERANCE_PX,
		"the shore gap is no longer the clone displacement plus the body radius: measured %.1f px (%.2f tiles), expected %.1f" %
		[gap_px, gap_px / TILE, expected])
