extends GutTest

## A synthetic 6x6 village with two tiers and one stair proves the BaseVillage layer build
## end to end: faces paint onto the Cliffs layer and block, stairs paint onto Overlay and
## connect, _can_step carries the height rule, and a village with NO height data is unchanged.

const TILE := 32


class TierVillage extends BaseVillage:
	var height: Array[String] = [
		"WWWWWW",
		"W2222W",
		"W2222W",
		"W1111W",
		"W1111W",
		"WWWWWW",
	]
	var layout: Array[String] = [
		"WWWWWW",
		"WggggW",
		"WggggW",
		"Wg^ggW",
		"WgpggW",
		"WWWWWW",
	]
	var use_height := true
	func _get_area_id() -> String: return "tier_test_village"
	func _get_map_pixel_size() -> Vector2i: return Vector2i(6 * TILE_SIZE, 6 * TILE_SIZE)
	func _generate_map() -> void:
		for y in range(6):
			for x in range(6):
				var ch: String = layout[y][x]
				var t: int = TileGeneratorScript.TileType.WALL if ch == "W" else (TileGeneratorScript.TileType.VILLAGE_PATH if ch in ["p", "^"] else TileGeneratorScript.TileType.VILLAGE_GRASS)
				tile_map.set_cell(Vector2i(x, y), 0, TileGeneratorScript.get_atlas_coords_for_id(TileGeneratorScript.get_tile_id(t)))
		spawn_points["default"] = Vector2(1.5 * TILE, 4.5 * TILE)
		var h: Array[String] = []
		if use_height:
			for r in height:
				h.append(r.replace("W", "0"))
		_build_derived_layers(layout, h)


var _v: TierVillage


func _build(with_height: bool = true) -> TierVillage:
	var v := TierVillage.new()
	v.use_height = with_height
	add_child_autofree(v)
	return v


func test_three_layers_exist_in_order() -> void:
	_v = _build()
	assert_not_null(_v.tile_map)
	assert_not_null(_v.cliff_map)
	assert_not_null(_v.overlay_map)
	assert_eq(_v.cliff_map.name, "Cliffs")
	assert_eq(_v.overlay_map.name, "Overlay")
	assert_lt(_v.tile_map.get_index(), _v.cliff_map.get_index(), "ground under cliffs")
	assert_lt(_v.cliff_map.get_index(), _v.overlay_map.get_index(), "cliffs under overlay")


func test_faces_paint_on_row_3_except_the_stair() -> void:
	_v = _build()
	assert_true(_v._face_cells.has(Vector2i(1, 3)), "face under the ledge")
	assert_true(_v._face_cells.has(Vector2i(3, 3)))
	assert_true(_v._face_cells.has(Vector2i(4, 3)))
	assert_false(_v._face_cells.has(Vector2i(2, 3)), "the stair cell is the connector")
	assert_ne(_v.cliff_map.get_cell_source_id(Vector2i(1, 3)), -1, "face tile painted on Cliffs")
	assert_eq(_v.cliff_map.get_cell_source_id(Vector2i(2, 3)), -1, "nothing on Cliffs at the stair")
	assert_ne(_v.overlay_map.get_cell_source_id(Vector2i(2, 3)), -1, "stair painted on Overlay")


func test_is_cell_walkable_blocks_faces_and_keeps_tiles() -> void:
	_v = _build()
	assert_true(_v._tile_is_open(Vector2i(1, 3)), "the GROUND tile under a face is open grass")
	assert_false(_v._is_cell_walkable(Vector2i(1, 3)), "but the cell is not walkable — the face occupies it")
	assert_true(_v._is_cell_walkable(Vector2i(2, 3)), "stair walkable")
	assert_true(_v._is_cell_walkable(Vector2i(1, 1)), "upper tier walkable")
	assert_false(_v._is_cell_walkable(Vector2i(0, 0)), "perimeter wall")


func test_can_step_matrix() -> void:
	_v = _build()
	assert_true(_v._can_step(Vector2i(1, 1), Vector2i(2, 1)), "along the upper tier")
	assert_true(_v._can_step(Vector2i(2, 2), Vector2i(2, 3)), "down onto the stair")
	assert_true(_v._can_step(Vector2i(2, 3), Vector2i(2, 4)), "off the stair onto the lower tier")
	assert_false(_v._can_step(Vector2i(1, 2), Vector2i(1, 3)), "straight off the ledge is blocked (face)")
	assert_false(_v._can_step(Vector2i(3, 2), Vector2i(3, 3)), "so is the next column")
	assert_false(_v._can_step(Vector2i(1, 1), Vector2i(0, 1)), "into a wall")


func test_village_without_height_data_has_empty_derived_layers() -> void:
	_v = _build(false)
	assert_eq(_v._face_cells.size(), 0)
	assert_eq(_v.cliff_map.get_used_cells().size(), 0, "no cliffs without height data")
	assert_true(_v._is_cell_walkable(Vector2i(1, 3)), "flat village: every open tile walkable")
	assert_true(_v._can_step(Vector2i(1, 2), Vector2i(1, 3)), "flat village: every open step legal")
