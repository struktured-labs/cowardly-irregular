extends GutTest

## Load-bearing solver for the five W2-W6 masterite dungeons (struktured 2026-09-06,
## "the dragon dungeons are too shallow, all dungeons should be more involved").
##
## BFS over (floor, cell, switch-activation-mask) using each dungeon's REAL
## floor_layouts / switch_effects / portal_links -- not a hand-simplified model.
## Same shape as test_contrarian_depths_solver.gd, generalized across all five
## scripts this ticket touched.
##
## UNLIKE the Backwards Warren (which showcases the mechanic at its most
## extreme -- a portal-only boss floor), every switch and portal in these five
## dungeons is a DELIBERATELY OPTIONAL detour: the mandatory difficulty lives in
## corridor architecture (a sealed room with one exit) and in trap PLATES, never
## in a flip switch or a portal. test_dungeon_floor_reachability.gd enforces
## plain-walking U<->D connectivity on every floor >= 2 with zero knowledge of
## switches or portals, so a mandatory flip-gate here would be a straight
## regression against that guard. This file's "still reachable with X disabled"
## assertions exist to prove that boundary was actually respected, not merely
## intended.

const DUNGEONS := {
	"SuburbanUnderground": "res://src/maps/dungeons/SuburbanUnderground.gd",
	"SteampunkMechanism": "res://src/maps/dungeons/SteampunkMechanism.gd",
	"AssemblyCore": "res://src/maps/dungeons/AssemblyCore.gd",
	"RootProcess": "res://src/maps/dungeons/RootProcess.gd",
	"NullChamber": "res://src/maps/dungeons/NullChamber.gd",
}
const MIN_FLOORS := {
	"NullChamber": 3,
}
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _build(script_path: String):
	var cave = load(script_path).new()
	autofree(cave)
	return cave


func _switch_bit_index(cave) -> Dictionary:
	var keys: Array = (cave.switch_effects as Dictionary).keys()
	keys.sort()
	var out := {}
	for i in range(keys.size()):
		out[keys[i]] = i
	return out


func _switch_id_at(cave, floor_num: int, cell: Vector2i) -> String:
	for sw in DungeonPuzzleLayer.scan_switches(cave.floor_layouts):
		if int(sw["floor"]) == floor_num and (sw["cell"] as Vector2i) == cell:
			return str(sw["id"])
	return ""


func _active_dict(mask: int, bit_index: Dictionary) -> Dictionary:
	var d := {}
	for sw_id in bit_index:
		if mask & (1 << int(bit_index[sw_id])):
			d[sw_id] = true
	return d


func _find_char(cave, floor_num: int, ch: String) -> Vector2i:
	if not (cave.floor_layouts as Dictionary).has(floor_num):
		return Vector2i(-1, -1)
	var rows: Array = cave.floor_layouts[floor_num]
	for y in range(rows.size()):
		var x: int = (rows[y] as String).find(ch)
		if x >= 0:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


func _char_here(cave, f: int, cell: Vector2i) -> String:
	var rows: Array = cave.floor_layouts.get(f, [])
	if cell.y < 0 or cell.y >= rows.size():
		return ""
	var row: String = rows[cell.y]
	if cell.x < 0 or cell.x >= row.length():
		return ""
	return row[cell.x]


func _boss_cell(cave) -> Vector2i:
	return _find_char(cave, cave.total_floors, "B")


func _entrance_cell(cave) -> Vector2i:
	var sp: Vector2 = cave.floor_spawn_points[1]["entrance"]
	return Vector2i(int(sp.x), int(sp.y))


func _offer(queue: Array, seen: Dictionary, state: Array) -> void:
	var key := "%d:%d:%d:%d" % state
	if seen.has(key):
		return
	seen[key] = true
	queue.append(state)


