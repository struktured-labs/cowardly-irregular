extends GutTest

## Climbing out of the Suburban Underground used to drop you across the Mundane Sprawl.
##
## The exit named "entrance", the spot where you arrive from World 1, on the far
## side of the suburb. The storm drain you just climbed out of is
## SuburbanUndergroundEntrance. That name exists, so spawn_player_at does move
## you — it moved you to the wrong place. The door only asks for a confirm, so
## you are not trapped in a warp loop; you are simply a map away from the dungeon
## you were standing in. The return spawn has to be the door.

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const WORLD := preload("res://src/exploration/SuburbanOverworld.gd")
const DUNGEON := preload("res://src/maps/dungeons/SuburbanUnderground.gd")

var _prior_entered: bool = false


func before_each() -> void:
	_prior_entered = GameState.is_story_flag_set("w2_entered")


func after_each() -> void:
	GameState.set_story_flag("w2_entered", _prior_entered)
	SoundState.restore()


func _underground_door(world: Node) -> Node2D:
	var transitions: Node = world.get_node_or_null("Transitions")
	if transitions == null:
		return null
	for child in transitions.get_children():
		if child is AreaTransition and str(child.target_map) == "suburban_underground":
			return child
	return null


func test_leaving_the_suburban_underground_puts_you_back_at_its_door() -> void:
	var dungeon = DUNGEON.new()
	var exit_spawn: String = str(dungeon.overworld_exit_spawn)
	var exit_map: String = str(dungeon.overworld_exit_map)
	dungeon.free()
	assert_eq(exit_map, "suburban_overworld",
		"the Suburban Underground must exit onto the suburban overworld — this test is about that return")
	assert_ne(exit_spawn, "", "the dungeon must name the spawn it returns to")

	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var world = WORLD.new()
	vp.add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var door := _underground_door(world)
	assert_not_null(door,
		"CONTROL: the storm-drain door must exist, or this test measures nothing")
	var fallback: Vector2 = world.player.global_position
	assert_gt(fallback.distance_to(door.global_position), float(world.TILE_SIZE) * 8.0,
		"CONTROL: the default spawn is not the storm drain, so ignoring the exit name cannot pass")

	world.spawn_player_at(exit_spawn)

	var landed: Vector2 = world.player.global_position
	assert_lt(landed.distance_to(door.global_position), float(world.TILE_SIZE),
		"leaving the Suburban Underground via '%s' landed at %s; the door is at %s (default spawn was %s)" % [
			exit_spawn, str(landed), str(door.global_position), str(fallback)])
