extends GutTest

## Leaving the Vertex Apex drops you at the south entrance of the abstract overworld.
##
## VertexApex.overworld_exit_spawn is "apex". AbstractOverworld never registered that
## key, and spawn_player_at ignores a name it does not have, so the player stays on
## the default spawn — the world's south entrance, a full map away from the door
## they just walked out of. The door itself only appears after world6_chapter3, which
## is the only time anyone can be inside the Apex to leave it.

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const WORLD := preload("res://src/exploration/AbstractOverworld.gd")
const APEX := preload("res://src/maps/dungeons/VertexApex.gd")

var _prior_chapter: bool = false
var _prior_entered: bool = false


func before_each() -> void:
	_prior_chapter = GameState.is_story_flag_set("world6_chapter3_complete")
	_prior_entered = GameState.is_story_flag_set("w6_entered")
	GameState.set_story_flag("world6_chapter3_complete", true)


func after_each() -> void:
	GameState.set_story_flag("world6_chapter3_complete", _prior_chapter)
	GameState.set_story_flag("w6_entered", _prior_entered)
	SoundState.restore()


func _apex_door(world: Node) -> Node2D:
	var transitions: Node = world.get_node_or_null("Transitions")
	if transitions == null:
		return null
	for child in transitions.get_children():
		if child is AreaTransition and str(child.target_map) == "vertex_apex":
			return child
	return null


func test_leaving_the_apex_puts_you_back_at_its_door() -> void:
	var apex = APEX.new()
	var exit_spawn: String = str(apex.overworld_exit_spawn)
	var exit_map: String = str(apex.overworld_exit_map)
	apex.free()
	assert_eq(exit_map, "abstract_overworld",
		"the Apex must exit onto the abstract overworld — this test is about that return")
	assert_ne(exit_spawn, "", "the Apex must name the spawn it returns to")

	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var world = WORLD.new()
	vp.add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var door := _apex_door(world)
	assert_not_null(door,
		"CONTROL: with world6_chapter3_complete the Apex door must exist, or this test measures nothing")
	var fallback: Vector2 = world.player.global_position
	assert_gt(fallback.distance_to(door.global_position), float(world.TILE_SIZE) * 8.0,
		"CONTROL: the default spawn is not the Apex door, so ignoring the exit name cannot pass")

	world.spawn_player_at(exit_spawn)

	var landed: Vector2 = world.player.global_position
	assert_lt(landed.distance_to(door.global_position), float(world.TILE_SIZE),
		"leaving the Vertex Apex via '%s' landed at %s; the door is at %s (default spawn was %s)" % [
			exit_spawn, str(landed), str(door.global_position), str(fallback)])
