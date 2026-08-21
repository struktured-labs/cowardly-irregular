extends GutTest

## Village NPCs must stand in the walkable region the player can actually
## REACH — not merely on a walkable tile.
##
## THE RUNG THIS ADDS. Two guards already cover the tile itself:
##   test_village_placement_walkability   the cell is not impassable
##   test_village_reachability_framework  a walkable cell exists within
##                                        interaction reach of the node
## Both are LOCAL. A tile can be walkable, have a walkable neighbour, and sit
## inside a sealed ring of masonry — an NPC there passes both and cannot be
## talked to, which is exactly as unstartable as never placing them. Measured
## 2026-07-30: nothing in the suite computes connectivity for a village; the
## only flood fills are in the two dungeon tests.
##
## Currently every village is a single walkable component, so this is a
## ratchet rather than a bug fix — it earns its keep the first time someone
## walls off a courtyard, which is a live risk while quest givers and
## interactables are being added across five village maps.

const VILLAGE_DIR := "res://src/maps/villages"
const IMPASSABLE_TYPES := ["WALL", "WATER", "VILLAGE_HEDGE", "CAVE_WALL", "LAVA", "MOUNTAIN"]

## Both authored literal forms, same as the placement audit.
const LIT_MUL_EACH := "Vector2\\(\\s*(-?\\d+(?:\\.\\d+)?)\\s*\\*\\s*TILE_SIZE[^,]*,\\s*(-?\\d+(?:\\.\\d+)?)\\s*\\*\\s*TILE_SIZE[^)]*\\)"
const LIT_MUL_WHOLE := "Vector2\\(\\s*(-?\\d+(?:\\.\\d+)?)\\s*,\\s*(-?\\d+(?:\\.\\d+)?)\\s*\\)\\s*\\*\\s*TILE_SIZE"
const GS := preload("res://test/unit/helpers/village_grid_source.gd")
const HG := preload("res://src/exploration/HeightGrid.gd")


func _ctx(src: String) -> Dictionary:
	return {"rows": GS.rows(src), "blocked": GS.blocked_chars(src, IMPASSABLE_TYPES),
		"grid": GS.grid(src), "stairs": GS.stairs(src), "faces": GS.face_cells(src, IMPASSABLE_TYPES)}


func _walkable(ctx: Dictionary, x: int, y: int) -> bool:
	var rows: Array = ctx["rows"]
	if y < 0 or y >= rows.size():
		return false
	var row: String = rows[y]
	if x < 0 or x >= row.length():
		return false
	return not ctx["blocked"].has(row[x]) and not ctx["faces"].has(Vector2i(x, y))


## Flat village: every open neighbour connects. Tiered: only same height or via a stair.
func _step_ok(ctx: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	if (ctx["grid"] as Array).is_empty():
		return true
	return HG.can_step(ctx["grid"], ctx["stairs"], a, b)


## 4-connected components over walkable cells. Returns {cell_key: component_id}
## and {component_id: size}.
func _components(ctx: Dictionary) -> Array:
	var rows: Array = ctx["rows"]
	var owner := {}
	var sizes := {}
	var next_id := 0
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var key := Vector2i(x, y)
			if not _walkable(ctx, x, y) or owner.has(key):
				continue
			next_id += 1
			var n := 0
			var queue: Array[Vector2i] = [key]
			owner[key] = next_id
			while not queue.is_empty():
				var c: Vector2i = queue.pop_back()
				n += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nb: Vector2i = c + d
					if _walkable(ctx, nb.x, nb.y) and _step_ok(ctx, c, nb) and not owner.has(nb):
						owner[nb] = next_id
						queue.append(nb)
			sizes[next_id] = n
	return [owner, sizes]


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


func _npc_cells(src: String) -> Array:
	var each := RegEx.create_from_string(LIT_MUL_EACH)
	var whole := RegEx.create_from_string(LIT_MUL_WHOLE)
	var out: Array = []
	var idx := src.find("_create_npc(")
	while idx >= 0:
		var line_start := src.rfind("\n", idx) + 1
		if not src.substr(line_start, idx - line_start).contains("func "):
			var call := _call_extent(src, idx)
			var m := each.search(call)
			if m == null:
				m = whole.search(call)
			if m != null:
				out.append({
					"cell": Vector2i(int(float(m.get_string(1))), int(float(m.get_string(2)))),
					"line": src.substr(0, idx).count("\n") + 1,
				})
		idx = src.find("_create_npc(", idx + 1)
	return out


func test_every_village_npc_stands_in_the_reachable_region() -> void:
	var dir := DirAccess.open(VILLAGE_DIR)
	assert_not_null(dir, "villages dir readable")
	var villages := 0
	var npcs := 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var src: String = FileAccess.get_file_as_string(VILLAGE_DIR + "/" + f)
		var ctx := _ctx(src)
		var rows: Array = ctx["rows"]
		if rows.is_empty():
			continue
		var blocked: Dictionary = ctx["blocked"]
		# Without this the fill treats every cell as walkable, every village is
		# trivially one component, and the assertion below can never fail.
		assert_false(blocked.is_empty(),
			"%s: no impassable chars parsed from its legend — the flood fill would be vacuous" % f)
		if blocked.is_empty():
			continue
		villages += 1

		var parts := _components(ctx)
		var owner: Dictionary = parts[0]
		var sizes: Dictionary = parts[1]
		assert_gt(sizes.size(), 0, "%s: has walkable cells" % f)

		var total := 0
		for r in rows:
			total += (r as String).length()
		var walkable := 0
		for s in sizes.values():
			walkable += s
		assert_lt(walkable, total,
			"%s: every cell parsed as walkable — the legend did not resolve, so connectivity means nothing" % f)

		var main_id := 0
		var main_size := -1
		for id in sizes:
			if sizes[id] > main_size:
				main_size = sizes[id]
				main_id = id

		for entry in _npc_cells(src):
			npcs += 1
			var cell: Vector2i = entry["cell"]
			var comp = owner.get(cell, 0)
			assert_eq(comp, main_id,
				"%s:%d NPC at cell (%d,%d) is not in the village's main walkable region (component %s of %d cells vs main %d) — a player cannot reach them" % [
					f, entry["line"], cell.x, cell.y, str(comp), int(sizes.get(comp, 0)), main_size])

	# DERIVED floor, not a magic number. `> 8` let up to 4 of the 13 villages
	# drop out silently — _rows() returns [] on a failed parse and the loop
	# `continue`s, so a partial failure is indistinguishable from a village
	# that legitimately carries no grid. Compare the audit against the count
	# the marker itself implies.
	assert_eq(villages, _villages_declaring_a_grid(),
		"audited %d villages but %d declare a map_data grid — the difference parsed to nothing and was skipped in silence" % [villages, _villages_declaring_a_grid()])
	assert_gt(npcs, 40, "found real NPC placements — zero would pass this file for free")


## How many village sources DECLARE a grid, independent of whether this file
## managed to parse one. The gap between the two is what a silent skip looks like.
func _villages_declaring_a_grid() -> int:
	var n := 0
	var dir := DirAccess.open(VILLAGE_DIR)
	if dir == null:
		return 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		if FileAccess.get_file_as_string(VILLAGE_DIR + "/" + f).contains("var map_data: Array[String] = ["):
			n += 1
	return n
