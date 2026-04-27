extends GutTest

## Movement Isolation Test — physics only, no Mode 7
##
## Investigates whether movement asymmetry is visual (Mode 7 shader) or
## physical (CharacterBody2D velocity/collision).  All tests drive velocity
## directly; _physics_process is never involved so Input, GameLoop, and
## Mode7Overlay camera rotation are completely bypassed.

const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const TILE_SIZE: float = 32.0
const MOVE_SPEED: float = 180.0
const FRAMES: int = 30
const PHYSICS_DT: float = 1.0 / 60.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_player(pos: Vector2) -> CharacterBody2D:
	var p = OverworldPlayerScript.new()
	p.position = pos
	p.current_job = "fighter"
	p.can_move = true
	return p


func _make_wall(pos: Vector2, size: Vector2) -> StaticBody2D:
	var wall = StaticBody2D.new()
	wall.position = pos
	wall.collision_layer = 1
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	wall.add_child(col)
	return wall


func _drive_velocity(player: CharacterBody2D, vel: Vector2, frames: int) -> void:
	for _i in range(frames):
		player.velocity = vel
		player.move_and_slide()
		await get_tree().physics_frame


# ---------------------------------------------------------------------------
# Test 1 — horizontal vs vertical distance equality
#
# Each direction is driven for FRAMES frames at MOVE_SPEED pixels/frame (set
# every frame, so there is no lerp uncertainty).  Without walls the player
# should travel the same absolute distance regardless of axis.
# ---------------------------------------------------------------------------

func test_horizontal_vs_vertical_distance_equal():
	gut.p("=== Test 1: Horizontal vs Vertical Distance (no walls) ===")
	gut.p("  Driving %d frames at %.0f px/s  (dt=1/60, expected ~%.1f px total)" % [
		FRAMES, MOVE_SPEED, MOVE_SPEED * FRAMES * PHYSICS_DT])

	var dirs := {
		"right": Vector2(MOVE_SPEED, 0),
		"left":  Vector2(-MOVE_SPEED, 0),
		"down":  Vector2(0, MOVE_SPEED),
		"up":    Vector2(0, -MOVE_SPEED),
	}

	var distances := {}

	for dir_name in dirs:
		var player = _make_player(Vector2(500, 500))
		add_child_autofree(player)
		await get_tree().physics_frame

		var start = player.position
		await _drive_velocity(player, dirs[dir_name], FRAMES)
		var dist = player.position.distance_to(start)
		distances[dir_name] = dist
		gut.p("  %s: %.2f px  (start=%s end=%s)" % [dir_name, dist, start, player.position])

		player.queue_free()
		await get_tree().physics_frame

	var right_d: float = distances["right"]
	var left_d: float  = distances["left"]
	var down_d: float  = distances["down"]
	var up_d: float    = distances["up"]

	gut.p("  --- Distance summary ---")
	gut.p("  right=%.2f  left=%.2f  down=%.2f  up=%.2f" % [right_d, left_d, down_d, up_d])
	gut.p("  H diff (right-left): %.4f px" % abs(right_d - left_d))
	gut.p("  V diff (down-up):    %.4f px" % abs(down_d - up_d))
	gut.p("  H-vs-V diff:         %.4f px" % abs((right_d + left_d) * 0.5 - (down_d + up_d) * 0.5))

	var tolerance: float = 1.0
	assert_almost_eq(right_d, left_d, tolerance,
		"right (%.2f) != left (%.2f) — horizontal physics asymmetry" % [right_d, left_d])
	assert_almost_eq(down_d, up_d, tolerance,
		"down (%.2f) != up (%.2f) — vertical physics asymmetry" % [down_d, up_d])
	assert_almost_eq((right_d + left_d) * 0.5, (down_d + up_d) * 0.5, tolerance,
		"H avg (%.2f) != V avg (%.2f) — horizontal vs vertical physics asymmetry" % [
			(right_d + left_d) * 0.5, (down_d + up_d) * 0.5])


# ---------------------------------------------------------------------------
# Test 2 — perpendicular slide off a wall
#
# Drive player rightward into a vertical wall until stopped, then drive
# downward for 20 frames.  The CircleShape2D + wall_min_slide_angle=0 means
# the player should slide freely along the wall surface.
# ---------------------------------------------------------------------------

