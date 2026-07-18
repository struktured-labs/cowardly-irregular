extends GutTest

## Ragged-row map_data lint (cowir-main task #21, msg 2546 + extended to
## interiors 2026-07-18 per msg 2780). Village/interior grid rendering
## reads `map_data` with `for x in range(MAP_WIDTH)` — a row wider than
## MAP_WIDTH gets silently truncated at the render loop; a row narrower
## silently fills with 'W' padding via the row length check. Either
## drift makes the rendered layout diverge from what a reader sees in
## the source string.
##
## Precedent: EldertreeVillage shipped with 14 rows one char too long
## (each row 26 chars vs. MAP_WIDTH=25); TavernInterior shipped with 16
## rows THREE chars too long (each row 30-31 chars vs. MAP_WIDTH=28) —
## caught by struktured looking at a "door in the bottom right" that
## was authored past the render window. This lint pins the invariant
## so future typos surface at commit time, not at playtest.

const VILLAGES_DIR := "res://src/maps/villages"
const INTERIORS_DIR := "res://src/maps/interiors"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _parse_map_width(src: String) -> int:
	var m := RegEx.create_from_string("const MAP_WIDTH[^=]*=\\s*(\\d+)").search(src)
	return int(m.get_string(1)) if m else -1


## Villages declare `var map_data: Array[String] = [...]`; the three
## legacy interiors (InnInterior/ShopInterior/TavernInterior) declare
## `const INN_LAYOUT` / `SHOP_LAYOUT` / `TAVERN_LAYOUT`. Accept both
## shapes so the lint covers the full fleet. Anchor on the trailing
## `= [` so the parser skips past the `Array[String]` type annotation.
func _parse_map_data_rows(src: String) -> Array:
	var starts: Array = []
	for anchor in ["var map_data: Array[String] = [", "const INN_LAYOUT = [",
			"const SHOP_LAYOUT = [", "const TAVERN_LAYOUT = ["]:
		var idx := src.find(anchor)
		if idx >= 0:
			starts.append([idx, anchor.length()])
	if starts.is_empty():
		return []
	starts.sort()
	var start: int = starts[0][0]
	var anchor_len: int = starts[0][1]
	# body_start = the char AFTER the anchor's closing `[`.
	var body_start := start + anchor_len
	var body_end := src.find("]", body_start)
	if body_end < 0:
		return []
	var block := src.substr(body_start, body_end - body_start)
	var rows: Array = []
	var re := RegEx.create_from_string("\"([^\"]+)\"")
	for m in re.search_all(block):
		rows.append(m.get_string(1))
	return rows


## Iterate a directory once, applying the (mw, mh, rows) lint per file.
func _lint_dir(dir_path: String, base_skip: String, offenders_w: Array, offenders_h: Array) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	var checked := 0
	var re_h := RegEx.create_from_string("const MAP_HEIGHT[^=]*=\\s*(\\d+)")
	for f in dir.get_files():
		if not f.ends_with(".gd") or f == base_skip or f == base_skip + ".uid":
			continue
		var path := dir_path + "/" + f
		var src := _read(path)
		var rows := _parse_map_data_rows(src)
		if rows.is_empty():
			continue
		checked += 1
		var mw := _parse_map_width(src)
		if mw > 0:
			for i in range(rows.size()):
				var row: String = rows[i]
				if row.length() != mw:
					offenders_w.append("%s row %d: len=%d != MAP_WIDTH=%d (row='%s')" % [
						f, i, row.length(), mw, row])
		var h_m := re_h.search(src)
		if h_m != null:
			var mh := int(h_m.get_string(1))
			if rows.size() != mh:
				offenders_h.append("%s: %d rows vs MAP_HEIGHT=%d" % [
					f, rows.size(), mh])
	return checked


func test_every_village_map_data_row_matches_map_width() -> void:
	var offenders_w: Array = []
	var offenders_h: Array = []
	var checked := _lint_dir(VILLAGES_DIR, "BaseVillage.gd", offenders_w, offenders_h)
	assert_gt(checked, 10,
		"expected the village fleet to carry map_data grids (checked %d)" % checked)
	assert_eq(offenders_w.size(), 0,
		"village map_data rows must all equal MAP_WIDTH — %d offenders:\n  %s" % [
			offenders_w.size(), "\n  ".join(offenders_w)])
	assert_eq(offenders_h.size(), 0,
		"village map_data row count must equal MAP_HEIGHT — %d offenders:\n  %s" % [
			offenders_h.size(), "\n  ".join(offenders_h)])


## Interior extension (msg 2780). TavernInterior shipped with rows 3
## chars past MAP_WIDTH — Struktured saw a "door in the bottom right"
## that was authored past the render window. The three legacy Node2D
## interiors expose the layout as a named LAYOUT const; BaseInterior
## descendants use _get_layout() and don't declare a map-data literal,
## so this lint is a no-op for them (they're covered by the BaseInterior
## sweep + placement ratchet from PR #162).
func test_every_interior_map_data_row_matches_map_width() -> void:
	var offenders_w: Array = []
	var offenders_h: Array = []
	var checked := _lint_dir(INTERIORS_DIR, "BaseInterior.gd", offenders_w, offenders_h)
	assert_gt(checked, 2,
		"expected at least the 3 legacy interiors to carry map_data (checked %d)" % checked)
	assert_eq(offenders_w.size(), 0,
		"interior map_data rows must all equal MAP_WIDTH — %d offenders:\n  %s" % [
			offenders_w.size(), "\n  ".join(offenders_w)])
	assert_eq(offenders_h.size(), 0,
		"interior map_data row count must equal MAP_HEIGHT — %d offenders:\n  %s" % [
			offenders_h.size(), "\n  ".join(offenders_h)])
