extends GutTest

## Dragon cave boss floors: boss at far end + winding path + treasures
## (struktured msg 2788: "why is the dragon at the very beginning of the
## cave? seems silly — make it a little harder to reach, wear the
## character out, maybe get some treasures on the way").
##
## Pre-fix: all 4 dragon caves' boss floors had B at (10, 7) and D at
## (10, 14) with an unobstructed straight 7-tile walk from arrival to
## boss trigger. Lightning was 2-floor (shorter than the others) so the
## traversal was even more compressed.
##
## Post-fix (class-level, per struktured "fix the class not the instance"):
##   - Lightning bumped to 3 floors (parity with Fire/Ice/Shadow).
##   - All 4 caves' boss floors share a new layout: B at top-right corner
##     (col ≥ 15, row ≤ 3), D at south (row 14), interior walls forming a
##     chamber player must detour around, 3+ T treasure markers on the
##     path. Loot is generated per T marker via DragonCave._place_floor
##     _treasure — chest_id is per-floor so they don't collide across caves.

const DRAGON_CAVES: Array = [
	["res://src/maps/dungeons/LightningDragonCave.gd", "LightningDragonCaveScene"],
	["res://src/maps/dungeons/FireDragonCave.gd", "FireDragonCaveScene"],
	["res://src/maps/dungeons/IceDragonCave.gd", "IceDragonCaveScene"],
	["res://src/maps/dungeons/ShadowDragonCave.gd", "ShadowDragonCaveScene"],
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _find_char(rows: Array, ch: String) -> Vector2i:
	for y in range(rows.size()):
		var r: String = str(rows[y])
		for x in range(r.length()):
			if r[x] == ch:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _count_char(rows: Array, ch: String) -> int:
	var n := 0
	for y in range(rows.size()):
		var r: String = str(rows[y])
		for x in range(r.length()):
			if r[x] == ch:
				n += 1
	return n


func _flood_reach(rows: Array, start: Vector2i, goal: Vector2i, wall: String = "M") -> bool:
	if start == Vector2i(-1, -1) or goal == Vector2i(-1, -1):
		return false
	var seen := {}
	var stack: Array = [start]
	while stack.size() > 0:
		var p: Vector2i = stack.pop_back()
		if p == goal:
			return true
		if seen.has(p):
			continue
		seen[p] = true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.y < 0 or q.y >= rows.size():
				continue
			var r: String = str(rows[q.y])
			if q.x < 0 or q.x >= r.length():
				continue
			if r[q.x] == wall:
				continue
			stack.append(q)
	return false


## Every cave now has 3 floors — parity across the class.
func test_all_dragon_caves_have_three_floors() -> void:
	for entry in DRAGON_CAVES:
		var script = load(entry[0])
		assert_not_null(script, "%s loads" % entry[0])
		var inst = script.new()
		assert_eq(inst.total_floors, 3,
			"%s: total_floors must be 3 (msg 2788 class-level parity)" % entry[1])


## Boss (B) sits at the FAR end of the top floor (row 1, cols ≥ 14).
## D (arrival) sits at the south — row 14. The old layout put them on
## the same vertical line, 7 tiles apart; the new layout separates them
## by both axes so the traversal winds.
func test_boss_is_at_far_end_of_top_floor() -> void:
	for entry in DRAGON_CAVES:
		var script = load(entry[0])
		var inst = script.new()
		var boss_floor: Array = inst.floor_layouts[inst.total_floors]
		var b := _find_char(boss_floor, "B")
		var d := _find_char(boss_floor, "D")
		assert_ne(b, Vector2i(-1, -1), "%s boss floor has a B marker" % entry[1])
		assert_ne(d, Vector2i(-1, -1), "%s boss floor has a D marker" % entry[1])
		assert_lt(b.y, 4, "%s: B must be near the TOP (row < 4)" % entry[1])
		assert_gt(b.x, 13, "%s: B must be at the FAR side (col > 13)" % entry[1])
		assert_gt(d.y, 10, "%s: D stays at the south (row > 10)" % entry[1])


## Every boss floor carries at least 3 T treasure markers so the path is
## rewarding, per struktured's "get some treasures on the way."
func test_boss_floor_has_treasures_en_route() -> void:
	for entry in DRAGON_CAVES:
		var script = load(entry[0])
		var inst = script.new()
		var boss_floor: Array = inst.floor_layouts[inst.total_floors]
		var t_count := _count_char(boss_floor, "T")
		assert_gt(t_count, 2,
			"%s: boss floor must have >2 T treasure markers (got %d)" % [entry[1], t_count])


## Walkability: D → B must be reachable through floor cells. Catches
## the layout-authoring trap where the boss ends up sealed behind walls.
func test_boss_reachable_from_arrival_on_every_cave() -> void:
	for entry in DRAGON_CAVES:
		var script = load(entry[0])
		var inst = script.new()
		var boss_floor: Array = inst.floor_layouts[inst.total_floors]
		var d := _find_char(boss_floor, "D")
		var b := _find_char(boss_floor, "B")
		assert_true(_flood_reach(boss_floor, d, b),
			"%s: no walkable path from D%s to B%s" % [entry[1], str(d), str(b)])


## Every T treasure must also be reachable from the arrival — a chest
## the player can't get to is dead loot.
func test_every_treasure_reachable_from_arrival() -> void:
	for entry in DRAGON_CAVES:
		var script = load(entry[0])
		var inst = script.new()
		var boss_floor: Array = inst.floor_layouts[inst.total_floors]
		var d := _find_char(boss_floor, "D")
		for y in range(boss_floor.size()):
			var r: String = str(boss_floor[y])
			for x in range(r.length()):
				if r[x] == "T":
					var t := Vector2i(x, y)
					assert_true(_flood_reach(boss_floor, d, t),
						"%s: treasure at %s unreachable from D%s" % [
							entry[1], str(t), str(d)])
