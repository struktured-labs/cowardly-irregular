extends GutTest

## The first cave now teaches the Zelda-style gates the W1 dragon caves require (struktured
## 2026-10-07): floor 3 carries a required lever, floor 4 a required key-and-door. Same
## shape as test_w1_dungeon_depth_solver.gd's mechanics-aware BFS, trimmed to the one switch
## and one lock/pickup pair this cave actually declares -- the mutation controls below prove
## each gate is load-bearing (disabling it drops the floor's own exit stairs OUT of the
## reachable set), not just present.

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const TOTAL_FLOORS := 6

var _cave = null


func before_each() -> void:
	_cave = load("res://src/maps/dungeons/WhisperingCave.gd").new()
	autofree(_cave)


func _entrance_cell() -> Vector2i:
	var sp: Vector2 = _cave.floor_spawn_points[1]["entrance"]
	return Vector2i(int(sp.x), int(sp.y))


func _find_char(floor_num: int, ch: String) -> Vector2i:
	var rows: Array = _cave.floor_layouts.get(floor_num, [])
	for y in range(rows.size()):
		var x: int = (rows[y] as String).find(ch)
		if x >= 0:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


func _char_here(f: int, cell: Vector2i) -> String:
	var rows: Array = _cave.floor_layouts.get(f, [])
	if cell.y < 0 or cell.y >= rows.size():
		return ""
	var row: String = rows[cell.y]
	if cell.x < 0 or cell.x >= row.length():
		return ""
	return row[cell.x]


func _offer(queue: Array, seen: Dictionary, state: Array) -> void:
	var key := "%d:%d:%d:%d:%d" % state
	if seen.has(key):
		return
	seen[key] = true
	queue.append(state)


## BFS over (floor, x, y, switch_mask, mech_mask). switch_mask bit0 = the floor-3 lever
## ("sw0"); mech_mask bit0/bit1 = the single K pickup / G lock pair -- same monotonic-OR
## shape as test_w1_dungeon_depth_solver.gd's _mech_bit_index, just with one fixed pair
## instead of a scanned index, since this cave never carries more than one of each.
func _solve(disable_lever: bool = false, disable_pickup: bool = false) -> Dictionary:
	var switches := DungeonPuzzleLayer.scan_switches(_cave.floor_layouts)
	var pickups := DungeonMechanics.scan_pickups(_cave.floor_layouts)
	var locks := DungeonMechanics.scan_locks(_cave.floor_layouts)
	var start := _entrance_cell()
	var boss_cell := _find_char(TOTAL_FLOORS, "B")
	var seen := {"1:%d:%d:0:0" % [start.x, start.y]: true}
	var queue: Array = [[1, start.x, start.y, 0, 0]]
	var visited := {}
	var reached_boss := false
	var head := 0
	while head < queue.size():
		var state: Array = queue[head]
		head += 1
		var f: int = state[0]
		var cell := Vector2i(state[1], state[2])
		var switch_mask: int = state[3]
		var mech_mask: int = state[4]
		visited["%d:%d:%d" % [f, cell.x, cell.y]] = true
		if f == TOTAL_FLOORS and cell == boss_cell:
			reached_boss = true
		var lever_active: bool = (switch_mask & 1) != 0 and not disable_lever
		var collected: bool = (mech_mask & 1) != 0
		var opened: bool = (mech_mask & 2) != 0

		for d in DIRS:
			var n: Vector2i = cell + d
			var ch := _char_here(f, n)
			if ch == "":
				continue
			if ch == "M":
				var active := {"sw0": lever_active}
				if not DungeonPuzzleLayer.is_walkable(_cave.floor_layouts, _cave.switch_effects, f, n, active):
					continue
			elif ch == "G":
				if not opened:
					continue
			_offer(queue, seen, [f, n.x, n.y, switch_mask, mech_mask])

		var ch_here := _char_here(f, cell)
		if ch_here == "U" and f + 1 <= TOTAL_FLOORS:
			var land := _find_char(f + 1, "D")
			if land != Vector2i(-1, -1):
				_offer(queue, seen, [f + 1, land.x, land.y, switch_mask, mech_mask])
		elif ch_here == "D" and f > 1:
			var land2 := _find_char(f - 1, "U")
			if land2 == Vector2i(-1, -1) and f - 1 == 1:
				land2 = start
			if land2 != Vector2i(-1, -1):
				_offer(queue, seen, [f - 1, land2.x, land2.y, switch_mask, mech_mask])

		for sw in switches:
			if int(sw["floor"]) == f and (sw["cell"] as Vector2i) == cell and str(sw["id"]) == "sw0" and not disable_lever:
				if switch_mask & 1 == 0:
					_offer(queue, seen, [f, cell.x, cell.y, switch_mask | 1, mech_mask])

		for pk in pickups:
			if int(pk["floor"]) == f and (pk["cell"] as Vector2i) == cell and not disable_pickup:
				if mech_mask & 1 == 0:
					_offer(queue, seen, [f, cell.x, cell.y, switch_mask, mech_mask | 1])

		for lk in locks:
			if int(lk["floor"]) != f:
				continue
			var lcell: Vector2i = lk["cell"]
			if absi(cell.x - lcell.x) + absi(cell.y - lcell.y) > 1:
				continue
			if collected and not opened:
				_offer(queue, seen, [f, cell.x, cell.y, switch_mask, mech_mask | 2])

	return {"reached_boss": reached_boss, "visited": visited, "states_explored": queue.size()}


