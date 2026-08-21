extends GutTest

## Every village that declares height_data must be internally consistent: same dims as map_data,
## no two-tier jump between open cells, no face landing on a stair or an authored mark.
## CONTROL: the Harmonia grid must be present — the count assert keeps this audit from passing
## on an empty corpus.

const GS := preload("res://test/unit/helpers/village_grid_source.gd")
const HG := preload("res://src/exploration/HeightGrid.gd")
const IMPASSABLE := ["WALL", "WATER", "VILLAGE_HEDGE", "CAVE_WALL", "LAVA", "MOUNTAIN"]
const LIT := "Vector2\\(\\s*(-?\\d+(?:\\.\\d+)?)\\s*\\*\\s*TILE_SIZE[^,]*,\\s*(-?\\d+(?:\\.\\d+)?)\\s*\\*\\s*TILE_SIZE[^)]*\\)"
const MARK_LINES := ["_create_npc(", "_place_chicken(", "spawn_points[", ".position = Vector2(", "_add_interior_door("]


func _sources() -> Dictionary:
	var out := {}
	var dir := DirAccess.open("res://src/maps/villages")
	for f in dir.get_files():
		if f.ends_with(".gd") and f != "BaseVillage.gd":
			var src := FileAccess.get_file_as_string("res://src/maps/villages/" + f)
			if not GS.height_rows(src).is_empty():
				out[f] = src
	return out


func test_at_least_one_village_declares_height_data() -> void:
	assert_gt(_sources().size(), 0, "CONTROL: Harmonia must carry height_data")


func test_height_rows_match_map_dims() -> void:
	var srcs := _sources()
	for f in srcs:
		var src: String = srcs[f]
		var m := GS.rows(src)
		var h := GS.height_rows(src)
		assert_eq(h.size(), m.size(), "%s: height rows == map rows" % f)
		for i in range(mini(h.size(), m.size())):
			assert_eq(str(h[i]).length(), str(m[i]).length(), "%s row %d width" % [f, i])
			assert_true(RegEx.create_from_string("^[0-3]+$").search(str(h[i])) != null, "%s row %d digits 0-3 only" % [f, i])


func test_no_two_tier_jump_between_open_cells() -> void:
	var srcs := _sources()
	for f in srcs:
		var src: String = srcs[f]
		var g := GS.grid(src)
		var blocked := GS.blocked_chars(src, IMPASSABLE)
		var rows := GS.rows(src)
		for y in range(g.size()):
			for x in range(g[y].size()):
				if blocked.has(str(rows[y])[x]):
					continue
				for d in [Vector2i(1, 0), Vector2i(0, 1)]:
					var n: Vector2i = Vector2i(x, y) + d
					var hn := HG.height_at(g, n)
					if hn < 0 or blocked.has(str(rows[n.y])[n.x]):
						continue
					assert_lt(absi(hn - HG.height_at(g, Vector2i(x, y))), 2, "%s: %s -> %s jumps two tiers with no way to bridge it" % [f, Vector2i(x, y), n])


func test_faces_never_land_on_stairs_or_marks() -> void:
	var re := RegEx.create_from_string(LIT)
	var srcs := _sources()
	for f in srcs:
		var src: String = srcs[f]
		var faces := GS.face_cells(src, IMPASSABLE)
		assert_gt(faces.size(), 0, "%s: a tiered village derives at least one face" % f)
		for s in GS.stairs(src):
			assert_false(faces.has(s), "%s: stair %s consumed by a face" % [f, s])
		for line in src.split("\n"):
			var marked := false
			for k in MARK_LINES:
				if line.contains(k):
					marked = true
			if not marked:
				continue
			for m in re.search_all(line):
				var cell := Vector2i(int(floor(float(m.get_string(1)))), int(floor(float(m.get_string(2)))))
				assert_false(faces.has(cell), "%s: mark at %s sits on a derived cliff face: %s" % [f, cell, line.strip_edges()])
