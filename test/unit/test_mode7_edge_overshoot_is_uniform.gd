extends GutTest

## Every Mode 7 world must block the player the SAME distance past a drawn edge.
##
## Mode7Overlay.apply_terrain_collision_alignment clones the terrain layer and shifts it down by
## InteractGeometry.MODE7_GROUND_DISPLACEMENT_PX, so the player is stopped that far past where the
## edge is drawn. struktured's standing note is that the water/mountain edge is "a bit off"; measured
## in a rendered frame on 2026-09-09 it is 97 screen px of ground he can see and cannot cross.
##
## WHAT IS PINNED HERE IS THE CONSISTENCY, NOT THE VALUE. InteractGeometry's own comment carries
## cowir-main's ruling: "trigger geometry and terrain collision must agree with EACH OTHER more than
## either must be 'true' — a uniform offset is adapted to in minutes while inconsistency is
## unlearnable". 140.6 is PLAYTESTED and does not move on a test's say-so, so the expectation below
## is DERIVED from the constant: retune it and this stays green, break one world's alignment and it
## goes red naming that world.
##
## Measured uniform at 148.2 px across five worlds and five different blocking terrains (water, tree,
## pipe, brick, server) before this was written, which is why "they all agree" is worth pinning: it
## means one number still fixes all five, and that is only true while they agree.
##
## PROBE COORDINATES ARE NOT THE SUBJECT. Each entry is a spot where a straight blocking edge ran at
## the time of writing. If a map edit moves one, the probe stops hitting anything — so a probe that
## fails to be blocked FAILS rather than silently contributing no measurement.

const WORLDS := [
	{"name": "medieval", "path": "res://src/exploration/OverworldScene.gd", "from": Vector2(976, 960), "edge_y": 768.0},
	{"name": "suburban", "path": "res://src/exploration/SuburbanOverworld.gd", "from": Vector2(3120, 2144), "edge_y": 1952.0},
	{"name": "steampunk", "path": "res://src/exploration/SteampunkOverworld.gd", "from": Vector2(3984, 928), "edge_y": 736.0},
	{"name": "industrial", "path": "res://src/exploration/IndustrialOverworld.gd", "from": Vector2(3472, 1952), "edge_y": 1760.0},
	{"name": "futuristic", "path": "res://src/exploration/FuturisticOverworld.gd", "from": Vector2(4624, 960), "edge_y": 768.0},
]
## The player's own clearance shows up in every measurement and is not part of the displacement.
const CLEARANCE_TOLERANCE := 12.0


func _overshoot(entry: Dictionary) -> float:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var w = load(entry["path"]).new()
	vp.add_child(w)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var body := CharacterBody2D.new()
	var cs := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 4.0
	cs.shape = circ
	body.add_child(cs)
	body.collision_mask = 1
	vp.add_child(body)
	body.global_position = entry["from"]
	await get_tree().physics_frame

	var last: Vector2 = body.global_position
	var still := 0
	for step in range(400):
		body.velocity = Vector2(0, -90)
		body.move_and_slide()
		await get_tree().physics_frame
		if body.global_position.distance_to(last) < 0.05:
			still += 1
			if still >= 3:
				break
		else:
			still = 0
		last = body.global_position
	# Never blocked -> the probe walked off its own edge; report it as absent, not as a number.
	if still < 3:
		return NAN
	return body.global_position.y - float(entry["edge_y"])


func test_every_mode7_world_blocks_at_the_same_distance() -> void:
	var expected: float = InteractGeometry.MODE7_GROUND_DISPLACEMENT_PX
	assert_gt(expected, 1.0, "CONTROL: the displacement constant did not resolve; every comparison below is against zero")

	var seen := {}
	var never_blocked: Array = []
	for entry in WORLDS:
		var o: float = await _overshoot(entry)
		if is_nan(o):
			never_blocked.append(str(entry["name"]))
			continue
		seen[str(entry["name"])] = o

	assert_eq(never_blocked, [],
		"a probe walked without ever being blocked -- its coordinate is no longer a blocking edge, so that world contributed no measurement: %s" % str(never_blocked))
	assert_eq(seen.size(), WORLDS.size(), "measured %d of %d worlds" % [seen.size(), WORLDS.size()])

	# Every world must agree with every other, and with the shared constant plus a small clearance.
	var off: Array = []
	for name in seen:
		var o: float = seen[name]
		if absf(o - expected) > CLEARANCE_TOLERANCE:
			off.append("%s stops %.1f past the edge, constant is %.1f" % [name, o, expected])
	off.sort()
	assert_eq(off, [],
		"a Mode 7 world no longer blocks at the shared displacement -- the offsets stop agreeing with each other, which is the thing a player cannot learn: %s" % str(off))

	var values: Array = seen.values()
	var lo: float = values[0]
	var hi: float = values[0]
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	assert_lt(hi - lo, 1.0,
		"the five worlds disagree by %.1f px; they measured identical when this was written" % (hi - lo))