func test_perpendicular_slide_along_wall():
	gut.p("=== Test 2: Perpendicular Slide Along Wall ===")

	var player = _make_player(Vector2(200, 300))
	add_child_autofree(player)

	# Vertical wall 80 px to the right, tall enough not to be jumped around
	var wall = _make_wall(Vector2(280, 300), Vector2(TILE_SIZE, TILE_SIZE * 8))
	add_child_autofree(wall)
	await get_tree().physics_frame

	# Phase 1 — drive into wall until fully stopped
	await _drive_velocity(player, Vector2(MOVE_SPEED, 0), 30)
	var x_after_impact = player.position.x
	gut.p("  X after 30 frames into wall: %.2f  (wall center x=280, half=16 → stop ~%.0f)" % [
		x_after_impact, 280.0 - 16.0 - 7.0])

	# Phase 2 — drive downward along the wall face
	var y_before = player.position.y
	await _drive_velocity(player, Vector2(0, MOVE_SPEED), 20)
	var y_moved = player.position.y - y_before
	var x_drift = abs(player.position.x - x_after_impact)

	gut.p("  Y moved while pressing down against wall: %.2f px" % y_moved)
	gut.p("  X drift during downward slide: %.4f px" % x_drift)

	assert_gt(y_moved, 20.0,
		"Player should slide downward along wall — y moved only %.2f px" % y_moved)
	assert_lt(x_drift, 2.0,
		"Player should not drift into/through wall during slide — x drift %.4f" % x_drift)
	gut.p("  PASS: slide works")


# ---------------------------------------------------------------------------
# Test 3 — corner entrapment
#
# Two walls meeting at a corner.  Drive player into the corner for 40 frames,
# then drive away for 30 frames.  The player must escape — "permanently stuck"
# is defined as moving < 1 px after a clean escape direction is pressed.
# ---------------------------------------------------------------------------

func test_corner_does_not_permanently_stick():
	gut.p("=== Test 3: Corner Entrapment Recovery ===")

	var player = _make_player(Vector2(300, 300))
	add_child_autofree(player)

	# Right wall (vertical)
	var wall_r = _make_wall(Vector2(380, 300), Vector2(TILE_SIZE, TILE_SIZE * 6))
	add_child_autofree(wall_r)
	# Bottom wall (horizontal) — meets the right wall
	var wall_b = _make_wall(Vector2(300, 380), Vector2(TILE_SIZE * 6, TILE_SIZE))
	add_child_autofree(wall_b)
	await get_tree().physics_frame

	# Drive into the corner diagonally
	var into_corner = Vector2(MOVE_SPEED, MOVE_SPEED).normalized() * MOVE_SPEED
	await _drive_velocity(player, into_corner, 40)
	var corner_pos = player.position
	gut.p("  Position after driving into corner: %s" % corner_pos)

	# Drive away from the corner (up-left)
	var escape_vel = Vector2(-MOVE_SPEED, -MOVE_SPEED).normalized() * MOVE_SPEED
	await _drive_velocity(player, escape_vel, 30)
	var escaped_dist = player.position.distance_to(corner_pos)

	gut.p("  Position after escape attempt: %s" % player.position)
	gut.p("  Distance escaped from corner: %.2f px" % escaped_dist)

	assert_gt(escaped_dist, 5.0,
		"Player is permanently stuck in corner — escaped only %.2f px" % escaped_dist)
	gut.p("  PASS: not permanently stuck")


# ---------------------------------------------------------------------------
# Test 4 — grid of wall tiles around open centre
#
# Builds a ring of StaticBody2D tiles around an open centre and places the
# player in the middle.  Drives in all 4 directions, records distance before
# collision stops movement.
#
# NOTE: OverworldPlayer's CollisionShape2D has position offset (0, +4) — the
# collision circle sits 4 px below the node position (feet-grounded feel).
# This means the effective gap to the "down" wall is 4 px smaller and to the
# "up" wall 4 px larger.  We compensate by shifting the vertical walls by
# +4 px (down wall 4 px farther, up wall 4 px closer) so the *collision*
# distances are symmetric.  This tests that physics is symmetric given equal
# collision geometry — not that the visual offsets are invisible.
# ---------------------------------------------------------------------------

const COLLISION_OFFSET_Y: float = 0.0  # CollisionShape2D position.y in OverworldPlayer
# (was 4.0 historically; Mode 7 integration centered the collision shape —
# OverworldPlayer.gd ~line 234 sets `collision.position = Vector2(0, 0)`.
# Walls below compensate for this offset, so when offset == 0 they're
# placed symmetrically around the player center.)

