extends GutTest

## struktured asked for "visual depth" in the dungeons. Every W1 cave floor cell drew the ONE CAVE_FLOOR atlas tile, so
## its puddle and crystal fleck repeated on an exact 64px grid and a maze floor read as a dotted sheet. Floors now pick
## a variant per cell (stable across rebuilds); walls stay single because HiddenPassage disguises itself as the base wall.

const FireCave := preload("res://src/maps/dungeons/FireDragonCave.gd")

var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true) if GameState else {}


func after_each() -> void:
	if GameState:
		GameState.game_constants = _saved_constants.duplicate(true)


func _cave() -> Node:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var cave = FireCave.new()
	vp.add_child(cave)
	return cave


func _coords_of(cave: Node, tile_type: int) -> Dictionary:
	var gen := TileGenerator.new()
	var order: Array = gen._get_tile_order()
	var cols: int = gen._get_atlas_dimensions().x
	var seen := {}
	for cell in cave.tile_map.get_used_cells():
		var ac: Vector2i = cave.tile_map.get_cell_atlas_coords(cell)
		var idx: int = ac.y * cols + ac.x
		if idx >= 0 and idx < order.size() and order[idx] == tile_type:
			seen[ac] = int(seen.get(ac, 0)) + 1
	return seen


func test_a_cave_floor_uses_several_tiles() -> void:
	var cave := _cave()
	await get_tree().process_frame
	var floors := _coords_of(cave, TileGenerator.TileType.CAVE_FLOOR)
	var cells := 0
	for k in floors:
		cells += int(floors[k])
	assert_gt(cells, 40, "CONTROL: the floor laid real floor cells (%d)" % cells)
	assert_gt(floors.size(), 3, "floor cells draw from several tiles, not one stamp: %s" % str(floors))


func test_the_walls_stay_one_tile_so_a_hidden_passage_still_hides() -> void:
	var cave := _cave()
	await get_tree().process_frame
	var walls := _coords_of(cave, TileGenerator.TileType.CAVE_WALL)
	assert_gt(walls.size(), 0, "CONTROL: the floor has walls")
	assert_eq(walls.size(), 1, "every wall is the base tile HiddenPassage copies: %s" % str(walls))


func test_the_floor_variants_actually_look_different() -> void:
	var gen := TileGenerator.new()
	var ids: Array = TileGenerator.VARIANT_IDS.get(TileGenerator.TileType.CAVE_FLOOR, [])
	assert_gt(ids.size(), 3, "CONTROL: cave floor has variant slots")
	var variants: Dictionary = gen._get_tile_variants()
	var seen := {}
	for id in ids:
		var img := Image.create(TileGenerator.TILE_SIZE, TileGenerator.TILE_SIZE, false, Image.FORMAT_RGBA8)
		gen._draw_tile(img, TileGenerator.TileType.CAVE_FLOOR, TileGenerator.PALETTES[TileGenerator.TileType.CAVE_FLOOR], int(variants.get(id, 0)))
		seen[hash(img.get_data())] = true
	assert_eq(seen.size(), ids.size(), "each variant slot draws a distinct tile")
