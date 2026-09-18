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


## ⛔ THIS FILE DRIVES A REAL CharacterBody2D, AND OverworldPlayer._physics_process READS Input.
## Every `await _simulate_frames()` hands the player its own physics tick, so an action left HELD
## by any earlier file in the process steers it: the test sets velocity, the leaked hold adds to
## it, and the player walks through the wall the assertion is about. CLAUDE.md records this as
## already measured once (24px drift, 2026-07-18). Reproduced on this file before fixing it:
##
##   held ui_down    Failing 1   "[275.0] expected to be < than [264.0]: Player should stop before wall"
##   held ui_up      Failing 2
##   held ui_left    Failing 2
##   held ui_right   PASSES — the test already pushes right, so the leak pushes the same way
##
## ⚠️ NOTHING IN THE SUITE LEAKS AN ACTION TODAY — all 41 files that press Input measured clean —
## so this is prophylactic. It is still the cheap side of the trade: the polluter population grows
## with every new input test, while the victim set is the four files that drive a physics body.
func _release_all_actions() -> void:
	for action in InputMap.get_actions():
		Input.action_release(action)
	## parse_input_event QUEUES — measured: a joypad press is invisible to is_joy_button_pressed
	## until a frame is processed, and flush is the synchronous way to force it.
	Input.flush_buffered_events()


func before_each() -> void:
	_release_all_actions()


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


## The defence driven rather than asserted structurally: arm the exact hazard that broke this file,
## release it, and require the wall test's own conclusion to survive. Hollowing out
## _release_all_actions reds this arm, because the hold then steers the player through the wall.
func test_a_held_direction_does_not_steer_the_player() -> void:
	Input.action_press("ui_down")
	Input.flush_buffered_events()
	assert_true(Input.is_action_pressed("ui_down"),
		"CONTROL: the hazard must actually be armed, or the release below clears nothing and " +
		"this arm passes for the wrong reason")

	_release_all_actions()
	assert_false(Input.is_action_pressed("ui_down"), "the entry release must clear an inherited hold")

	var player = _create_test_player(Vector2(200, 200))
	add_child_autofree(player)
	var wall = _create_wall_body(Vector2(264, 200), Vector2(TILE_SIZE, TILE_SIZE * 3))
	add_child_autofree(wall)
	await _simulate_frames(2)
	for _i in range(30):
		player.velocity = Vector2(150, 0)
		player.move_and_slide()
		await get_tree().physics_frame

	assert_lt(player.position.x, 264.0,
		"a released hold must not steer the player: x=%.1f, wall at 264" % player.position.x)
	assert_gt(player.position.x, 220.0, "CONTROL: the player must still have walked into the wall")
