extends GutTest

## The artist tile-sheet seam. Regions come out of an injected in-memory sheet (no disk), an
## unnamed tile is a SILENT null (partial sets are the contract), an unusable region WARNS and
## falls through, and validate() is a real discriminator: clean on the shipped manifest,
## loud on a fabricated bad entry.

const TSM := preload("res://src/exploration/TileSheetManifest.gd")
const PATH := "res://fake/medieval.png"


func _sheet(w_tiles: int = 4, h_tiles: int = 2) -> Image:
	var img := Image.create(w_tiles * 32, h_tiles * 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	img.fill_rect(Rect2i(32, 0, 32, 32), Color.CYAN)
	return img


func _inject(entry: Dictionary) -> void:
	entry["path"] = PATH
	TSM.set_for_test({"medieval": entry}, {PATH: _sheet()})


func after_each() -> void:
	TSM.reset_for_test()


func test_region_cuts_the_named_cell() -> void:
	_inject({"tiles": {"VILLAGE_GRASS": [0, 0], "VILLAGE_GRASS:1": [1, 0]}})
	var a := TSM.region("medieval", "tiles", "VILLAGE_GRASS")
	assert_not_null(a)
	assert_eq(a.get_size(), Vector2i(32, 32))
	assert_eq(a.get_pixel(5, 5), Color.MAGENTA)
	assert_eq(TSM.region("medieval", "tiles", "VILLAGE_GRASS:1").get_pixel(5, 5), Color.CYAN, "variant name addresses its own cell")


func test_unnamed_or_unknown_is_a_silent_null() -> void:
	_inject({"tiles": {"VILLAGE_GRASS": [0, 0]}})
	assert_null(TSM.region("medieval", "tiles", "VILLAGE_PATH"), "one-entry sheet: other tiles fall through")
	assert_null(TSM.region("medieval", "cliff", "face"), "absent section falls through")
	assert_null(TSM.region("suburban", "tiles", "VILLAGE_GRASS"), "absent sheet falls through")
	assert_null(TSM.region("", "tiles", "VILLAGE_GRASS"), "empty key never consults the manifest")


func test_out_of_bounds_region_falls_through() -> void:
	_inject({"tiles": {"VILLAGE_GRASS": [9, 9]}})
	assert_null(TSM.region("medieval", "tiles", "VILLAGE_GRASS"), "region outside the 128x64 sheet is refused")


func test_props_use_multi_tile_regions() -> void:
	_inject({"props": {"TREE": [0, 0, 1, 2]}})
	var img := TSM.region("medieval", "props", "TREE", Vector2i(1, 3))
	assert_not_null(img)
	assert_eq(img.get_size(), Vector2i(32, 64), "explicit [w,h] wins over the caller's size hint")


func test_validate_is_clean_on_the_shipped_manifest_and_loud_on_a_bad_entry() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TSM.MANIFEST_PATH))
	assert_true(parsed is Dictionary and parsed.has("tile_sheets"), "sprite_manifest.json carries a tile_sheets section")
	var real: Array = TSM.validate(parsed["tile_sheets"])
	assert_eq(real.size(), 0, "shipped tile_sheets validate clean:\n  %s" % "\n  ".join(real))
	var bad := {"medieval": {"path": PATH, "tiles": {"NOT_A_TILE": [0, 0], "VILLAGE_GRASS": [40, 0]}, "props": {"TREE": [0, 0]}, "cliff": {"face": [0, 1]}},
		"mars": {"path": PATH}}
	var problems: Array = TSM.validate(bad, {PATH: _sheet()})
	assert_eq(problems.size(), 4, "unknown tile name + out-of-bounds + prop without w,h + unknown sheet key:\n  %s" % "\n  ".join(problems))
