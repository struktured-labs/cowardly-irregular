extends GutTest

## Six quest examine points across five villages were placed at `Vector2(x * TILE_SIZE, y * TILE_SIZE)` -- a cell's
## top-left CORNER -- while every route point beside them used `x.5`. A corner point straddles four cells and its
## raised prompt landed on the NPC in the row above (Brasston: "Read the depot record" over a villager's head).
## Same mistake the dungeon signs and chests had. Every examine/route point now names a cell centre.

const DIR := "res://src/maps/villages"


func test_every_quest_point_in_every_village_is_on_a_cell_centre() -> void:
	var re := RegEx.create_from_string("_add_quest_(examine|route)_point\\(")
	var pos_re := RegEx.create_from_string("Vector2\\(\\s*([\\d.]+)\\s*\\*\\s*TILE_SIZE\\s*,\\s*([\\d.]+)\\s*\\*\\s*TILE_SIZE\\s*\\)")
	var checked := 0
	var offenders: Array = []
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string(DIR + "/" + f)
		for m in re.search_all(src):
			var call_end := src.find("\n\n", m.get_start())
			var call := src.substr(m.get_start(), (call_end if call_end > 0 else src.length()) - m.get_start())
			var p := pos_re.search(call)
			if p == null:
				continue
			checked += 1
			if not (p.get_string(1).ends_with(".5") and p.get_string(2).ends_with(".5")):
				offenders.append("%s (%s,%s)" % [f, p.get_string(1), p.get_string(2)])
	assert_gt(checked, 10, "CONTROL: the scan read real quest points (%d)" % checked)
	assert_eq(offenders, [], "quest points on a cell corner: %s" % [offenders])
