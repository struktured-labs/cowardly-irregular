extends GutTest

## struktured asked for "visual depth" in the dungeons. Every W1 cave floor cell drew the ONE CAVE_FLOOR atlas tile, so
## its puddle and crystal fleck repeated on an exact 64px grid and a maze floor read as a dotted sheet (W2's storm drain:
## one blue puddle per tile). Floors now pick
## a variant per cell (stable across rebuilds); walls too, since HiddenPassage draws its own disguise.

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


func test_the_walls_vary_too() -> void:
	# HiddenPassage draws its own procedural disguise (with a deliberate crack tell), never the atlas wall, so walls can vary.
	var cave := _cave()
	await get_tree().process_frame
	var walls := _coords_of(cave, TileGenerator.TileType.CAVE_WALL)
	assert_gt(walls.size(), 3, "wall cells draw from several tiles, not one stamp: %s" % str(walls))


func test_every_wall_variant_blocks_movement() -> void:
	var gen := TileGenerator.new()
	var ts: TileSet = gen.create_tileset()
	var atlas: TileSetAtlasSource = ts.get_source(ts.get_source_id(0))
	var cols: int = gen._get_atlas_dimensions().x
	var ids: Array = TileGenerator.VARIANT_IDS.get(TileGenerator.TileType.CAVE_WALL, [])
	assert_gt(ids.size(), 3, "CONTROL: cave wall has variant slots to check")
	for id in ids:
		var td: TileData = atlas.get_tile_data(Vector2i(id % cols, id / cols), 0)
		assert_gt(td.get_collision_polygons_count(0) if td else 0, 0, "wall slot %d carries collision" % id)


func test_the_floor_variants_actually_look_different() -> void:
	var gen := TileGenerator.new()
	var order: Array = gen._get_tile_order()
	var variants: Dictionary = gen._get_tile_variants()
	for t in [TileGenerator.TileType.CAVE_FLOOR, TileGenerator.TileType.SUBURBAN_FLOOR, TileGenerator.TileType.CAVE_WALL]:
		var ids: Array = TileGenerator.VARIANT_IDS.get(t, [])
		assert_gt(ids.size(), 2, "CONTROL: floor %d has variant slots" % t)
		var seen := {}
		for id in ids:
			assert_eq(order[id], t, "slot %d holds the floor it is listed for" % id)
			var img := Image.create(TileGenerator.TILE_SIZE, TileGenerator.TILE_SIZE, false, Image.FORMAT_RGBA8)
			gen._draw_tile(img, t, TileGenerator.PALETTES[t], int(variants.get(id, 0)))
			seen[hash(img.get_data())] = true
		assert_eq(seen.size(), ids.size(), "each variant slot of floor %d draws a distinct tile" % t)


func test_a_storm_drain_floor_uses_several_tiles() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var cave = load("res://src/maps/dungeons/SuburbanUnderground.gd").new()
	vp.add_child(cave)
	await get_tree().process_frame
	var floors := _coords_of(cave, TileGenerator.TileType.SUBURBAN_FLOOR)
	assert_gt(floors.size(), 2, "the W2 storm drain's floor draws from several tiles: %s" % str(floors))
