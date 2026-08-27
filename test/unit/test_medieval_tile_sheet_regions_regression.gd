extends GutTest

## The shipped medieval sheet must resolve through the real seam off the real PNG.
## region() returns a SILENT null for an absent key, so a mis-registered section name
## falls through to procedural with nothing red — these assert the art is reachable.

const TSM := preload("res://src/exploration/TileSheetManifest.gd")
const MANIFEST := "res://data/sprite_manifest.json"
const KEY := "medieval"
const TILE := 32
const N := 1
const E := 2
const S := 4
const W := 8


func _entry() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_not_null(f, "sprite_manifest.json must be readable")
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	var sheets: Dictionary = data.get("tile_sheets", {})
	return sheets.get(KEY, {})


## Ink in the middle of a side, corners excluded — a full-width lip legitimately
## reaches into the perpendicular bands at the corners.
func _side_ink(img: Image, bit: int) -> int:
	var n := 0
	for i in range(6, TILE - 6):
		for d in range(3):
			var p: Vector2i
			match bit:
				N: p = Vector2i(i, d)
				S: p = Vector2i(i, TILE - 1 - d)
				W: p = Vector2i(d, i)
				_: p = Vector2i(TILE - 1 - d, i)
			if img.get_pixelv(p).a > 0.0:
				n += 1
	return n


func test_medieval_sheet_is_registered() -> void:
	var e := _entry()
	assert_false(e.is_empty(), "tile_sheets.medieval must exist in sprite_manifest.json")
	assert_true(TSM.has_sheet(KEY), "the seam must load the medieval sheet")
	assert_true(ResourceLoader.exists(str(e.get("path", ""))), "sheet PNG must exist: %s" % e.get("path", ""))


## Enumerated from the ENGINE's vocabulary, not from the manifest's own keys: iterating
## e.get("cliff") checks nothing at all if that section is ever renamed, and reports clean.
func test_every_engine_name_resolves_to_real_art() -> void:
	var e := _entry()
	var dead: Array = []
	var expect := {"cliff": TSM.CLIFF_NAMES, "overlay": TSM.OVERLAY_NAMES}
	for section in expect:
		var declared: Dictionary = e.get(section, {})
		assert_eq(declared.size(), (expect[section] as Array).size(),
			"medieval must declare every %s name the engine asks for" % section)
		for name in expect[section]:
			var img: Image = TSM.region(KEY, section, name)
			if img == null:
				dead.append("%s/%s -> null (falls through to procedural)" % [section, name])
				continue
			if img.get_width() != TILE or img.get_height() != TILE:
				dead.append("%s/%s -> %dx%d, expected %dx%d" % [section, name, img.get_width(), img.get_height(), TILE, TILE])
				continue
			var ink := 0
			for y in range(TILE):
				for x in range(TILE):
					if img.get_pixel(x, y).a > 0.0:
						ink += 1
			if ink == 0:
				dead.append("%s/%s -> fully transparent (an empty atlas cell)" % [section, name])
	assert_eq(dead, [], "every declared region must cut real art out of the sheet")


func test_bitmask_regions_are_not_transposed() -> void:
	var e := _entry()
	var wrong: Array = []
	var families := {"cliff": "edge_", "overlay": "fringe_"}
	for section in families:
		for mask in range(1, 16):
			var name: String = "%s%d" % [families[section], mask]
			if not (e.get(section, {}) as Dictionary).has(name):
				continue
			var img: Image = TSM.region(KEY, section, name)
			if img == null:
				wrong.append("%s: null" % name)
				continue
			for bit in [N, E, S, W]:
				var ink := _side_ink(img, bit)
				if (mask & bit) != 0 and ink == 0:
					wrong.append("%s: side %d flagged but blank" % [name, bit])
				if (mask & bit) == 0 and ink > 0:
					wrong.append("%s: side %d unflagged but has %d px" % [name, bit, ink])
	assert_eq(wrong, [], "each edge_N/fringe_N must carry ink on exactly its flagged sides")
