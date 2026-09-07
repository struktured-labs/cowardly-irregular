extends GutTest

## Runtime probe for the 2026-07-25 playtest report:
## "got stuck in castle harmonia btw, you cant go up or down any labeled place
##  in the dungeon/village modes. seems busted tbh."
##
## test_dungeon_stairs_reachable_regression already pins the STRUCTURE (markers
## present, tiles walkable, sensors built, mask correct, handlers wired, latch
## released) and all of it passes — so reading the source says the stairs work.
## That is exactly the situation where a source pin stops being evidence.
##
## This instantiates the real CastleHarmonia, ticks physics, and drives the
## player onto the actual staircase, following the tavern-exit test's pattern:
## its own SubViewport/World2D so a leaked body from an unrelated test can't
## overlap our sensors, and explicit input release because the Input singleton
## is not reset between GUT tests.

const CastleScript = preload("res://src/maps/dungeons/CastleHarmonia.gd")
const TILE := 32
const _DIRECTIONS := ["ui_up", "ui_down", "ui_left", "ui_right"]

var _viewport: SubViewport


func before_each() -> void:
	for a in _DIRECTIONS:
		Input.action_release(a)
	_viewport = SubViewport.new()
	_viewport.world_2d = World2D.new()
	add_child(_viewport)


func after_each() -> void:
	_viewport.queue_free()
	for a in _DIRECTIONS:
		Input.action_release(a)


func _find(castle, node_name: String) -> Area2D:
	if castle.transitions == null:
		return null
	for t in castle.transitions.get_children():
		if t.name == node_name and t is Area2D:
			return t
	return null


func _build() -> Node2D:
	var castle = CastleScript.new()
	_viewport.add_child(castle)
	await get_tree().process_frame
	await get_tree().process_frame
	return castle


func test_castle_builds_stair_sensors_on_the_starting_floor() -> void:
	var castle = await _build()

	assert_true(castle.spawn_points.has("stairs_up"),
		"floor %d parsed no 'U' marker — nothing to walk onto to ascend" % castle.current_floor)

	var up := _find(castle, "StairsUp")
	assert_not_null(up, "a StairsUp Area2D must exist on the starting floor")
	if up != null:
		assert_eq(up.global_position, castle.spawn_points["stairs_up"],
			"the sensor must sit ON the marker the stair sprite is drawn at — an offset "
			+ "sensor is the 'I'm standing on it and nothing happens' report")
		assert_true(up.monitoring, "a non-monitoring Area2D never emits body_entered")
		assert_eq(up.collision_mask & 2, 2,
			"sensor must mask the player's collision_layer (2) or it can never see them")
		assert_gt(up.get_child_count(), 0, "sensor needs a CollisionShape2D or it has no extent")

	castle.free()


func test_walking_onto_the_up_stairs_changes_floor() -> void:
	# The actual repro path. If this passes, "can't go up" is not the dungeon.
	var castle = await _build()
	var start_floor: int = castle.current_floor
	var up := _find(castle, "StairsUp")
	if up == null:
		fail_test("no StairsUp sensor to walk onto")
		castle.free()
		return

	# Settle through the fade-in-equivalent window before walking.
	for i in range(10):
		await get_tree().physics_frame

	var floors: Array = []
	castle.floor_changed.connect(func(f): floors.append(f))

	# Walk in from a tile away so we cross the sensor boundary rather than
	# spawning inside it (an overlap that already exists at _ready may not
	# emit body_entered at all).
	var target: Vector2 = up.global_position
	var origin: Vector2 = target + Vector2(0, 2 * TILE)
	var steps := 24
	for i in range(steps + 1):
		castle.player.position = origin.lerp(target, float(i) / steps)
		await get_tree().physics_frame

	# _transition_to_floor awaits a 0.3s timer before completing; hold on the
	# sensor until the signal lands or a generous cap (condition-based, per the
	# 2026-07-18 flake note on the tavern test).
	var settle := 0
	while floors.is_empty() and settle < 120:
		settle += 1
		castle.player.position = target
		await get_tree().physics_frame

	assert_false(floors.is_empty(),
		"walking onto the up-stairs emitted no floor_changed — the player is standing on the "
		+ "sensor and nothing fires, which is the 'stuck in castle harmonia' report")
	if not floors.is_empty():
		assert_eq(floors[0], start_floor + 1,
			"ascending must go UP exactly one floor (from %d)" % start_floor)

	castle.free()


func test_stair_sensor_does_not_self_fire_before_the_player_arrives() -> void:
	# The mirror failure: a sensor that fires at spawn burns the transition
	# while the player is elsewhere, and _transitioning gates every later use.
	var castle = await _build()
	var floors: Array = []
	castle.floor_changed.connect(func(f): floors.append(f))

	# Park the player away from both staircases and idle.
	var up := _find(castle, "StairsUp")
	if up != null:
		castle.player.position = up.global_position + Vector2(6 * TILE, 6 * TILE)
	for i in range(30):
		await get_tree().physics_frame

	assert_true(floors.is_empty(),
		"floor changed with the player parked away from the stairs — a self-firing sensor "
		+ "spends the transition and leaves the real staircase inert")
	assert_false(castle._transitioning,
		"_transitioning must be clear while idle, or every staircase is dead for the session")

	castle.free()
