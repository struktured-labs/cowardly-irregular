extends GutTest

## struktured 2026-11-01 (via cowir-main 21340/21341): the water "looks like just lighting right now". The drawn WATER tile
## carries a moving-surface shader (drift inside its own atlas cell, travelling glints, rings from the village fountain);
## nothing else in the tileset does, and a world with no drawn water is left alone.


func _water_materials(ts: TileSet) -> Array:
	var out: Array = []
	for k in range(ts.get_source_count()):
		var src := ts.get_source(ts.get_source_id(k)) as TileSetAtlasSource
		if src == null:
			continue
		for t in range(src.get_tiles_count()):
			var at := src.get_tile_id(t)
			var td := src.get_tile_data(at, 0)
			if td != null and td.material is ShaderMaterial and (td.material as ShaderMaterial).shader == BaseTileGenerator.WATER_SURFACE_SHADER:
				out.append({"coords": at, "mat": td.material, "grid": src.get_atlas_grid_size()})
	return out


func test_only_the_drawn_water_tile_moves() -> void:
	var gen := TileGenerator.new()
	assert_ne(TileSheetManifest.region("medieval", "tiles", "WATER"), null, "CONTROL: medieval water is a drawn tile")
	var found := _water_materials(gen.create_tileset())
	assert_eq(found.size(), 1, "exactly the one drawn WATER tile carries the water shader (found %d)" % found.size())
	if found.is_empty():
		return
	var f: Dictionary = found[0]
	var g: Vector2i = f["grid"]
	var c: Vector2i = f["coords"]
	var r: Vector4 = (f["mat"] as ShaderMaterial).get_shader_parameter("region")
	assert_almost_eq(r, Vector4(float(c.x) / g.x, float(c.y) / g.y, 1.0 / g.x, 1.0 / g.y), Vector4.ONE * 0.0001, "the shader samples its own atlas cell, not a neighbour's")


func test_a_world_without_drawn_water_keeps_its_tiles_still() -> void:
	var gen := SuburbanTileGenerator.new()
	assert_eq(TileSheetManifest.region("suburban", "tiles", "WATER"), null, "CONTROL: suburban water is still painted")
	assert_eq(_water_materials(gen.create_tileset()).size(), 0, "a painted water tile was given the drawn tile's shader")


func test_harmonias_rings_spread_from_its_fountain() -> void:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var v: Node = (load("res://src/maps/villages/HarmoniaVillage.tscn") as PackedScene).instantiate()
	vp.add_child(v)
	for i in range(4):
		await get_tree().process_frame
	var fountain: Node2D = null
	for n in v.find_children("*", "", true, false):
		if n.get_script() == load("res://src/exploration/VillageFountain.gd"):
			fountain = n
	assert_not_null(fountain, "CONTROL: Harmonia has its fountain")
	var found := _water_materials(v.tile_map.tile_set)
	assert_eq(found.size(), 1, "Harmonia's tileset carries the moving water")
	if fountain == null or found.is_empty():
		return
	var centre: Vector2 = (found[0]["mat"] as ShaderMaterial).get_shader_parameter("ripple_center")
	assert_almost_eq(centre, v.tile_map.to_local(fountain.global_position), Vector2.ONE * 0.5, "the rings do not spread from the fountain")