## Mirrors DragonCave._transition_to_floor's landing rule: ascend via 'U' lands on the
## next floor's 'D'; descend via 'D' on floor > 1 lands on the floor below's 'U'.
func _solve(cave, allow_portals: bool, disabled_switches: Array = []) -> Dictionary:
	var bit_index := _switch_bit_index(cave)
	for sw_id in disabled_switches:
		bit_index.erase(sw_id)
	var start_cell := _entrance_cell(cave)
	var seen := {"1:%d:%d:0" % [start_cell.x, start_cell.y]: true}
	var queue: Array = [[1, start_cell.x, start_cell.y, 0]]
	var boss_cell := _boss_cell(cave)
	var reached_boss := false
	var visited_cells := {}
	var head := 0
	while head < queue.size():
		var state: Array = queue[head]
		head += 1
		var f: int = state[0]
		var cell := Vector2i(state[1], state[2])
		var mask: int = state[3]
		visited_cells["%d:%d:%d" % [f, cell.x, cell.y]] = true
		if f == cave.total_floors and cell == boss_cell:
			reached_boss = true
		var active := _active_dict(mask, bit_index)

		for d in DIRS:
			var n: Vector2i = cell + d
			if DungeonPuzzleLayer.is_walkable(cave.floor_layouts, cave.switch_effects, f, n, active):
				_offer(queue, seen, [f, n.x, n.y, mask])

		var ch_here := _char_here(cave, f, cell)
		if ch_here == "U" and f + 1 <= cave.total_floors:
			var land := _find_char(cave, f + 1, "D")
			if land != Vector2i(-1, -1):
				_offer(queue, seen, [f + 1, land.x, land.y, mask])
		elif ch_here == "D" and f > 1:
			var land2 := _find_char(cave, f - 1, "U")
			if land2 == Vector2i(-1, -1) and f - 1 == 1:
				land2 = start_cell
			if land2 != Vector2i(-1, -1):
				_offer(queue, seen, [f - 1, land2.x, land2.y, mask])

		var sw_id := _switch_id_at(cave, f, cell)
		if sw_id != "" and bit_index.has(sw_id):
			var new_mask: int = mask | (1 << int(bit_index[sw_id]))
			if new_mask != mask:
				_offer(queue, seen, [f, cell.x, cell.y, new_mask])

		if allow_portals:
			var dest := DungeonPuzzleLayer.portal_destination(cave.floor_layouts, cave.portal_links, f, cell)
			if not dest.is_empty() and DungeonPuzzleLayer.portal_usable(cave.switch_effects, cave.floor_layouts, f, cell, active):
				var dcell: Vector2i = dest["cell"]
				_offer(queue, seen, [int(dest["floor"]), dcell.x, dcell.y, mask])

	return {"reached_boss": reached_boss, "states_explored": queue.size(), "visited_cells": visited_cells}


func test_every_dungeon_meets_the_floor_depth_requirement() -> void:
	for name in DUNGEONS:
		var cave = _build(DUNGEONS[name])
		var min_floors: int = int(MIN_FLOORS.get(name, 4))
		assert_gte(int(cave.total_floors), min_floors,
			"%s must have at least %d floors (struktured 2026-09-06: dungeons were too shallow)" % [name, min_floors])


func test_control_boss_cell_and_entrance_are_found_in_every_dungeon() -> void:
	for name in DUNGEONS:
		var cave = _build(DUNGEONS[name])
		assert_ne(_boss_cell(cave), Vector2i(-1, -1), "CONTROL: %s must parse a 'B' marker on its final floor" % name)
		assert_ne(_entrance_cell(cave), Vector2i(-1, -1), "CONTROL: %s must parse a floor-1 entrance" % name)


func test_boss_is_reachable_from_the_entrance_in_every_dungeon() -> void:
	for name in DUNGEONS:
		var cave = _build(DUNGEONS[name])
		var result := _solve(cave, true)
		assert_gt(int(result["states_explored"]), 20,
			"CONTROL: %s explored too few states (%d) -- the BFS itself is probably broken" % [name, int(result["states_explored"])])
		assert_true(bool(result["reached_boss"]), "%s: the boss must be reachable from the entrance using the full mechanic set" % name)


## Unlike the Warren, none of these five gate the boss behind a switch -- every
## flip effect is a bonus-vault detour. Disabling any one switch must NOT strand the run.
func test_boss_remains_reachable_with_any_single_switch_disabled() -> void:
	for name in DUNGEONS:
		var cave = _build(DUNGEONS[name])
		for sw_id in (cave.switch_effects as Dictionary):
			var result := _solve(cave, true, [sw_id])
			assert_true(bool(result["reached_boss"]),
				"%s: disabling switch '%s' must not strand the boss -- every switch in these five dungeons is an optional detour, never a mandatory gate" % [name, sw_id])


