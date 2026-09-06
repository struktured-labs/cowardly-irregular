extends GutTest

## Load-bearing solver for The Backwards Warren (struktured 2026-09-06).
##
## BFS over (floor, cell, switch-activation-mask) using the dungeon's REAL
## floor_layouts / switch_effects / portal_links / trap_chests -- not a
## hand-simplified model of them. Proves two things a screenshot cannot:
##   1. the boss is reachable from the entrance at all.
##   2. it is NOT reachable with portal use disabled -- so "go down to go
##      up" is a genuine gate, not set dressing.
##
## Constructed but never added to the scene tree: _init() only assigns plain
## data, so this needs no autoload and cannot be confused with a live-scene
## smoke test (that's test_dungeon_constructs_at_runtime + the puzzle-layer
## regression file).

const ContrarianDepthsScript = preload("res://src/maps/dungeons/ContrarianDepths.gd")
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _cave


func before_each() -> void:
	_cave = ContrarianDepthsScript.new()
	autofree(_cave)


func _switch_bit_index() -> Dictionary:
	var keys: Array = _cave.switch_effects.keys()
	keys.sort()
	assert_lt(keys.size(), 20, "sanity: bitmask assumes a small switch count")
	var out := {}
	for i in range(keys.size()):
		out[keys[i]] = i
	return out


func _switch_id_at(floor_num: int, cell: Vector2i) -> String:
	for sw in DungeonPuzzleLayer.scan_switches(_cave.floor_layouts):
		if int(sw["floor"]) == floor_num and (sw["cell"] as Vector2i) == cell:
			return str(sw["id"])
	return ""


func _active_dict(mask: int, bit_index: Dictionary) -> Dictionary:
	var d := {}
	for sw_id in bit_index:
		if mask & (1 << int(bit_index[sw_id])):
			d[sw_id] = true
	return d


func _find_char(floor_num: int, ch: String) -> Vector2i:
	if not (_cave.floor_layouts as Dictionary).has(floor_num):
		return Vector2i(-1, -1)
	var rows: Array = _cave.floor_layouts[floor_num]
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


func _boss_cell() -> Vector2i:
	return _find_char(_cave.total_floors, "B")


func _entrance_cell() -> Vector2i:
	var sp: Vector2 = _cave.floor_spawn_points[1]["entrance"]
	return Vector2i(int(sp.x), int(sp.y))


func _offer(queue: Array, seen: Dictionary, state: Array) -> void:
	var key := "%d:%d:%d:%d" % state
	if seen.has(key):
		return
	seen[key] = true
	queue.append(state)


## BFS over (floor, x, y, switch-mask). Transitions: cardinal moves (respecting
## live flip state), U/D stairs (mirrors DragonCave._transition_to_floor's
## landing rule exactly: ascend via 'U' lands on the next floor's 'D', descend
## via 'D' on floor > 1 lands on the floor below's 'U'), switch activation
## while standing on it, and (if allow_portals) portal warps when usable.
## `disabled_switches` pretends those ids can never be thrown -- used to prove
## a specific switch is load-bearing, not just present.
func _solve(allow_portals: bool, disabled_switches: Array = []) -> Dictionary:
	var bit_index := _switch_bit_index()
	for sw_id in disabled_switches:
		bit_index.erase(sw_id)
	var start_cell := _entrance_cell()
	var seen := {"1:%d:%d:0" % [start_cell.x, start_cell.y]: true}
	var queue: Array = [[1, start_cell.x, start_cell.y, 0]]
	var boss_cell := _boss_cell()
	var reached_boss := false
	var head := 0
	while head < queue.size():
		var state: Array = queue[head]
		head += 1
		var f: int = state[0]
		var cell := Vector2i(state[1], state[2])
		var mask: int = state[3]
		if f == _cave.total_floors and cell == boss_cell:
			reached_boss = true
		var active := _active_dict(mask, bit_index)

		for d in DIRS:
			var n: Vector2i = cell + d
			if DungeonPuzzleLayer.is_walkable(_cave.floor_layouts, _cave.switch_effects, f, n, active):
				_offer(queue, seen, [f, n.x, n.y, mask])

		var ch_here := _char_here(f, cell)
		if ch_here == "U" and f + 1 <= _cave.total_floors:
			var land := _find_char(f + 1, "D")
			if land != Vector2i(-1, -1):
				_offer(queue, seen, [f + 1, land.x, land.y, mask])
		elif ch_here == "D" and f > 1:
			var land2 := _find_char(f - 1, "U")
			if land2 == Vector2i(-1, -1) and f - 1 == 1:
				land2 = start_cell
			if land2 != Vector2i(-1, -1):
				_offer(queue, seen, [f - 1, land2.x, land2.y, mask])

		var sw_id := _switch_id_at(f, cell)
		if sw_id != "" and bit_index.has(sw_id):
			var new_mask: int = mask | (1 << int(bit_index[sw_id]))
			if new_mask != mask:
				_offer(queue, seen, [f, cell.x, cell.y, new_mask])

		if allow_portals:
			var dest := DungeonPuzzleLayer.portal_destination(_cave.floor_layouts, _cave.portal_links, f, cell)
			if not dest.is_empty() and DungeonPuzzleLayer.portal_usable(_cave.switch_effects, _cave.floor_layouts, f, cell, active):
				var dcell: Vector2i = dest["cell"]
				_offer(queue, seen, [int(dest["floor"]), dcell.x, dcell.y, mask])

	return {"reached_boss": reached_boss, "states_explored": queue.size()}


