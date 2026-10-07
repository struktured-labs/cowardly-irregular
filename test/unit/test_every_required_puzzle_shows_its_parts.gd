extends GutTest

## Regression (cowir-main's .609 Fire floor 3 / Shadow floor 2 frames): the required timed plate was a flat orange
## square, its gate read as plain wall until opened, and the mirror lever was a dark purple square. Each now draws
## a part a player can read: a flame-glyph plate, a burning barrier on the closed gate, a framed mirror.

const FireCave := preload("res://src/maps/dungeons/FireDragonCave.gd")
const ShadowCave := preload("res://src/maps/dungeons/ShadowDragonCave.gd")

var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)


func after_each() -> void:
	GameState.game_constants = _saved_constants


func _cave_on(script: GDScript, floor_num: int) -> Node:
	var cave = script.new()
	add_child_autofree(cave)
	await get_tree().process_frame
	cave.current_floor = floor_num
	cave._generate_map_for_floor(floor_num)
	await get_tree().process_frame
	return cave


func _role(cave: Node, role: String) -> Array:
	return cave._mechanics_layer._container.get_children().filter(func(n): return not n.is_queued_for_deletion() and str(n.get_meta(&"dm_role", "")) == role)


func test_the_timed_plate_and_its_closed_gate_read() -> void:
	var cave = await _cave_on(FireCave, 3)
	var plates := _role(cave, "timed_plate")
	assert_eq(plates.size(), 1, "the timed plate is marked as a plate")
	if plates.size() == 1:
		assert_true(plates[0].get_child(0) is Sprite2D, "drawn as a stone plate, not a flat square")
	var gates := _role(cave, "timed_gate")
	assert_gte(gates.size(), 1, "SCOPE: the timed gate exists")
	if gates.size() > 0:
		await get_tree().process_frame
		assert_true(gates[0]._barrier.visible, "a closed timed gate burns as a barrier instead of reading as wall")


func test_the_mirror_lever_reads() -> void:
	var cave = await _cave_on(ShadowCave, 2)
	var mirrors := _role(cave, "mirror")
	assert_eq(mirrors.size(), 1, "the mirror lever is marked")
	if mirrors.size() == 1:
		assert_true(mirrors[0].get_child(0) is Sprite2D, "drawn as a framed mirror, not a dark square")
