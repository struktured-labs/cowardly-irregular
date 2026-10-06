extends GutTest

## Regression (struktured's 2026-10-05 play log, right after door_open + surprised_chime): "ERROR: Can't change this state
## while flushing queries ... at: area_set_shape_disabled". A pressure plate's body_entered ran activate_switch, whose
## rebuild_floor adds trigger areas, inside the physics callback. The plate now defers the switch out of the flush.

const ContrarianDepthsScript = preload("res://src/maps/dungeons/ContrarianDepths.gd")

var _saved_constants: Dictionary = {}
var _saved_forced_encounter: bool = false


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)
	_saved_forced_encounter = EncounterSystem.forced_encounter_next_step


func after_each() -> void:
	GameState.game_constants = _saved_constants.duplicate(true)
	EncounterSystem.forced_encounter_next_step = _saved_forced_encounter


func _cave_on_floor(n: int) -> Node:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var cave = ContrarianDepthsScript.new()
	vp.add_child(cave)
	cave.current_floor = n
	cave._generate_map_for_floor(n)
	return cave


func test_a_plate_switch_fires_after_the_physics_callback_returns() -> void:
	var cave := _cave_on_floor(3)
	await get_tree().process_frame
	EncounterSystem.forced_encounter_next_step = false
	var layer = cave._puzzle_layer
	layer._on_plate_entered(cave.player, "sw3")
	assert_false(bool(layer._active.get("sw3", false)), "the plate must not rebuild the floor inside the physics callback")
	await get_tree().process_frame
	assert_true(bool(layer._active.get("sw3", false)), "the deferred switch still fires on the next idle step")
	assert_true(EncounterSystem.forced_encounter_next_step, "CONTROL: it is the real trap switch (arms the ambush)")


func test_a_non_player_body_still_does_nothing() -> void:
	var cave := _cave_on_floor(3)
	await get_tree().process_frame
	var layer = cave._puzzle_layer
	layer._on_plate_entered(autofree(Node2D.new()), "sw3")
	await get_tree().process_frame
	assert_false(bool(layer._active.get("sw3", false)), "CONTROL: only the player presses a plate")