func test_control_boss_cell_and_entrance_are_found() -> void:
	assert_ne(_boss_cell(), Vector2i(-1, -1), "CONTROL: the 'B' marker must parse on the final floor")
	assert_eq(_entrance_cell(), Vector2i(6, 13), "CONTROL: floor 1's authored entrance")


func test_boss_is_reachable_from_the_entrance() -> void:
	var result := _solve(true)
	assert_gt(int(result["states_explored"]), 20,
		"CONTROL: too few states explored (%d) -- the BFS itself is probably broken, not the dungeon" % int(result["states_explored"]))
	assert_true(bool(result["reached_boss"]), "the boss must be reachable from the entrance using the full mechanic set")


func test_boss_is_not_reachable_without_using_a_portal() -> void:
	var result := _solve(false)
	assert_false(bool(result["reached_boss"]),
		"floor 4 (the boss floor) has no stairs at all -- reachability without portals would mean the puzzle is decorative")


func test_the_critical_path_actually_needs_the_vault_lever() -> void:
	# Portals allowed, but sw2 (the lever that opens the vault door guarding
	# portal 'b') can never be thrown -- so portal 'b' stays sealed behind its wall.
	var result := _solve(true, ["sw2"])
	assert_false(bool(result["reached_boss"]),
		"with sw2 disabled, portal 'b' must stay behind its wall and the boss must be unreachable")


func test_the_critical_path_does_not_actually_need_the_decoy_switch() -> void:
	# sw3 (floor3's trap plate) is a red herring -- disabling it must NOT block the win.
	var result := _solve(true, ["sw3"])
	assert_true(bool(result["reached_boss"]),
		"sw3 is a decoy/trap switch -- the boss must remain reachable without ever touching it")


func test_every_portal_and_switch_marker_is_in_bounds() -> void:
	var offenders: Array = []
	for f in _cave.floor_layouts:
		var rows: Array = _cave.floor_layouts[f]
		if rows.size() != _cave.MAP_HEIGHT:
			offenders.append("floor %s has %d rows, expected %d" % [str(f), rows.size(), _cave.MAP_HEIGHT])
		for y in range(rows.size()):
			var row: String = rows[y]
			if row.length() != _cave.MAP_WIDTH:
				offenders.append("floor %s row %d has %d chars, expected %d" % [str(f), y, row.length(), _cave.MAP_WIDTH])
	var portals := DungeonPuzzleLayer.scan_portals(_cave.floor_layouts)
	for ch in portals:
		for e in (portals[ch] as Array):
			var c: Vector2i = e["cell"]
			if c.x < 0 or c.x >= _cave.MAP_WIDTH or c.y < 0 or c.y >= _cave.MAP_HEIGHT:
				offenders.append("portal '%s' at %s is out of bounds" % [ch, str(c)])
	for sw in DungeonPuzzleLayer.scan_switches(_cave.floor_layouts):
		var c: Vector2i = sw["cell"]
		if c.x < 0 or c.x >= _cave.MAP_WIDTH or c.y < 0 or c.y >= _cave.MAP_HEIGHT:
			offenders.append("switch '%s' at %s is out of bounds" % [sw["id"], str(c)])
	assert_eq(offenders, [], "every marker must sit on a real, in-bounds floor cell: %s" % str(offenders))


func test_every_trap_chest_key_matches_a_real_treasure_marker() -> void:
	var placed: Dictionary = {}
	for f in _cave.floor_layouts:
		var idx := 0
		var rows: Array = _cave.floor_layouts[f]
		for y in range(rows.size()):
			var row: String = rows[y]
			for x in range(row.length()):
				if row[x] == "T":
					placed["%s_f%d_c%d" % [_cave.cave_id, int(f), idx]] = true
					idx += 1
	assert_gt((_cave.trap_chests as Array).size(), 0, "CONTROL: the showcase dungeon must declare at least one mimic")
	for key in _cave.trap_chests:
		assert_true(placed.has(key), "trap_chests entry '%s' has no matching T marker" % key)
	var real_chests: int = placed.size() - (_cave.trap_chests as Array).size()
	assert_gte(real_chests, 2, "the showcase dungeon must keep at least two REAL (non-mimic) chests")
