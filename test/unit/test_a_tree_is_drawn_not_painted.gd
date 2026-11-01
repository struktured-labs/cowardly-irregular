extends GutTest

## struktured 2026-11-01: "the trees look procgen too". Every terrain tree tile now draws from its world's tile sheet
## (tile_sheets.<world>.tiles, row 3), not TileGenerator's painted canopy. The corpus is DERIVED: every tree-like
## TileType (FOREST or a name containing TREE) in every world generator, so a tree type added later without art reds.
## Variant 1 of FOREST is the one painted variant a tree has today, so it is pinned by name.

const TSM := preload("res://src/exploration/TileSheetManifest.gd")
const EXTRA_VARIANTS := {"medieval": ["FOREST:1"]}


func before_each() -> void:
	TSM.reset_for_test()


func after_each() -> void:
	TSM.reset_for_test()


## [world, generator, type id, sheet name] for every tree-like tile type any world generator draws.
func _tree_types() -> Array:
	var out: Array = []
	for world in TSM.GENERATOR_KEYS:
		var gen = load(TSM.GENERATOR_KEYS[world]).new()
		autofree(gen)
		for id in range(64):
			var name: String = gen._get_tile_type_name(id)
			if name == "FOREST" or name.contains("TREE"):
				out.append([world, gen, id, name])
	return out


## The pixels the shipped sheet holds at that name, read straight from the manifest and the PNG.
func _sheet_cell(world: String, name: String) -> Image:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var entry: Dictionary = manifest.get("tile_sheets", {}).get(world, {})
	var at: Array = entry.get("tiles", {}).get(name, [])
	if at.size() < 2:
		return null
	var sheet: Image = (load(str(entry["path"])) as Texture2D).get_image()
	return sheet.get_region(Rect2i(int(at[0]) * 32, int(at[1]) * 32, 32, 32))


func _same(a: Image, b: Image) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	return a.get_data() == b.get_data()


func test_every_tree_tile_is_drawn_from_its_sheet() -> void:
	var trees := _tree_types()
	assert_gte(trees.size(), 3, "FLOOR: FOREST, SNOW_TREE and SHADE_TREE must be found in the generators (%d)" % trees.size())
	var painted: Array = []
	for t in trees:
		var drawn: Image = t[1]._artist_tile(t[2], 0)
		if not _same(drawn, _sheet_cell(t[0], t[3])):
			painted.append("%s %s" % [t[0], t[3]])
	assert_eq(painted, [], "these tree tiles are still the painted canopy, not the sheet's art: %s" % [painted])


func test_the_forest_keeps_its_second_tree() -> void:
	## Overworld forests alternate two trees; the second must be drawn too, or every other cell stays procedural.
	for world in EXTRA_VARIANTS:
		var gen = load(TSM.GENERATOR_KEYS[world]).new()
		autofree(gen)
		for full in EXTRA_VARIANTS[world]:
			var parts: PackedStringArray = str(full).split(":")
			var id := -1
			for i in range(64):
				if gen._get_tile_type_name(i) == parts[0]:
					id = i
			assert_gt(id, -1, "CONTROL: %s names %s" % [world, parts[0]])
			var cell := _sheet_cell(world, full)
			assert_not_null(cell, "%s must name %s in its sheet" % [world, full])
			assert_true(_same(gen._artist_tile(id, int(parts[1])), cell), "%s %s must draw from the sheet" % [world, full])