func test_control_entrance_and_boss_cell_are_found() -> void:
	assert_ne(_entrance_cell(), Vector2i(-1, -1), "CONTROL: floor 1 must declare an entrance")
	assert_ne(_find_char(TOTAL_FLOORS, "B"), Vector2i(-1, -1), "CONTROL: the 'B' marker must parse on the boss floor")


func test_control_floor_3_declares_a_lever_and_floor_4_a_key_and_door() -> void:
	var switches := DungeonPuzzleLayer.scan_switches(_cave.floor_layouts)
	var floor3_levers := 0
	for sw in switches:
		if int(sw["floor"]) == 3 and str(sw["kind"]) == "lever":
			floor3_levers += 1
	assert_eq(floor3_levers, 1, "CONTROL: floor 3 must carry exactly one lever")

	var pickups := DungeonMechanics.scan_pickups(_cave.floor_layouts)
	var locks := DungeonMechanics.scan_locks(_cave.floor_layouts)
	var floor4_keys := 0
	var floor4_doors := 0
	for pk in pickups:
		if int(pk["floor"]) == 4 and str(pk["resource"]) == "key":
			floor4_keys += 1
	for lk in locks:
		if int(lk["floor"]) == 4 and str(lk["resource"]) == "key":
			floor4_doors += 1
	assert_eq(floor4_keys, 1, "CONTROL: floor 4 must carry exactly one key pickup")
	assert_eq(floor4_doors, 1, "CONTROL: floor 4 must carry exactly one locked door")


func test_the_boss_is_reachable_with_every_mechanic_available() -> void:
	var result := _solve()
	assert_gt(int(result["states_explored"]), 10, "CONTROL: too few states explored -- the BFS is probably broken")
	assert_true(bool(result["reached_boss"]), "the Cave Rat King must be reachable from the entrance using the lever and the key")


func test_floor_3_exit_stairs_require_the_lever() -> void:
	var exit_cell := _find_char(3, "U")
	assert_ne(exit_cell, Vector2i(-1, -1), "floor 3 must have an exit stairs ('U') marker")
	var full := _solve()
	var key := "3:%d:%d" % [exit_cell.x, exit_cell.y]
	assert_true((full["visited"] as Dictionary).has(key), "the full solve must reach floor 3's exit stairs")
	var blocked := _solve(true, false)
	assert_false((blocked["visited"] as Dictionary).has(key),
		"disabling floor 3's lever must make its exit stairs unreachable -- the gate is a no-op otherwise")


func test_floor_4_exit_stairs_require_the_key() -> void:
	var exit_cell := _find_char(4, "U")
	assert_ne(exit_cell, Vector2i(-1, -1), "floor 4 must have an exit stairs ('U') marker")
	var full := _solve()
	var key := "4:%d:%d" % [exit_cell.x, exit_cell.y]
	assert_true((full["visited"] as Dictionary).has(key), "the full solve must reach floor 4's exit stairs")
	var blocked := _solve(false, true)
	assert_false((blocked["visited"] as Dictionary).has(key),
		"disabling floor 4's key pickup must make its exit stairs unreachable -- the gate is a no-op otherwise")


func test_floor_3_and_4_lore_signposts_are_declared() -> void:
	assert_true((_cave._LORE as Dictionary).has(3), "floor 3 must carry a lore signpost near its lever")
	assert_true((_cave._LORE as Dictionary).has(4), "floor 4 must carry a lore signpost near its key")
