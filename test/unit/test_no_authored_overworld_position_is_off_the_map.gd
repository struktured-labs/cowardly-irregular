extends GutTest

## An authored coordinate outside the map rect is placed in the void, and NOTHING notices.
##
## FOUND 2026-09-10. W1's only hidden passage and the chest behind it were authored at map cell
## (126, 7) and (126, 5). Authored positions are MAP CELLS -- `pos.x * MAP_SCALE * TILE_SIZE` -- so
## for W1 (MAP_SCALE 2, TILE_SIZE 32, MAP_WIDTH 200 tiles) the grid is 100x70 and x=126 resolves to
## 8080 px against a 6400 px map. Both sat 1680 px EAST of the world, outside the boundary wall.
##
## 🔑 THE REACHABILITY GUARD I WROTE FOR EXACTLY THIS COULD NOT SEE IT. It asks the physics whether
## a body fits at the chest's position. Off the map there are no tiles and no colliders, so the query
## comes back empty and empty reads as STANDABLE. The instrument fails toward PASS precisely where
## the defect is worst. Bounds are a different question from clearance and need their own assertion.
##
## The coordinate came from tools/find_secret_pockets.py, which works in the PNG's TILE grid
## (200x140). Nothing converted it to cells. The comment sitting directly above it warned about this
## exact unit confusion, in the same file, written the same day.

const WORLDS := [
	"res://src/exploration/OverworldScene.gd",
	"res://src/exploration/SuburbanOverworld.gd",
	"res://src/exploration/SteampunkOverworld.gd",
	"res://src/exploration/IndustrialOverworld.gd",
	"res://src/exploration/FuturisticOverworld.gd",
	"res://src/exploration/AbstractOverworld.gd",
]


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "cannot open %s" % path)
	return "" if f == null else f.get_as_text()


func _const_int(src: String, key: String) -> int:
	var re := RegEx.new()
	re.compile("const %s: int = (\\d+)" % key)
	var m := re.search(src)
	return -1 if m == null else int(m.get_string(1))


func test_every_authored_pos_lands_inside_its_own_world() -> void:
	var offenders: Array = []
	var worlds_read := 0
	var positions_checked := 0

	var pos_re := RegEx.new()
	pos_re.compile('"pos":\\s*Vector2\\((\\d+),\\s*(\\d+)\\)')

	for path in WORLDS:
		var src := _read(path)
		if src == "":
			continue
		var scale := _const_int(src, "MAP_SCALE")
		var w := _const_int(src, "MAP_WIDTH")
		var h := _const_int(src, "MAP_HEIGHT")
		assert_gt(scale, 0, "CONTROL: %s declares no MAP_SCALE" % path)
		assert_gt(w, 0, "CONTROL: %s declares no MAP_WIDTH" % path)
		if scale <= 0 or w <= 0 or h <= 0:
			continue
		worlds_read += 1
		# The authored grid is the tile grid divided by MAP_SCALE: that is what the placement
		# formula pos * MAP_SCALE * TILE_SIZE inverts.
		var cells_x := int(w / scale)
		var cells_y := int(h / scale)
		for m in pos_re.search_all(src):
			positions_checked += 1
			var px := int(m.get_string(1))
			var py := int(m.get_string(2))
			if px >= cells_x or py >= cells_y:
				offenders.append("%s (%d,%d) outside %dx%d" % [path.get_file(), px, py, cells_x, cells_y])

	assert_eq(worlds_read, WORLDS.size(), "CONTROL: every overworld must declare its own dimensions")
	assert_gt(positions_checked, 60,
		"CONTROL: only %d authored positions found across six worlds — the scan is broken and the zero below is free" % positions_checked)
	assert_eq(offenders, [], "authored content placed outside its own map: %s" % str(offenders))