## Same guarantee for portals: they are shortcuts/flavor, not gates, in these five.
func test_boss_remains_reachable_without_using_any_portal() -> void:
	for name in DUNGEONS:
		var cave = _build(DUNGEONS[name])
		var result := _solve(cave, false)
		assert_true(bool(result["reached_boss"]),
			"%s: the boss must remain reachable with portal use disabled entirely" % name)


func test_every_portal_and_switch_marker_is_in_bounds() -> void:
	for name in DUNGEONS:
		var cave = _build(DUNGEONS[name])
		var offenders: Array = []
		for f in cave.floor_layouts:
			var rows: Array = cave.floor_layouts[f]
			if rows.size() != cave.MAP_HEIGHT:
				offenders.append("%s floor %s has %d rows, expected %d" % [name, str(f), rows.size(), cave.MAP_HEIGHT])
			for y in range(rows.size()):
				var row: String = rows[y]
				if row.length() != cave.MAP_WIDTH:
					offenders.append("%s floor %s row %d has %d chars, expected %d" % [name, str(f), y, row.length(), cave.MAP_WIDTH])
		var portals := DungeonPuzzleLayer.scan_portals(cave.floor_layouts)
		for ch in portals:
			for e in (portals[ch] as Array):
				var c: Vector2i = e["cell"]
				if c.x < 0 or c.x >= cave.MAP_WIDTH or c.y < 0 or c.y >= cave.MAP_HEIGHT:
					offenders.append("%s portal '%s' at %s is out of bounds" % [name, ch, str(c)])
		for sw in DungeonPuzzleLayer.scan_switches(cave.floor_layouts):
			var c: Vector2i = sw["cell"]
			if c.x < 0 or c.x >= cave.MAP_WIDTH or c.y < 0 or c.y >= cave.MAP_HEIGHT:
				offenders.append("%s switch '%s' at %s is out of bounds" % [name, sw["id"], str(c)])
		assert_eq(offenders, [], "every marker must sit on a real, in-bounds floor cell: %s" % str(offenders))


func test_every_dungeon_declares_a_flip_switch_a_portal_pair_and_a_trap() -> void:
	## The task contract, checked per dungeon: >=1 flip-switch, >=1 portal pair,
	## >=1 trap (a switch trap OR a trap_chests mimic).
	for name in DUNGEONS:
		var cave = _build(DUNGEONS[name])
		var has_flip := false
		var has_trap := false
		for sw_id in (cave.switch_effects as Dictionary):
			var eff: Dictionary = cave.switch_effects[sw_id]
			if eff.has("flip"):
				has_flip = true
			if eff.has("trap"):
				has_trap = true
		var mimic_present: bool = not (cave.trap_chests as Array).is_empty()
		assert_true(has_flip, "%s must declare at least one flip switch" % name)
		assert_true(has_trap or mimic_present, "%s must declare at least one trap (switch trap or mimic chest)" % name)

		var portals := DungeonPuzzleLayer.scan_portals(cave.floor_layouts)
		var has_portal_pair := false
		for ch in portals:
			if (portals[ch] as Array).size() >= 2 or (cave.portal_links as Dictionary).has(ch):
				has_portal_pair = true
		assert_true(has_portal_pair, "%s must declare at least one resolvable portal pair" % name)

		var perrs := DungeonPuzzleLayer.validate_portal_pairs(cave.floor_layouts, cave.portal_links)
		assert_eq(perrs, [], "%s: every portal must resolve to exactly two endpoints: %s" % [name, str(perrs)])


