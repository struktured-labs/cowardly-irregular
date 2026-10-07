extends GutTest

## Regression (cowir-main's .610 Fire floor 2 / Ice floor 4 frames): the required key was a dull orange diamond on a brown
## floor, the blast charge a dark square that read as a hole, and both locks were thin coloured bars on a wall. Each is
## now a sprite: an outlined gold key, a round bomb with a lit fuse, a bound door with a keyhole, cracks across the wall.

const FireCave := preload("res://src/maps/dungeons/FireDragonCave.gd")
const IceCave := preload("res://src/maps/dungeons/IceDragonCave.gd")

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


func _sprite_role(cave: Node, role: String) -> int:
	var n := 0
	for c in cave._mechanics_layer._container.get_children():
		if not c.is_queued_for_deletion() and str(c.get_meta(&"dm_role", "")) == role and c.get_child_count() > 0 and c.get_child(0) is Sprite2D:
			n += 1
	return n


func test_the_key_and_its_door_read() -> void:
	var cave = await _cave_on(FireCave, 2)
	assert_eq(_sprite_role(cave, "pickup_key"), 1, "the key is drawn as a key sprite")
	assert_eq(_sprite_role(cave, "lock_key"), 1, "its locked door is drawn as a door, not a bar on the wall")


func test_the_charge_and_its_cracked_wall_read() -> void:
	var cave = await _cave_on(IceCave, 4)
	assert_eq(_sprite_role(cave, "pickup_bomb"), 1, "the blast charge is drawn as a bomb, not a dark square")
	assert_eq(_sprite_role(cave, "lock_bomb"), 1, "the cracked wall shows its cracks")
