extends GutTest

## Ragged-row map_data lint (cowir-main task #21, msg 2546). Village
## _generate_map() reads `map_data` with `for x in range(MAP_WIDTH)` —
## a row wider than MAP_WIDTH gets silently truncated at the render
## loop; a row narrower silently fills with 'W' padding via the row
## length check. Either drift makes the rendered layout diverge from
## what a reader sees in the source string.
##
## Precedent: EldertreeVillage shipped with 14 rows one char too long
## (each row 26 chars vs. MAP_WIDTH=25). The extra char was silently
## dropped for months. Caught during the 2026-07-14 village-grow pass
## because my grow script had to normalize row widths before padding.
## This lint pins the invariant so future typos surface at commit
## time, not at playtest.

const VILLAGES_DIR := "res://src/maps/villages"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _parse_map_width(src: String) -> int:
	var m := RegEx.create_from_string("const MAP_WIDTH: int = (\\d+)").search(src)
	return int(m.get_string(1)) if m else -1


func _parse_map_data_rows(src: String) -> Array:
	# Match the map_data literal — start at `= [`, end at the matching `]`
	# on the same block; strip the closing bracket back to the last quote.
	var start := src.find("var map_data: Array[String] = [")
	if start < 0:
		return []
	var body_start := src.find("= [", start) + 3
	var body_end := src.find("]", body_start)
	if body_end < 0:
		return []
	var block := src.substr(body_start, body_end - body_start)
	var rows: Array = []
	var re := RegEx.create_from_string("\"([^\"]+)\"")
	for m in re.search_all(block):
		rows.append(m.get_string(1))
	return rows


func test_every_village_map_data_row_matches_map_width() -> void:
	var dir := DirAccess.open(VILLAGES_DIR)
	assert_not_null(dir, "villages dir readable")
	var checked := 0
	var offenders: Array = []
	for f in dir.get_files():
		if not f.ends_with(".gd") or f == "BaseVillage.gd" or f == "BaseVillage.gd.uid":
			continue
		var path := VILLAGES_DIR + "/" + f
		var src := _read(path)
		var mw := _parse_map_width(src)
		var rows := _parse_map_data_rows(src)
		# Villages without map_data (should be none, but be safe): skip.
		if mw < 0 or rows.is_empty():
			continue
		checked += 1
		for i in range(rows.size()):
			var row: String = rows[i]
			if row.length() != mw:
				offenders.append("%s row %d: len=%d != MAP_WIDTH=%d (row='%s')" % [
					f, i, row.length(), mw, row])
	assert_gt(checked, 10,
		"expected the village fleet to carry map_data grids (checked %d)" % checked)
	assert_eq(offenders.size(), 0,
		"map_data rows must all equal MAP_WIDTH — %d offenders: %s" % [
			offenders.size(), "\n  ".join(offenders)])


func test_every_village_map_data_row_count_matches_map_height() -> void:
	# Companion invariant: too-few rows silently pad with 'W' at the render
	# loop; too-many rows leave dead data. Neither should ship.
	var dir := DirAccess.open(VILLAGES_DIR)
	assert_not_null(dir, "villages dir readable")
	var re_h := RegEx.create_from_string("const MAP_HEIGHT: int = (\\d+)")
	var offenders: Array = []
	for f in dir.get_files():
		if not f.ends_with(".gd") or f == "BaseVillage.gd" or f == "BaseVillage.gd.uid":
			continue
		var path := VILLAGES_DIR + "/" + f
		var src := _read(path)
		var m := re_h.search(src)
		var rows := _parse_map_data_rows(src)
		if m == null or rows.is_empty():
			continue
		var mh := int(m.get_string(1))
		if rows.size() != mh:
			offenders.append("%s: %d rows vs MAP_HEIGHT=%d" % [f, rows.size(), mh])
	assert_eq(offenders.size(), 0,
		"map_data row count must equal MAP_HEIGHT — %d offenders: %s" % [
			offenders.size(), "\n  ".join(offenders)])
