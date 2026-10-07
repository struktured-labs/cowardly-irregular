extends GutTest

## Regression (2026-10-07): .605 gave every DragonCave a light that follows the player and an ambience layer (drips,
## crystal glints), wired in DragonCave. The Whispering Cave -- the FIRST cave in the game -- extends Node2D, not
## DragonCave, so it shipped without either. It now builds both.

const WhisperingCaveScript := preload("res://src/maps/dungeons/WhisperingCave.gd")

var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)


func after_each() -> void:
	GameState.game_constants = _saved_constants


func test_the_whispering_cave_lights_the_player() -> void:
	var cave = WhisperingCaveScript.new()
	add_child_autofree(cave)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_not_null(cave.lighting, "SCOPE: the cave has its lighting rig")
	var light = cave.lighting._player_light if cave.lighting else null
	assert_not_null(light, "the first cave carries a light that follows the player, as every dragon cave does")
	if light and cave.player:
		assert_lt(light.global_position.distance_to(cave.player.global_position), 4.0, "and it tracks the player")


func test_the_whispering_cave_has_ambience() -> void:
	var cave = WhisperingCaveScript.new()
	add_child_autofree(cave)
	await get_tree().process_frame
	assert_not_null(cave.get("ambience"), "the first cave builds the ambience layer")
	if cave.get("ambience"):
		assert_gt(cave.ambience.get_child_count(), 0, "with ambient props on its floor")
