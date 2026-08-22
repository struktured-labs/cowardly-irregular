extends RefCounted
## Shared SOURCE parser for village grids so every source-level geometry audit reads map_data, height_data and the legend the same way.

const HG := preload("res://src/exploration/HeightGrid.gd")
const MAP_ANCHOR := "var map_data: Array[String] = ["
const HEIGHT_ANCHOR := "var height_data: Array[String] = ["


static func _rows_after(src: String, anchor: String) -> Array:
	var start := src.find(anchor)
	if start < 0:
		return []
	var open := start + anchor.length()
	var block := src.substr(open, src.find("]", open) - open)
	var out: Array = []
	for m in RegEx.create_from_string("\"([^\"]+)\"").search_all(block):
		out.append(m.get_string(1))
	return out


static func rows(src: String) -> Array:
	return _rows_after(src, MAP_ANCHOR)


static func height_rows(src: String) -> Array:
	return _rows_after(src, HEIGHT_ANCHOR)


static func grid(src: String) -> Array:
	return HG.parse(height_rows(src))


static func stairs(src: String) -> Dictionary:
	return HG.stair_cells(rows(src))


## Impassable TileType names for whichever generators a village's legend actually names.
## W2-W6 villages paint with their own world's generator (CrossCode phase 4), so a hardcoded
## medieval list parses their legends as ZERO blocking chars and every flood fill downstream
## goes vacuous. Derived from each generator's own _get_impassable_types(), never a hand-list:
## for the medieval generator the derived set is byte-identical to the list callers passed.
static func derived_impassable(src: String) -> Array:
	var out: Array = []
	var seen := {}
	var re := RegEx.create_from_string("(\\w*)TileGeneratorScript\\.TileType\\.")
	for m in re.search_all(src):
		seen[m.get_string(1)] = true
	for prefix in seen:
		var path := "res://src/exploration/%sTileGenerator.gd" % prefix
		if not ResourceLoader.exists(path):
			continue
		var gsrc := FileAccess.get_file_as_string(path)
		var start := gsrc.find("func _get_impassable_types")
		if start < 0:
			continue
		var stop := gsrc.find("\nfunc ", start + 1)
		var body := gsrc.substr(start, (stop - start) if stop > -1 else gsrc.length() - start)
		var tre := RegEx.create_from_string("TileType\\.([A-Z_]+)")
		for tm in tre.search_all(body):
			out.append(tm.get_string(1))
	return out


static func blocked_chars(src: String, impassable_types: Array) -> Dictionary:
	var types: Array = impassable_types + derived_impassable(src)
	var b := {}
	var ch := RegEx.create_from_string("\"(.)\"")
	for line in src.split("\n"):
		if not (line.contains("return") and line.contains("TileType.")):
			continue
		var blocking := false
		for t in types:
			if line.contains("TileType." + t):
				blocking = true
				break
		if not blocking:
			continue
		for m in ch.search_all(line):
			b[m.get_string(1)] = true
	return b


## Derived face cells for a source file (empty for flat villages).
static func face_cells(src: String, impassable_types: Array) -> Dictionary:
	var g := grid(src)
	if g.is_empty():
		return {}
	var r := rows(src)
	var blocked := blocked_chars(src, impassable_types)
	var walls := {}
	for y in range(r.size()):
		for x in range(str(r[y]).length()):
			if blocked.has(str(r[y])[x]):
				walls[Vector2i(x, y)] = true
	return HG.derive(g, stairs(src), walls)["faces"]
