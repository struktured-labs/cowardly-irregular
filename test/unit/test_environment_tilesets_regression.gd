extends GutTest

## The two derived-layer tilesets. Collision geometry is the contract: a mask tile carries
## exactly one 4px strip per set bit on the matching side, the face blocks the whole cell,
## and nothing on the overlay sheet blocks anything.

const ETS := preload("res://src/exploration/EnvironmentTileSets.gd")
const HG := preload("res://src/exploration/HeightGrid.gd")


func _source(ts: TileSet) -> TileSetAtlasSource:
	return ts.get_source(ts.get_source_id(0)) as TileSetAtlasSource


func test_cliff_tileset_has_17_tiles_and_a_physics_layer() -> void:
	var ts := ETS.build_cliff_tileset()
	assert_eq(ts.get_physics_layers_count(), 1)
	assert_eq(ts.get_physics_layer_collision_layer(0), 1, "walls live on physics layer 1 (player mask)")
	var src := _source(ts)
	assert_eq(src.get_tiles_count(), 17)
	for id in range(17):
		assert_true(src.has_tile(ETS.atlas_coords(id)), "tile %d present" % id)


func test_mask_tiles_carry_one_strip_per_bit_on_the_right_side() -> void:
	var src := _source(ETS.build_cliff_tileset())
	var half := ETS.TILE / 2.0
	for mask in range(16):
		var td := src.get_tile_data(ETS.atlas_coords(mask), 0)
		var bits := 0
		for b in [1, 2, 4, 8]:
			if mask & b:
				bits += 1
		assert_eq(td.get_collision_polygons_count(0), bits, "mask %d has %d strips" % [mask, bits])
	# Side check on the single-bit tiles: every vertex of the N strip sits in the top 4px, etc.
	var checks := {HG.EDGE_N: func(p: Vector2) -> bool: return p.y <= -half + ETS.EDGE_THICKNESS,
		HG.EDGE_S: func(p: Vector2) -> bool: return p.y >= half - ETS.EDGE_THICKNESS,
		HG.EDGE_W: func(p: Vector2) -> bool: return p.x <= -half + ETS.EDGE_THICKNESS,
		HG.EDGE_E: func(p: Vector2) -> bool: return p.x >= half - ETS.EDGE_THICKNESS}
	for bit in checks:
		var td := src.get_tile_data(ETS.atlas_coords(bit), 0)
		for p in td.get_collision_polygon_points(0, 0):
			assert_true(checks[bit].call(p), "bit %d vertex %s on its side" % [bit, p])


func test_mask_zero_and_face() -> void:
	var src := _source(ETS.build_cliff_tileset())
	assert_eq(src.get_tile_data(ETS.atlas_coords(0), 0).get_collision_polygons_count(0), 0, "mask 0 is inert")
	var face := src.get_tile_data(ETS.atlas_coords(ETS.FACE_ID), 0)
	assert_eq(face.get_collision_polygons_count(0), 1)
	var pts := face.get_collision_polygon_points(0, 0)
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	assert_eq(r.size, Vector2(ETS.TILE, ETS.TILE), "face blocks the whole cell")


func test_overlay_tileset_is_walkable_everywhere() -> void:
	var ts := ETS.build_overlay_tileset()
	var src := _source(ts)
	assert_eq(src.get_tiles_count(), 19)
	for id in range(19):
		assert_eq(src.get_tile_data(ETS.atlas_coords(id), 0).get_collision_polygons_count(0), 0, "overlay %d never blocks" % id)


func test_face_and_stair_tiles_are_not_blank() -> void:
	var cliff := _source(ETS.build_cliff_tileset()).texture.get_image()
	var face_px := cliff.get_pixel(ETS.FACE_ID * ETS.TILE + 16, 16)
	assert_gt(face_px.a, 0.9, "face tile is painted")
	var overlay := _source(ETS.build_overlay_tileset()).texture.get_image()
	var stair_px := overlay.get_pixel(ETS.STAIR_ID * ETS.TILE + 16, 16)
	assert_gt(stair_px.a, 0.9, "stair tile is painted")
	var blank := overlay.get_pixel(16, 16)
	assert_eq(blank.a, 0.0, "fringe mask 0 is transparent in the middle")


func test_artist_cliff_piece_replaces_pixels_but_never_colliders() -> void:
	const TSM := preload("res://src/exploration/TileSheetManifest.gd")
	var sheet := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.MAGENTA)
	TSM.set_for_test({"medieval": {"path": "res://fake/m.png", "cliff": {"face": [0, 0]}, "overlay": {"stair": [0, 0]}}}, {"res://fake/m.png": sheet})
	var cliff := _source(ETS.build_cliff_tileset({}, "medieval"))
	var img := cliff.texture.get_image()
	assert_eq(img.get_pixel(ETS.FACE_ID * ETS.TILE + 16, 16), Color.MAGENTA, "face is the artist cell")
	assert_ne(img.get_pixel(1 * ETS.TILE + 1, 1), Color.MAGENTA, "edge_1 unnamed — procedural")
	assert_eq(cliff.get_tile_data(ETS.atlas_coords(ETS.FACE_ID), 0).get_collision_polygons_count(0), 1, "art never changes collision")
	var overlay := _source(ETS.build_overlay_tileset({}, "medieval"))
	assert_eq(overlay.texture.get_image().get_pixel(ETS.STAIR_ID * ETS.TILE + 16, 16), Color.MAGENTA, "stair is the artist cell")
	assert_ne(_source(ETS.build_cliff_tileset()).texture.get_image().get_pixel(ETS.FACE_ID * ETS.TILE + 16, 16), Color.MAGENTA, "no key: procedural")
	TSM.reset_for_test()
