extends GutTest

## A save, a Continue, or a battle return stands you on the portal pad you left. That overlap must not warp you; stepping off and back on still does.

const GameLoopScript := preload("res://src/GameLoop.gd")
const ContrarianDepthsScript := preload("res://src/maps/dungeons/ContrarianDepths.gd")

var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true) if GameState else {}


func after_each() -> void:
	if GameState:
		GameState.game_constants = _saved_constants.duplicate(true)


func _cave() -> Node:
	if GameState:
		GameState.game_constants.erase("backwards_warren_floor")
		GameState.game_constants.erase("backwards_warren_switches")
		GameState.game_constants["meta_dungeon_skip_pending"] = false
	var cave = ContrarianDepthsScript.new()
	add_child_autofree(cave)
	await get_tree().process_frame
	if cave.get("controller") != null:
		cave.controller.encounter_enabled = false
	return cave


func _portal_b(cave: Node) -> Area2D:
	var hits: Array = cave.find_children("Portal_b_*", "Area2D", true, false)
	if hits.size() != 1:
		return null
	return hits[0] as Area2D


func _settle_warp() -> void:
	# puzzle_warp_to keeps timers after the floor has already changed.
	await get_tree().create_timer(1.0).timeout


func test_restoring_onto_a_puzzle_portal_does_not_warp_and_a_later_step_does() -> void:
	var bare = await _cave()
	var open: Area2D = _portal_b(bare)
	assert_not_null(open, "floor 1 of the Backwards Warren must spawn portal b, or a green swallow proved nothing")
	if open == null:
		return
	assert_eq(bare.current_floor, 1)
	var pad: Vector2 = open.global_position
	bare.player.global_position = pad
	for _i in 4:
		await get_tree().physics_frame
	assert_eq(bare.current_floor, 3,
		"control: standing on portal b must warp to floor 3, or a green swallow proved nothing")
	await _settle_warp()
	var cave = await _cave()
	var back_pad: Area2D = _portal_b(cave)
	assert_not_null(back_pad, "the rebuilt floor 1 must spawn portal b again")
	if back_pad == null:
		return
	var back: Vector2 = back_pad.global_position
	cave.player.global_position = back
	var loop := GameLoopScript.new()
	await loop._swallow_return_tile_triggers(cave, cave.player)
	loop.free()
	for _i in 4:
		await get_tree().physics_frame
	assert_eq(cave.current_floor, 1,
		"returning onto the portal pad must not send you through it")
	assert_eq(cave.player.global_position, back,
		"the restore leaves you on the pad you saved on")
	cave.player.position = cave.spawn_points["default"]
	for _i in 3:
		await get_tree().physics_frame
	cave.player.global_position = back
	for _i in 4:
		await get_tree().physics_frame
	assert_eq(cave.current_floor, 3,
		"walking off the portal and back on must still warp — the swallow is only the overlap you spawned inside")
	await _settle_warp()
