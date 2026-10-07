extends GutTest

## Regression (cowir-main's .608 Lightning Dragon Cave floor 2 frame): the required push puzzle drew only a plain brown
## square that read as a hole in the floor; its pylon target had no marker and the gate it opens was an ordinary wall.
## The block is now carved stone with a rune, the target a socket, and the closed gate an energy barrier.

const LightningCave := preload("res://src/maps/dungeons/LightningDragonCave.gd")

var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)


func after_each() -> void:
	GameState.game_constants = _saved_constants


func _cave_on_floor_2() -> Node:
	var cave := LightningCave.new()
	add_child_autofree(cave)
	await get_tree().process_frame
	cave.current_floor = 2
	cave._generate_map_for_floor(2)
	await get_tree().process_frame
	return cave


## By role, not node name: a rebuild adds new markers while the old are still queued, so names get uniquified.
func _markers(cave: Node, role: String) -> Array:
	return cave._mechanics_layer._container.get_children().filter(func(n): return not n.is_queued_for_deletion() and str(n.get_meta(&"dm_role", "")) == role)


func test_an_unsolved_puzzle_shows_its_block_target_and_gate() -> void:
	var cave = await _cave_on_floor_2()
	var blocks: Array = cave._mechanics_layer._container.get_children().filter(func(n): return n is DungeonMechanics.PushBlock and not n.is_queued_for_deletion())
	assert_eq(blocks.size(), 1, "SCOPE: floor 2 carries its push block")
	if blocks.size() == 1:
		assert_true(blocks[0].get_node_or_null("Body") is Sprite2D, "the block is drawn as carved stone, not a flat brown square")
	assert_eq(_markers(cave, "block_target").size(), 1, "the pylon socket the block goes on is marked")
	assert_gte(_markers(cave, "block_gate").size(), 1, "the closed gate it opens shows as a barrier, not plain wall")


func test_a_solved_puzzle_drops_its_barrier() -> void:
	var cave = await _cave_on_floor_2()
	cave._mechanics_layer.mark_block_on_target("bp0")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_markers(cave, "block_gate").size(), 0, "once the block is seated the barrier is gone")
	assert_eq(_markers(cave, "block_target").size(), 1, "CONTROL: the socket stays, now lit")