func test_every_trap_chest_key_matches_a_real_treasure_marker_and_the_real_count_is_in_range() -> void:
	for name in DUNGEONS:
		var cave = _build(DUNGEONS[name])
		var placed: Dictionary = {}
		for f in cave.floor_layouts:
			var idx := 0
			var rows: Array = cave.floor_layouts[f]
			for y in range(rows.size()):
				var row: String = rows[y]
				for x in range(row.length()):
					if row[x] == "T":
						placed["%s_f%d_c%d" % [cave.cave_id, int(f), idx]] = true
						idx += 1
		for key in (cave.trap_chests as Array):
			assert_true(placed.has(key), "%s: trap_chests entry '%s' has no matching T marker" % [name, key])
		var real_chests: int = placed.size() - (cave.trap_chests as Array).size()
		assert_gte(real_chests, 2, "%s must keep at least two REAL (non-mimic) chests" % name)
		assert_lte(real_chests, 3, "%s should keep 2-3 real chests, not turn into a loot pinata" % name)


## ---- round 2: maze-complexity guard (struktured 2026-10-07, "we need more maze complexity") ----
## Same shape as test_w1_dungeon_depth_solver.gd's round-3 guard, generalized to every
## non-boss floor of the five W2-W6 dungeons. UNLIKE the W1 guard, no floor here is
## required to be mazed by game design -- but the ticket asks for real mazes throughout,
## so this guard holds every floor 1..total_floors-1 to the same bar: no undeclared 4x4
## open area, at least 3 dead ends, and a plain-walk (no mechanics) shortest D<->U path at
## least 1.5x the Manhattan distance. The boss floor (total_floors) is exempt by design --
## CLAUDE.md: "Boss floors may stay open arenas."
##
## Proven to red on the pre-2026-10-07 open-room layouts: reverting the five dungeon
## scripts to their prior committed versions and running this test fails with dozens of
## undeclared 4x4 opens, near-zero dead ends, and ratios pinned at ~1.0 (a straight-line
## walk from D to U through an open hall). Measured by hand before authoring this guard.

const DIRS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _in_declared_chamber(cave, floor_num: int, x: int, y: int) -> bool:
	for entry in (cave.puzzle_chambers.get(floor_num, []) as Array):
		var rect: Array = entry["rect"]
		var x0: int = int(rect[0])
		var y0: int = int(rect[1])
		var x1: int = int(rect[2])
		var y1: int = int(rect[3])
		if x >= x0 and y >= y0 and x + 3 <= x1 and y + 3 <= y1:
			return true
	return false


func _open4_spots(cave, floor_num: int) -> Array:
	var rows: Array = cave.floor_layouts[floor_num]
	var h: int = rows.size()
	var w: int = (rows[0] as String).length()
	var spots: Array = []
	for y in range(h - 3):
		for x in range(w - 3):
			var all_open := true
			for dy in range(4):
				for dx in range(4):
					if (rows[y + dy] as String)[x + dx] == "M":
						all_open = false
						break
				if not all_open:
					break
			if all_open and not _in_declared_chamber(cave, floor_num, x, y):
				spots.append(Vector2i(x, y))
	return spots


## Cells with exactly one open orthogonal neighbor -- plain maze-shape dead ends.
func _dead_end_cells(cave, floor_num: int) -> Array:
	var rows: Array = cave.floor_layouts[floor_num]
	var out: Array = []
	for y in range(rows.size()):
		var row: String = rows[y]
		for x in range(row.length()):
			if row[x] == "M":
				continue
			var n := 0
			for d in DIRS4:
				if _char_here(cave, floor_num, Vector2i(x, y) + d) not in ["", "M"]:
					n += 1
			if n == 1:
				out.append(Vector2i(x, y))
	return out


## Plain D->U walk, no mechanics -- every switch/lever's locked side stays locked. These
## five dungeons' main routes never need a switch (round-1's "still reachable with X
## disabled" guarantees that), so the plain-walk distance IS the real solved distance.
func _plain_shortest_path(cave, floor_num: int) -> int:
	var start := _find_char(cave, floor_num, "D")
	var goal := _find_char(cave, floor_num, "U")
	if start == Vector2i(-1, -1) or goal == Vector2i(-1, -1):
		return -1
	var seen := {start: true}
	var queue: Array = [[start, 0]]
	var head := 0
	while head < queue.size():
		var state: Array = queue[head]
		head += 1
		var cell: Vector2i = state[0]
		var d: int = state[1]
		if cell == goal:
			return d
		for dir in DIRS4:
			var n: Vector2i = cell + dir
			var ch := _char_here(cave, floor_num, n)
			if ch == "" or ch == "M":
				continue
			if seen.has(n):
				continue
			seen[n] = true
			queue.append([n, d + 1])
	return -1


