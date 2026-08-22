extends GutTest

## Encounter zones must follow the PAINTED biome, not absolute tile rectangles:
## the old rects were tuned to 100x70 and distort at any other size.

const SceneScript = preload("res://src/exploration/OverworldScene.gd")


func _scene() -> Node:
	var s = SceneScript.new()
	add_child_autofree(s)
	await wait_frames(2)
	return s


func test_biome_char_at_returns_the_painted_character() -> void:
	var scene = await _scene()
	assert_gt(scene.map_rows.size(), 0, "map_rows must be populated -- otherwise every assert below is vacuous")
	assert_eq(scene.map_rows.size(), scene.MAP_HEIGHT, "one row per map row")
	assert_eq(scene.biome_char_at(0, 0).length(), 1, "a single painted character")
	assert_eq(scene.biome_char_at(-1, 0), "", "out of bounds west is empty")
	assert_eq(scene.biome_char_at(scene.MAP_WIDTH, 0), "", "out of bounds east is empty")
	assert_eq(scene.biome_char_at(0, scene.MAP_HEIGHT), "", "out of bounds south is empty")
