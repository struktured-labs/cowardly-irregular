extends GutTest

## create_tileset consults the artist sheet per (type, variant) and draws procedurally for
## everything the sheet does not name. Pins: a named tile is the sheet's pixels, its variant is
## addressed by NAME:N, an unnamed neighbour stays procedural, and a keyless generator never looks.

const TSM := preload("res://src/exploration/TileSheetManifest.gd")
const TG := preload("res://src/exploration/TileGenerator.gd")
const PATH := "res://fake/medieval.png"


func after_each() -> void:
	TSM.reset_for_test()


func _sheet() -> Image:
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	img.fill_rect(Rect2i(32, 0, 32, 32), Color.CYAN)
	return img


func _atlas_pixel(ts: TileSet, id: int) -> Color:
	var src := ts.get_source(ts.get_source_id(0)) as TileSetAtlasSource
	var img := src.texture.get_image()
	return img.get_pixel((id % 5) * 32 + 16, (id / 5) * 32 + 16)


func test_named_tiles_come_from_the_sheet_and_the_rest_stay_procedural() -> void:
	TSM.set_for_test({"medieval": {"path": PATH, "tiles": {"VILLAGE_GRASS": [0, 0], "VILLAGE_GRASS:1": [1, 0]}}}, {PATH: _sheet()})
	var gen := TG.new()
	autofree(gen)
	assert_eq(gen._get_sheet_key(), "medieval")
	assert_eq(gen._get_tile_type_name(TG.TileType.VILLAGE_GRASS), "VILLAGE_GRASS")
	var ts := gen.create_tileset()
	assert_eq(_atlas_pixel(ts, 30), Color.MAGENTA, "base grass (id 30) is the sheet's cell")
	assert_eq(_atlas_pixel(ts, 35), Color.CYAN, "grass variant 1 (id 35) is addressed as VILLAGE_GRASS:1")
	assert_ne(_atlas_pixel(ts, 31), Color.MAGENTA, "path (id 31) is unnamed — procedural")
	assert_ne(_atlas_pixel(ts, 39), Color.MAGENTA, "grass variant 2 is unnamed — procedural")


func test_every_world_generator_has_a_sheet_key_and_names_its_types() -> void:
	for key in TSM.GENERATOR_KEYS:
		var gen = load(TSM.GENERATOR_KEYS[key]).new()
		autofree(gen)
		assert_eq(gen._get_sheet_key(), key, "%s generator answers to its manifest key" % key)
		assert_ne(gen._get_tile_type_name(0), "", "%s names its first tile type" % key)
		assert_eq(gen._get_tile_type_name(999), "", "%s: out-of-range type has no name" % key)


func test_keyless_generator_never_consults_the_sheet() -> void:
	TSM.set_for_test({"medieval": {"path": PATH, "tiles": {"VILLAGE_GRASS": [0, 0]}}}, {PATH: _sheet()})
	var base := BaseTileGenerator.new()
	autofree(base)
	assert_null(base._artist_tile(0, 0), "no key, no lookup")
