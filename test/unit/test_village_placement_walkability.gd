extends GutTest

## Placement-walkability ratchet (live playtest 2026-07-11, msg 2360):
## a quest hen sat inside Harmonia's Inn wall block, Gerald + the wildflower
## sat inside the Suburban Mart, a loft-exit spawn dropped the player inside
## a Brasston house. This audit parses every village's map_data grid + its
## _char_to_tile_type legend and asserts that player-reachable placements
## (_create_npc / _place_chicken / spawn_points / chests / patrol loops)
## land on walkable cells. Building-anchored fixtures (shops, doors, save
## monuments) are intentionally out of scope — their interact zones reach
## outside their blocks. Runtime belt: BaseVillage._validate_placements.

const IMPASSABLE_TYPES := ["WALL", "WATER", "VILLAGE_HEDGE", "CAVE_WALL", "LAVA", "MOUNTAIN"]

## Line shapes that place something the player must physically reach.
const PLACEMENT_MARKERS := ["_create_npc(", "_place_chicken(", "spawn_points["]


func test_every_village_placement_is_walkable() -> void:
	var dir := DirAccess.open("res://src/maps/villages")
	assert_not_null(dir, "villages dir readable")
	var audited := 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var src: String = FileAccess.get_file_as_string("res://src/maps/villages/" + f)
		var rows := _parse_map_rows(src)
		if rows.is_empty():
			continue
		audited += 1
		var blocked := _parse_impassable_chars(src)
		_audit_file(f, src, rows, blocked)
	assert_gt(audited, 8, "expected the village fleet to carry map_data grids (got %d)" % audited)


func _audit_file(fname: String, src: String, rows: Array, blocked: Dictionary) -> void:
	var vec_re := RegEx.create_from_string(
		"Vector2\\(\\s*(\\d+(?:\\.\\d+)?)\\s*\\*\\s*TILE_SIZE[^,]*,\\s*(\\d+(?:\\.\\d+)?)\\s*\\*\\s*TILE_SIZE[^)]*\\)")
	var in_patrol := false
	var line_no := 0
	for line in src.split("\n"):
		line_no += 1
		if line.contains("Array[Vector2] = ["):
			in_patrol = true
		var relevant := in_patrol
		for marker in PLACEMENT_MARKERS:
			if line.contains(marker):
				relevant = true
				break
		if in_patrol and line.strip_edges() == "]":
			in_patrol = false
		if not relevant:
			continue
		for m in vec_re.search_all(line):
			var cx := int(float(m.get_string(1)))
			var cy := int(float(m.get_string(2)))
			var ch := _char_at(rows, cx, cy)
			assert_false(blocked.has(ch),
				"%s:%d places on impassable '%s' at cell (%d,%d) — %s" % [
					fname, line_no, ch, cx, cy, line.strip_edges().left(70)])


func _parse_map_rows(src: String) -> Array:
	var start := src.find("var map_data: Array[String] = [")
	if start < 0:
		return []
	# Scan from past "= [" — the type annotation's own "]" would end the block early.
	var open := src.find("= [", start) + 3
	var block := src.substr(open, src.find("]", open) - open)
	var rows: Array = []
	var row_re := RegEx.create_from_string("\"([^\"]+)\"")
	for m in row_re.search_all(block):
		rows.append(m.get_string(1))
	return rows


## Chars mapped to blocking TileTypes by this village's _char_to_tile_type.
func _parse_impassable_chars(src: String) -> Dictionary:
	var blocked := {}
	var char_re := RegEx.create_from_string("\"(.)\"")
	for line in src.split("\n"):
		if not (line.contains("return") and line.contains("TileType.")):
			continue
		var is_blocking := false
		for t in IMPASSABLE_TYPES:
			if line.contains("TileType." + t):
				is_blocking = true
				break
		if not is_blocking:
			continue
		for m in char_re.search_all(line):
			blocked[m.get_string(1)] = true
	return blocked


func _char_at(rows: Array, cx: int, cy: int) -> String:
	if cy >= rows.size():
		return "W"
	var row: String = rows[cy]
	if cx >= row.length():
		return "W"
	return row[cx]


## The runtime belt must stay wired: BaseVillage sweeps npcs-container
## children + wanderer patrols after scene build.
func test_runtime_sweep_is_wired() -> void:
	var base: String = FileAccess.get_file_as_string("res://src/maps/villages/BaseVillage.gd")
	assert_true(base.contains("_validate_placements()"), "sweep called in _ready")
	assert_true(base.contains("get_collision_polygons_count"), "walkability reads TileSet physics data")
	assert_true(base.contains("_validate_patrol"), "wanderer legs validated")
	var wanderer: String = FileAccess.get_file_as_string("res://src/exploration/WanderingNPC.gd")
	assert_true(wanderer.contains("func get_patrol"), "patrol read-back exists for the sweep")