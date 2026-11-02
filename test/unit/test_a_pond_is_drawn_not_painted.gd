extends GutTest

## struktured 2026-11-01: "any of that old school procgenylooking art needs to go". Medieval WATER (Harmonia's pond,
## the W1 lakes) draws from the world's tile sheet now. Every water cell is the SAME atlas id, so the tile must also
## repeat onto itself: its edge ring is one even colour, so no ripple is cut off where it meets its neighbour.

const TSM := preload("res://src/exploration/TileSheetManifest.gd")


func before_each() -> void:
	TSM.reset_for_test()


func after_each() -> void:
	TSM.reset_for_test()


func _sheet_cell(world: String, name: String) -> Image:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var entry: Dictionary = manifest.get("tile_sheets", {}).get(world, {})
	var at: Array = entry.get("tiles", {}).get(name, [])
	if at.size() < 2:
		return null
	var sheet: Image = (load(str(entry["path"])) as Texture2D).get_image()
	sheet.convert(Image.FORMAT_RGBA8)
	return sheet.get_region(Rect2i(int(at[0]) * 32, int(at[1]) * 32, 32, 32))


func _water_id(gen) -> int:
	for i in range(64):
		if gen._get_tile_type_name(i) == "WATER":
			return i
	return -1


func test_medieval_water_is_drawn_from_its_sheet() -> void:
	var gen = load(TSM.GENERATOR_KEYS["medieval"]).new()
	autofree(gen)
	var id := _water_id(gen)
	assert_gt(id, -1, "CONTROL: the medieval generator names WATER")
	var cell := _sheet_cell("medieval", "WATER")
	assert_not_null(cell, "medieval must name WATER in its sheet")
	var drawn: Image = gen._artist_tile(id, 0)
	assert_not_null(drawn, "medieval WATER must draw from the sheet, not the painted water")
	if drawn != null and cell != null:
		drawn.convert(Image.FORMAT_RGBA8)
		assert_eq(drawn.get_data(), cell.get_data(), "medieval WATER must be the sheet's pixels")


func test_the_water_tile_repeats_onto_itself() -> void:
	var cell := _sheet_cell("medieval", "WATER")
	assert_not_null(cell, "medieval must name WATER in its sheet")
	if cell == null:
		return
	var ring := {}
	for i in range(32):
		for p in [Vector2i(i, 0), Vector2i(i, 31), Vector2i(0, i), Vector2i(31, i)]:
			ring[cell.get_pixelv(p).to_html()] = true
	assert_eq(ring.size(), 1, "the edge ring must be one colour, or a ripple is cut at every tile seam: %s" % [ring.keys()])
	var inside := {}
	for y in range(1, 31):
		for x in range(1, 31):
			inside[cell.get_pixel(x, y).to_html()] = true
	## CONTROL: a tile that is one flat colour passes the ring arm and is still the painted look the directive retires.
	assert_gt(inside.size(), 1, "the water must carry its drawn ripples, not be a flat fill")
