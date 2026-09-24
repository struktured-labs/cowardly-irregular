extends GutTest

## Returning from the Clockwork Dominion drops you across the Mundane Sprawl.
##
## SteampunkOverworld's BackPortal ("Return to the Mundane Sprawl") targets
## suburban_overworld at "entrance". That key is where you arrive from World 1,
## on the far side of the suburb. The portal you just walked out of is the east
## forward portal, and SuburbanOverworld already registers from_industrial one
## tile beside it — the spot the objective arrow and the minimap call the portal.
## "entrance" exists, so spawn_player_at does move you. It moves you to the
## wrong place.

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const W3 := preload("res://src/exploration/SteampunkOverworld.gd")
const W2 := preload("res://src/exploration/SuburbanOverworld.gd")

var _saved_worlds: int = 1
var _saved_w2: bool = false
var _saved_w3: bool = false


func before_each() -> void:
	_saved_worlds = GameState.worlds_unlocked
	_saved_w2 = GameState.get_story_flag("w2_entered")
	_saved_w3 = GameState.get_story_flag("w3_entered")
	GameState.worlds_unlocked = 6


func after_each() -> void:
	GameState.worlds_unlocked = _saved_worlds
	GameState.set_story_flag("w2_entered", _saved_w2)
	GameState.set_story_flag("w3_entered", _saved_w3)
	SoundState.restore()


func _mount(script) -> Node:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var world = script.new()
	vp.add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return world


func _named(world: Node, node_name: String) -> Node2D:
	var transitions: Node = world.get_node_or_null("Transitions")
	if transitions == null:
		return null
	for child in transitions.get_children():
		if str(child.name) == node_name:
			return child
	return null


func test_returning_from_the_clockwork_dominion_lands_beside_its_portal() -> void:
	var w3 = await _mount(W3)
	var back := _named(w3, "BackPortal")
	assert_not_null(back, "W3 must have the portal back to the Mundane Sprawl")
	assert_eq(str(back.target_map), "suburban_overworld",
		"the Clockwork back portal must return to the suburban overworld")
	var spawn_name := str(back.target_spawn)
	assert_ne(spawn_name, "", "the back portal must name the spawn it returns to")

	var w2 = await _mount(W2)
	var door := _named(w2, "WorldPortal")
	assert_not_null(door,
		"CONTROL: with world 3 unlocked the portal to the Clockwork Dominion must exist")
	var fallback: Vector2 = w2.player.global_position
	var beside := float(w2.TILE_SIZE) * 8.0
	assert_gt(fallback.distance_to(door.global_position), beside,
		"CONTROL: the default spawn is not the Clockwork portal, so a no-op spawn cannot pass")

	w2.spawn_player_at(spawn_name)

	var landed: Vector2 = w2.player.global_position
	assert_lt(landed.distance_to(door.global_position), beside,
		"returning via '%s' landed at %s; the Clockwork portal is at %s (default spawn was %s)" % [
			spawn_name, str(landed), str(door.global_position), str(fallback)])
