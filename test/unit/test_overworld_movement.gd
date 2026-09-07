extends GutTest

## Test actual player movement and collision in a real overworld scene.
## Spawns OverworldScene, simulates input, verifies positions.

const OverworldPlayerScript = preload("res://src/exploration/OverworldPlayer.gd")
const TILE_SIZE: int = 32


func _create_test_player(pos: Vector2) -> CharacterBody2D:
	var player = OverworldPlayerScript.new()
	player.position = pos
	player.current_job = "fighter"
	return player


func _create_wall_body(pos: Vector2, size: Vector2) -> StaticBody2D:
	var wall = StaticBody2D.new()
	wall.position = pos
	wall.collision_layer = 1  # Player collision_mask = 1
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	wall.add_child(col)
	return wall


func _simulate_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


func test_player_starts_movable():
	var player = _create_test_player(Vector2(200, 200))
	add_child_autofree(player)
	await _simulate_frames(2)

	assert_true(player._can_move(), "Player should be movable at start")
	gut.p("Player can_move: %s, position: %s" % [player._can_move(), player.position])


func test_player_moves_when_input():
	var player = _create_test_player(Vector2(200, 200))
	add_child_autofree(player)
	await _simulate_frames(2)

	var start_pos = player.position
	# Directly set velocity (simulating input without actual InputEvent)
	player.velocity = Vector2(150, 0)  # move_speed to the right
	player.move_and_slide()
	await _simulate_frames(1)

	var moved = player.position.x - start_pos.x
	gut.p("Moved %.1f px right (expected >0)" % moved)
	assert_gt(moved, 0.0, "Player should move right when velocity is set")


func test_player_stops_at_wall():
	var player = _create_test_player(Vector2(200, 200))
	add_child_autofree(player)

	# Place a wall 64px to the right
	var wall = _create_wall_body(Vector2(264, 200), Vector2(TILE_SIZE, TILE_SIZE * 3))
	add_child_autofree(wall)
	await _simulate_frames(2)

	# Push player toward wall for 30 frames
	for _i in range(30):
		player.velocity = Vector2(150, 0)
		player.move_and_slide()
		await get_tree().physics_frame

	gut.p("Player pos after walking into wall: %s (wall at x=264)" % player.position)
	# Player should be stopped before the wall (within collision radius + wall half-size)
	assert_lt(player.position.x, 264.0, "Player should stop before wall")
	assert_gt(player.position.x, 220.0, "Player should have moved toward wall")


func test_player_slides_along_wall():
	var player = _create_test_player(Vector2(200, 200))
	add_child_autofree(player)

	# Place a wall to the right spanning vertically
	var wall = _create_wall_body(Vector2(240, 200), Vector2(TILE_SIZE, TILE_SIZE * 6))
	add_child_autofree(wall)
	await _simulate_frames(2)

	var start_y = player.position.y

	# Push player diagonally into wall (right + down)
	for _i in range(20):
		player.velocity = Vector2(150, 150).normalized() * 150.0
		player.move_and_slide()
		await get_tree().physics_frame

	var moved_y = player.position.y - start_y
	gut.p("Slid %.1f px along wall (expected >0 vertical movement)" % moved_y)
	# With FLOATING mode + wall_min_slide_angle=0, player should slide vertically
	assert_gt(moved_y, 10.0, "Player should slide along wall in FLOATING mode")


func test_floating_mode_set():
	var player = _create_test_player(Vector2(100, 100))
	add_child_autofree(player)
	await _simulate_frames(2)

	assert_eq(player.motion_mode, CharacterBody2D.MOTION_MODE_FLOATING,
		"Player must use FLOATING mode for top-down movement")
	gut.p("motion_mode: FLOATING ✓")


func test_collision_shape_is_circle():
	var player = _create_test_player(Vector2(100, 100))
	add_child_autofree(player)
	await _simulate_frames(2)

	var col = player.get_node_or_null("Collision")
	assert_not_null(col, "Player should have Collision node")
	assert_true(col.shape is CircleShape2D, "Collision should be CircleShape2D")
	gut.p("Collision shape: CircleShape2D, radius: %.0f" % col.shape.radius)


func test_movement_all_four_directions():
	var directions = {
		"right": Vector2(150, 0),
		"left": Vector2(-150, 0),
		"down": Vector2(0, 150),
		"up": Vector2(0, -150),
	}

	for dir_name in directions:
		var player = _create_test_player(Vector2(500, 500))
		add_child_autofree(player)
		await _simulate_frames(2)

		var start = player.position
		for _i in range(5):
			player.velocity = directions[dir_name]
			player.move_and_slide()
			await get_tree().physics_frame

		var delta = player.position - start
		var moved = delta.length()
		gut.p("  %s: moved %.1f px (delta: %s)" % [dir_name, moved, delta])
		assert_gt(moved, 5.0, "Player should move %s" % dir_name)

		player.queue_free()
		await _simulate_frames(1)
