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
	# DERIVED, not a magic number. `> 8` let up to 4 of the 13 grid-carrying
	# villages parse to nothing and be skipped in silence — _parse_map_rows
	# returns [] on failure and the loop `continue`s, so a failed parse is
	# indistinguishable from a village that legitimately has no grid.
	assert_eq(audited, _villages_declaring_a_grid(),
		"audited %d villages but %d declare a map_data grid — the difference parsed to nothing and was skipped in silence" % [audited, _villages_declaring_a_grid()])


## How many village sources DECLARE a grid, independent of whether this file
## managed to parse one. The gap between the two is what a silent skip looks like.
func _villages_declaring_a_grid() -> int:
	var n := 0
	var dir := DirAccess.open("res://src/maps/villages")
	if dir == null:
		return 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		if FileAccess.get_file_as_string("res://src/maps/villages/" + f).contains("var map_data: Array[String] = ["):
			n += 1
	return n


## Both authored literal forms. Form B is what ScripturaPlaza uses for two of
## its NPCs; the old single-pattern scan matched neither of them, so they were
## placed unchecked from the day they landed.
const LIT_MUL_EACH := "Vector2\\(\\s*(-?\\d+(?:\\.\\d+)?)\\s*\\*\\s*TILE_SIZE[^,]*,\\s*(-?\\d+(?:\\.\\d+)?)\\s*\\*\\s*TILE_SIZE[^)]*\\)"
const LIT_MUL_WHOLE := "Vector2\\(\\s*(-?\\d+(?:\\.\\d+)?)\\s*,\\s*(-?\\d+(?:\\.\\d+)?)\\s*\\)\\s*\\*\\s*TILE_SIZE"


## Walk a call to its balanced closing paren. The previous scan iterated LINES
## and only looked at one when the marker and the Vector2 shared it, so a call
## wrapped across lines was skipped and reported as a pass — fail-open, and
## invisible. Measured on main before this change: 34% of markers yielded no
## coordinate at all.
func _call_extent(src: String, start: int) -> String:
	var open := src.find("(", start)
	if open < 0:
		return ""
	var depth := 0
	var i := open
	while i < src.length():
		if src[i] == "(":
			depth += 1
		elif src[i] == ")":
			depth -= 1
			if depth == 0:
				return src.substr(start, i - start + 1)
		i += 1
	return ""


## Text inside the call's first Vector2(...), for shape classification.
func _vector_args(call_text: String) -> String:
	var v := call_text.find("Vector2(")
	if v < 0:
		return ""
	var inner := _call_extent(call_text.substr(v), 0)
	return inner.substr(8, inner.length() - 9) if inner.length() > 9 else ""


## A literal placement is one whose Vector2 args are pure arithmetic on tile
## numbers. Anything reaching into a dict, a property or a variable is dynamic
## and cannot be resolved from source — those are REPORTED, never silently
## dropped. Classifying by shape rather than by an allowlist means a NEW
## literal form fails loudly instead of joining the invisible 34%.
func _is_literal_shape(args: String) -> bool:
	if args.is_empty():
		return false
	var stripped := args.replace("TILE_SIZE", "")
	for c in stripped:
		if not (c in "0123456789 \t\n.,*+-/()"):
			return false
	return true


func _check_cell(fname: String, where: String, rows: Array, blocked: Dictionary, cx: int, cy: int) -> void:
	var ch := _char_at(rows, cx, cy)
	assert_false(blocked.has(ch),
		"%s %s places on impassable '%s' at cell (%d,%d)" % [fname, where, ch, cx, cy])


func _audit_file(fname: String, src: String, rows: Array, blocked: Dictionary) -> void:
	var re_each := RegEx.create_from_string(LIT_MUL_EACH)
	var re_whole := RegEx.create_from_string(LIT_MUL_WHOLE)
	var calls := 0
	var resolved := 0
	var dynamic: Array[String] = []

	for marker in PLACEMENT_MARKERS:
		var idx := src.find(marker)
		while idx >= 0:
			# `func _place_chicken(` is a definition, not a placement.
			var line_start := src.rfind("\n", idx) + 1
			if not src.substr(line_start, idx - line_start).contains("func "):
				var call_text := _call_extent(src, idx)
				var line_no := src.substr(0, idx).count("\n") + 1
				var hits := re_each.search_all(call_text)
				if hits.is_empty():
					hits = re_whole.search_all(call_text)
				calls += 1
				if hits.is_empty():
					var args := _vector_args(call_text)
					assert_false(_is_literal_shape(args),
						"%s:%d is a LITERAL placement in a form this audit cannot read (%s) — extend the patterns rather than leaving it unchecked" % [fname, line_no, args.strip_edges().left(48)])
					dynamic.append("%s:%d" % [fname, line_no])
				else:
					resolved += 1
					for m in hits:
						_check_cell(fname, "line %d" % line_no, rows, blocked,
							int(float(m.get_string(1))), int(float(m.get_string(2))))
			idx = src.find(marker, idx + 1)

	# Patrol legs are authored as multi-line Vector2 arrays, scanned separately.
	var in_patrol := false
	var line_no_p := 0
	for line in src.split("\n"):
		line_no_p += 1
		if line.contains("Array[Vector2] = ["):
			in_patrol = true
		if in_patrol:
			for m in re_each.search_all(line):
				_check_cell(fname, "patrol line %d" % line_no_p, rows, blocked,
					int(float(m.get_string(1))), int(float(m.get_string(2))))
			if line.strip_edges() == "]":
				in_patrol = false

	# THE FLOOR. A village carrying placement markers must yield at least one
	# resolved coordinate. Without this, a reformat that made every call
	# unreadable would leave the file counted as audited and checked zero times.
	if calls > 0:
		assert_gt(resolved, 0,
			"%s has %d placement call(s) and NONE resolved to a cell — the audit read nothing and would have passed silently" % [fname, calls])
	if not dynamic.is_empty():
		gut.p("  %s: %d dynamic placement(s) not statically resolvable: %s" % [fname, dynamic.size(), ", ".join(dynamic)])


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


## Negative guards are load-bearing, not defensive padding: GDScript indexes
## from the END, so row[-3] returns a real tile several columns from the right
## edge — a silent wrong answer rather than an error. cowir-story hit exactly
## this in QuestSystem (objectives[-2] returning a populated objective). It was
## unreachable here only because the patterns below could not express a
## negative; they now can, so the guard has to precede them.
func _char_at(rows: Array, cx: int, cy: int) -> String:
	if cy < 0 or cy >= rows.size():
		return "W"
	var row: String = rows[cy]
	if cx < 0 or cx >= row.length():
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