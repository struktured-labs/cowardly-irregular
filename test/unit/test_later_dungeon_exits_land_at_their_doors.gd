extends GutTest

## Leaving three later dungeons dropped you in a named district, not at the door.
##
## Steampunk Mechanism exits to "plaza", the fountain, about 2731px from the
## industrial-district door. Assembly Core still exits to "chemical_zone" after
## that door was moved to a standable tile, about 1295px away. Root Process
## exits to "glitch_sector", the sector landmark, about 1729px from its door.
## Each door only asks for a confirm, so this is not a warp loop. The return
## spawn has to be the door. Debug and crystal warps use TeleportMenu's
## entrance/default for these overworlds and must keep those destinations.

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

const CASES := [
	{
		"world": preload("res://src/exploration/SteampunkOverworld.gd"),
		"dungeon": preload("res://src/maps/dungeons/SteampunkMechanism.gd"),
		"target": "steampunk_mechanism",
		"map": "steampunk_overworld",
		"flag": "w3_entered",
		"label": "Grand Mechanism",
	},
	{
		"world": preload("res://src/exploration/IndustrialOverworld.gd"),
		"dungeon": preload("res://src/maps/dungeons/AssemblyCore.gd"),
		"target": "assembly_core",
		"map": "industrial_overworld",
		"flag": "w4_entered",
		"label": "Assembly Core",
	},
	{
		"world": preload("res://src/exploration/FuturisticOverworld.gd"),
		"dungeon": preload("res://src/maps/dungeons/RootProcess.gd"),
		"target": "root_process",
		"map": "futuristic_overworld",
		"flag": "w5_entered",
		"label": "Root Process",
	},
]

var _saved_flags: Dictionary = {}


func before_each() -> void:
	_saved_flags.clear()
	for case in CASES:
		_saved_flags[case["flag"]] = GameState.is_story_flag_set(case["flag"])


func after_each() -> void:
	for flag in _saved_flags:
		GameState.set_story_flag(flag, _saved_flags[flag])
	SoundState.restore()


func _door(world: Node, target_map: String) -> Node2D:
	var transitions: Node = world.get_node_or_null("Transitions")
	if transitions == null:
		return null
	for child in transitions.get_children():
		if child is AreaTransition and str(child.target_map) == target_map:
			return child
	return null


func _box_of(trans: Node2D) -> Rect2:
	for ch in trans.get_children():
		if ch is CollisionShape2D and (ch as CollisionShape2D).shape is RectangleShape2D:
			var e: Vector2 = ((ch as CollisionShape2D).shape as RectangleShape2D).size
			return Rect2(trans.global_position - e * 0.5, e)
	return Rect2()


func _warp_spawn_for(map_id: String) -> String:
	for dest in TeleportMenu.DESTINATIONS:
		if str(dest["id"]) == map_id:
			return str(dest["spawn"])
	return ""


func _world(script) -> Node:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var world = script.new()
	vp.add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return world


func _leave_and_land(case: Dictionary) -> void:
	var dungeon = case["dungeon"].new()
	var exit_spawn: String = str(dungeon.overworld_exit_spawn)
	var exit_map: String = str(dungeon.overworld_exit_map)
	dungeon.free()
	assert_eq(exit_map, case["map"],
		"%s must exit onto its overworld — this test is about that return" % case["label"])
	assert_ne(exit_spawn, "", "%s must name the spawn it returns to" % case["label"])

	var world = await _world(case["world"])
	var door := _door(world, case["target"])
	assert_not_null(door, "CONTROL: the %s door must exist" % case["label"])
	assert_true(door.require_interaction,
		"the %s door must wait for a confirm, so standing on it is not an auto-warp" % case["label"])
	var fallback: Vector2 = world.player.global_position
	assert_gt(fallback.distance_to(door.global_position), float(world.TILE_SIZE) * 8.0,
		"CONTROL: the default spawn is not the %s door, so ignoring the exit name cannot pass" % case["label"])

	world.spawn_player_at(exit_spawn)

	var landed: Vector2 = world.player.global_position
	assert_lt(landed.distance_to(door.global_position), float(world.TILE_SIZE),
		"leaving the %s via '%s' landed at %s; the door is at %s (%.0fpx away; default spawn was %s)" % [
			case["label"], exit_spawn, str(landed), str(door.global_position),
			landed.distance_to(door.global_position), str(fallback)])
	var transitions: Node = world.get_node("Transitions")
	for child in transitions.get_children():
		if not (child is AreaTransition):
			continue
		if not _box_of(child).has_point(landed):
			continue
		assert_true(child.require_interaction,
			"landing from the %s overlaps '%s', which warps without a confirm" % [case["label"], child.name])


func test_leaving_the_grand_mechanism_puts_you_back_at_its_door() -> void:
	await _leave_and_land(CASES[0])


func test_leaving_the_assembly_core_puts_you_back_at_its_door() -> void:
	await _leave_and_land(CASES[1])


func test_leaving_the_root_process_puts_you_back_at_its_door() -> void:
	await _leave_and_land(CASES[2])


func test_debug_and_crystal_warps_keep_their_overworld_entrances() -> void:
	for case in CASES:
		var warp_spawn := _warp_spawn_for(case["map"])
		assert_true(warp_spawn == "entrance" or warp_spawn == "default",
			"crystal and debug warps to %s use TeleportMenu spawn '%s'" % [case["map"], warp_spawn])
		var world = await _world(case["world"])
		var door := _door(world, case["target"])
		assert_not_null(door, "CONTROL: the %s door must exist" % case["label"])
		assert_true(world.spawn_points.has(warp_spawn),
			"%s is missing the warp spawn '%s'" % [case["map"], warp_spawn])
		var expected: Vector2 = world.spawn_points[warp_spawn]
		world.spawn_player_at(warp_spawn)
		assert_eq(world.player.global_position, expected,
			"warping to %s via '%s' did not land on that spawn" % [case["map"], warp_spawn])
		assert_gt(expected.distance_to(door.global_position), float(world.TILE_SIZE) * 8.0,
			"the %s warp spawn '%s' moved onto the dungeon door" % [case["map"], warp_spawn])