func test_symmetric_wall_grid():
	gut.p("=== Test 4: Symmetric Wall Grid (4-direction collision parity) ===")
	gut.p("  NOTE: collision offset +%.0f px on Y axis — walls compensated accordingly" % COLLISION_OFFSET_Y)

	# Centre of the open cell is at (500, 500).
	var centre := Vector2(500, 500)
	var player = _make_player(centre)
	add_child_autofree(player)

	# Walls 64 px away from centre on each side.
	# Down and up walls are shifted by COLLISION_OFFSET_Y so the gap between
	# the collision circle and each wall is identical in all 4 directions.
	var wall_configs := [
		[centre + Vector2(64, 0),                         Vector2(TILE_SIZE, TILE_SIZE * 3)],  # right
		[centre + Vector2(-64, 0),                        Vector2(TILE_SIZE, TILE_SIZE * 3)],  # left
		[centre + Vector2(0, 64 + COLLISION_OFFSET_Y),    Vector2(TILE_SIZE * 3, TILE_SIZE)],  # down
		[centre + Vector2(0, -64 + COLLISION_OFFSET_Y),   Vector2(TILE_SIZE * 3, TILE_SIZE)],  # up
	]
	for cfg in wall_configs:
		var w = _make_wall(cfg[0], cfg[1])
		add_child_autofree(w)

	await get_tree().physics_frame

	var dir_vels := {
		"right": Vector2(MOVE_SPEED, 0),
		"left":  Vector2(-MOVE_SPEED, 0),
		"down":  Vector2(0, MOVE_SPEED),
		"up":    Vector2(0, -MOVE_SPEED),
	}

	var travel := {}

	for dir_name in dir_vels:
		# Reset player to centre before each direction test
		player.position = centre
		player.velocity = Vector2.ZERO
		await get_tree().physics_frame

		var start = player.position
		await _drive_velocity(player, dir_vels[dir_name], 25)
		travel[dir_name] = player.position.distance_to(start)
		gut.p("  %s: %.2f px from centre" % [dir_name, travel[dir_name]])

	gut.p("  --- Parity check (tolerance ±2 px) ---")
	var vals := [travel["right"], travel["left"], travel["down"], travel["up"]]
	var vmax: float = vals.max()
	var vmin: float = vals.min()
	gut.p("  max=%.2f  min=%.2f  spread=%.2f" % [vmax, vmin, vmax - vmin])

	var parity_tolerance: float = 2.0
	assert_almost_eq(travel["right"], travel["left"], parity_tolerance,
		"right/left parity failure: %.2f vs %.2f" % [travel["right"], travel["left"]])
	assert_almost_eq(travel["down"], travel["up"], parity_tolerance,
		"down/up parity failure: %.2f vs %.2f" % [travel["down"], travel["up"]])
	assert_almost_eq((travel["right"] + travel["left"]) * 0.5,
		(travel["down"] + travel["up"]) * 0.5, parity_tolerance,
		"H-vs-V parity failure: H_avg=%.2f  V_avg=%.2f" % [
			(travel["right"] + travel["left"]) * 0.5,
			(travel["down"] + travel["up"]) * 0.5])
	gut.p("  PASS: symmetric wall grid")


# ---------------------------------------------------------------------------
# Test 5 — all distances are non-trivially large (sanity check)
# ---------------------------------------------------------------------------

func test_player_actually_moves_all_four_directions():
	gut.p("=== Test 5: Player Moves Non-Trivially in All 4 Directions ===")

	var dirs := {
		"right": Vector2(MOVE_SPEED, 0),
		"left":  Vector2(-MOVE_SPEED, 0),
		"down":  Vector2(0, MOVE_SPEED),
		"up":    Vector2(0, -MOVE_SPEED),
	}

	for dir_name in dirs:
		var player = _make_player(Vector2(500, 500))
		add_child_autofree(player)
		await get_tree().physics_frame

		var start = player.position
		await _drive_velocity(player, dirs[dir_name], FRAMES)
		var dist = player.position.distance_to(start)
		gut.p("  %s: %.2f px" % [dir_name, dist])
		assert_gt(dist, 30.0,
			"Player barely moved %s (%.2f px) — physics may be broken" % [dir_name, dist])

		player.queue_free()
		await get_tree().physics_frame

	gut.p("  PASS: all directions produce meaningful travel")