func test_every_w2_w6_non_boss_floor_is_a_real_maze() -> void:
	var checked := 0
	for name in DUNGEONS:
		var cave = _build(DUNGEONS[name])
		for f in range(1, int(cave.total_floors)):
			checked += 1
			var open4 := _open4_spots(cave, f)
			assert_eq(open4, [] as Array,
				"%s floor %d: %d undeclared 4x4-or-larger open area(s) at %s -- not a maze; declare a puzzle_chambers entry if this is deliberate" % [name, f, open4.size(), str(open4)])

			var deads := _dead_end_cells(cave, f)
			assert_gte(deads.size(), 3, "%s floor %d: only %d dead end(s), need at least 3" % [name, f, deads.size()])

			var start := _find_char(cave, f, "D")
			var goal := _find_char(cave, f, "U")
			assert_ne(start, Vector2i(-1, -1), "%s floor %d: no 'D' marker" % [name, f])
			assert_ne(goal, Vector2i(-1, -1), "%s floor %d: no 'U' marker" % [name, f])
			var man: int = absi(start.x - goal.x) + absi(start.y - goal.y)
			var dist := _plain_shortest_path(cave, f)
			assert_gt(dist, -1, "%s floor %d: D cannot reach U at all by plain walking" % [name, f])
			assert_gte(float(dist), 1.5 * float(man),
				"%s floor %d: shortest plain-walk path is %d tiles, Manhattan is %d -- ratio %.2f is below the 1.5x maze-complexity floor" % [name, f, dist, man, float(dist) / float(man) if man > 0 else 0.0])
	assert_gt(checked, 10, "checked %d non-boss floors -- too few to be the sweep" % checked)


## Boss floors (the arena) are exempt by design -- CONTROL proving this guard does not
## accidentally also demand a maze there, which would contradict "boss floors may stay
## open arenas".
func test_boss_floors_remain_exempt_from_the_maze_guard() -> void:
	for name in DUNGEONS:
		var cave = _build(DUNGEONS[name])
		var boss_floor: int = int(cave.total_floors)
		var open4 := _open4_spots(cave, boss_floor)
		assert_gt(open4.size(), 0,
			"CONTROL: %s's boss floor %d has no open area at all -- the exemption is untested" % [name, boss_floor])


## Same guard as the W1 solver file: every chest, crystal, sign and quest point of every floor must stand on or beside
## a cell the solved route visits -- placed on open floor is not the same as reachable.
func test_every_prop_stands_where_the_solver_can_reach_it() -> void:
	var checked := 0
	for name in DUNGEONS:
		var visited: Dictionary = _solve(_build(DUNGEONS[name]), true)["visited_cells"]
		assert_false(visited.has("1:0:0"), "CONTROL: %s's border corner is not visited, so 'reached' can say no" % name)
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		add_child_autofree(vp)
		var live = load(DUNGEONS[name]).new()
		vp.add_child(live)
		await get_tree().process_frame
		var tile: int = live.TILE_SIZE
		for f in range(1, int(live.total_floors) + 1):
			live._generate_map_for_floor(f)
			live._setup_transitions_for_floor(f)
			for c in live.transitions.get_children():
				if c.is_queued_for_deletion() or not (c is SavePoint or c is TreasureChest or c is QuestExaminePoint or c is Signpost):
					continue
				checked += 1
				var cell := Vector2i(c.position / tile)
				var ok := false
				for d in [Vector2i.ZERO] + DIRS:
					if visited.has("%d:%d:%d" % [f, cell.x + d.x, cell.y + d.y]):
						ok = true
				var kind: String = c.get_script().get_global_name() if c.get_script() else c.get_class()
				assert_true(ok, "%s floor %d %s at %s stands where no solved route reaches" % [name, f, kind, str(cell)])
	assert_gt(checked, 40, "CONTROL: the walk reached real props (%d)" % checked)
