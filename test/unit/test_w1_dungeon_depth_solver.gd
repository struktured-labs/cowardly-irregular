extends GutTest

## Load-bearing solver for the W1 depth pass (struktured 2026-09-06).
##
## BFS over (floor, cell, switch-activation-mask) using each dungeon's REAL
## floor_layouts / switch_effects / portal_links / trap_chests -- not a
## hand-simplified model of them. Mirrors test_contrarian_depths_solver.gd's
## shape across all five W1 story dungeons: the four dragon caves plus
## Castle Harmonia. Proves entrance -> boss reachability, every T/S/L/portal
## marker sits on a real floor tile, every trap_chests key matches a real
## treasure marker, and every dungeon kept its 4-5 floor depth.

const DUNGEON_DIR := "res://src/maps/dungeons/"
const DUNGEONS := {
	"fire_dragon_cave": "FireDragonCave.gd",
	"ice_dragon_cave": "IceDragonCave.gd",
	"lightning_dragon_cave": "LightningDragonCave.gd",
	"shadow_dragon_cave": "ShadowDragonCave.gd",
	"castle_harmonia": "CastleHarmonia.gd",
}
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const TileGeneratorClass = preload("res://src/exploration/TileGenerator.gd")

var _caves: Dictionary = {}


func before_each() -> void:
	_caves.clear()
	for id in DUNGEONS:
		var cave = load(DUNGEON_DIR + DUNGEONS[id]).new()
		autofree(cave)
		_caves[id] = cave


func _switch_bit_index(cave) -> Dictionary:
	var keys: Array = (cave.switch_effects as Dictionary).keys()
	keys.sort()
	assert_lt(keys.size(), 20, "sanity: bitmask assumes a small switch count")
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
	var key := "%d:%d:%d:%d:%d" % state
	if seen.has(key):
		return
	seen[key] = true
	queue.append(state)


## DungeonMechanics pickups (K/Q) and locks (G/Z) each get one bit in a second mask, same
## shape as _switch_bit_index -- pickup bits are set on first visit, lock bits are set once
## DungeonMechanics.resource_available says a matching resource hasn't already been spent.
func _mech_bit_index(cave) -> Dictionary:
	var out := {}
	var i := 0
	for pk in DungeonMechanics.scan_pickups(cave.floor_layouts):
		out[str(pk["id"])] = i
		i += 1
	for lk in DungeonMechanics.scan_locks(cave.floor_layouts):
		out[str(lk["id"])] = i
		i += 1
	assert_lt(i, 20, "sanity: mechanics bitmask assumes a small pickup/lock count")
	return out


func _mech_dicts(mech_mask: int, mech_bits: Dictionary, pickups: Array, locks: Array) -> Array:
	var collected := {}
	var opened := {}
	var pk_ids := {}
	for pk in pickups:
		pk_ids[str(pk["id"])] = true
	for id in mech_bits:
		if not (mech_mask & (1 << int(mech_bits[id]))):
			continue
		if pk_ids.has(id):
			collected[id] = true
		else:
			opened[id] = true
	return [collected, opened]


## True if `n` can be entered given the base cave mechanics plus DungeonMechanics locks --
## a G/Z cell is walkable only once DungeonMechanics.resource_available cleared it.
func _walkable_with_mechanics(cave, f: int, n: Vector2i, active: Dictionary, opened: Dictionary, locks: Array) -> bool:
	var ch := _char_here(cave, f, n)
	if ch == "":
		return false
	if DungeonMechanics.RESOURCE_FOR_LOCK.has(ch):
		var lid := DungeonMechanics.lock_id_at(locks, f, n)
		return lid != "" and bool(opened.get(lid, false))
	return DungeonPuzzleLayer.is_walkable(cave.floor_layouts, cave.switch_effects, f, n, active)


## Mirrors DragonCave._transition_to_floor's landing rule exactly: ascend via
## 'U' lands on the next floor's 'D', descend via 'D' on floor > 1 lands on
## the floor below's 'U' (floor 1's landing is the authored entrance).
func _solve(cave, allow_portals: bool, disabled_switches: Array = [], disabled_pickups: Array = []) -> Dictionary:
	var bit_index := _switch_bit_index(cave)
	for sw_id in disabled_switches:
		bit_index.erase(sw_id)
	var mech_bits := _mech_bit_index(cave)
	for pk_id in disabled_pickups:
		mech_bits.erase(pk_id)
	var pickups := DungeonMechanics.scan_pickups(cave.floor_layouts)
	var locks := DungeonMechanics.scan_locks(cave.floor_layouts)
	var start_cell := _entrance_cell(cave)
	var seen := {"1:%d:%d:0:0" % [start_cell.x, start_cell.y]: true}
	var queue: Array = [[1, start_cell.x, start_cell.y, 0, 0]]
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
		var mech_mask: int = state[4]
		visited_cells["%d:%d:%d" % [f, cell.x, cell.y]] = true
		if f == cave.total_floors and cell == boss_cell:
			reached_boss = true
		var active := _active_dict(mask, bit_index)
		var mech_dicts := _mech_dicts(mech_mask, mech_bits, pickups, locks)
		var collected: Dictionary = mech_dicts[0]
		var opened: Dictionary = mech_dicts[1]

		for d in DIRS:
			var n: Vector2i = cell + d
			if _walkable_with_mechanics(cave, f, n, active, opened, locks):
				_offer(queue, seen, [f, n.x, n.y, mask, mech_mask])

		var ch_here := _char_here(cave, f, cell)
		if ch_here == "U" and f + 1 <= cave.total_floors:
			var land := _find_char(cave, f + 1, "D")
			if land != Vector2i(-1, -1):
				_offer(queue, seen, [f + 1, land.x, land.y, mask, mech_mask])
		elif ch_here == "D" and f > 1:
			var land2 := _find_char(cave, f - 1, "U")
			if land2 == Vector2i(-1, -1) and f - 1 == 1:
				land2 = start_cell
			if land2 != Vector2i(-1, -1):
				_offer(queue, seen, [f - 1, land2.x, land2.y, mask, mech_mask])

		var sw_id := _switch_id_at(cave, f, cell)
		if sw_id != "" and bit_index.has(sw_id):
			var new_mask: int = mask | (1 << int(bit_index[sw_id]))
			if new_mask != mask:
				_offer(queue, seen, [f, cell.x, cell.y, new_mask, mech_mask])

		var pk_id := DungeonMechanics.pickup_id_at(pickups, f, cell)
		if pk_id != "" and mech_bits.has(pk_id) and not (mech_mask & (1 << int(mech_bits[pk_id]))):
			_offer(queue, seen, [f, cell.x, cell.y, mask, mech_mask | (1 << int(mech_bits[pk_id]))])

		for lk in locks:
			if int(lk["floor"]) != f:
				continue
			var lcell: Vector2i = lk["cell"]
			var lid: String = str(lk["id"])
			if not mech_bits.has(lid) or (mech_mask & (1 << int(mech_bits[lid]))):
				continue
			if absi(cell.x - lcell.x) + absi(cell.y - lcell.y) > 1:
				continue  # must be standing on or adjacent to the lock to interact with it
			if DungeonMechanics.resource_available(str(lk["resource"]), pickups, locks, collected, opened):
				_offer(queue, seen, [f, cell.x, cell.y, mask, mech_mask | (1 << int(mech_bits[lid]))])

		if allow_portals:
			var dest := DungeonPuzzleLayer.portal_destination(cave.floor_layouts, cave.portal_links, f, cell)
			if not dest.is_empty() and DungeonPuzzleLayer.portal_usable(cave.switch_effects, cave.floor_layouts, f, cell, active):
				var dcell: Vector2i = dest["cell"]
				_offer(queue, seen, [int(dest["floor"]), dcell.x, dcell.y, mask, mech_mask])

	return {"reached_boss": reached_boss, "states_explored": queue.size(), "visited_cells": visited_cells}


func test_control_boss_cell_and_entrance_are_found_in_every_dungeon() -> void:
	for id in DUNGEONS:
		var cave = _caves[id]
		assert_ne(_boss_cell(cave), Vector2i(-1, -1), "%s: CONTROL: the 'B' marker must parse on the final floor" % id)
		assert_ne(_entrance_cell(cave), Vector2i(-1, -1), "%s: CONTROL: floor 1 must declare an entrance" % id)


func test_boss_is_reachable_from_the_entrance_in_every_dungeon() -> void:
	for id in DUNGEONS:
		var cave = _caves[id]
		var result := _solve(cave, true)
		assert_gt(int(result["states_explored"]), 20,
			"%s: CONTROL: too few states explored (%d) -- the BFS itself is probably broken" % [id, int(result["states_explored"])])
		assert_true(bool(result["reached_boss"]), "%s: the boss must be reachable from the entrance using the full mechanic set" % id)


## Mutation control (struktured 2026-10-06 maze pass): proves the solver's lock modeling is
## load-bearing, not vacuous. With the matching pickup disabled, every DungeonMechanics lock
## cell in the dungeon must drop OUT of the reachable set; with it enabled, it must be IN.
func test_a_locked_cell_is_reachable_only_once_its_resource_is_collectible() -> void:
	var dungeons_with_locks := 0
	for id in DUNGEONS:
		var cave = _caves[id]
		var locks := DungeonMechanics.scan_locks(cave.floor_layouts)
		if locks.is_empty():
			continue
		dungeons_with_locks += 1
		var pickups := DungeonMechanics.scan_pickups(cave.floor_layouts)
		var pickup_ids: Array = []
		for pk in pickups:
			pickup_ids.append(str(pk["id"]))
		var without := _solve(cave, true, [], pickup_ids)
		var with_resource := _solve(cave, true, [], [])
		for lk in locks:
			var key := "%d:%d:%d" % [int(lk["floor"]), (lk["cell"] as Vector2i).x, (lk["cell"] as Vector2i).y]
			assert_false((without["visited_cells"] as Dictionary).has(key),
				"%s: lock '%s' must NOT be steppable with its resource disabled -- the solver's lock gating is a no-op otherwise" % [id, str(lk["id"])])
			assert_true((with_resource["visited_cells"] as Dictionary).has(key),
				"%s: lock '%s' must be steppable once its resource is collectible" % [id, str(lk["id"])])
	assert_gt(dungeons_with_locks, 0, "CONTROL: at least one W1 dungeon must carry a DungeonMechanics lock, or this test is vacuous")


func test_floor_count_is_at_least_four_in_every_dungeon() -> void:
	for id in DUNGEONS:
		var cave = _caves[id]
		assert_gte(int(cave.total_floors), 4, "%s: dragon dungeons and Castle Harmonia must be 4-5 floors deep now, got %d" % [id, int(cave.total_floors)])


func test_boss_sits_only_on_the_final_floor() -> void:
	for id in DUNGEONS:
		var cave = _caves[id]
		for f in (cave.floor_layouts as Dictionary):
			var pos := _find_char(cave, int(f), "B")
			if pos == Vector2i(-1, -1):
				continue
			assert_eq(int(f), int(cave.total_floors), "%s: a 'B' marker on floor %s is not the last floor (%d)" % [id, str(f), int(cave.total_floors)])


func test_every_marker_sits_on_a_real_floor_tile() -> void:
	var checked := 0
	for id in DUNGEONS:
		var cave = _caves[id]
		for f in (cave.floor_layouts as Dictionary):
			var rows: Array = cave.floor_layouts[f]
			for y in range(rows.size()):
				var row: String = rows[y]
				for x in range(row.length()):
					var ch := row[x]
					if ch in ["T", "S", "L", "a", "b", "c", "d", "e", "f"]:
						checked += 1
						var tile_type: int = cave._char_to_tile_type(ch)
						assert_eq(tile_type, TileGeneratorClass.TileType.CAVE_FLOOR,
							"%s floor %s (%d,%d) '%s' must resolve to a walkable floor tile" % [id, str(f), x, y, ch])
	assert_gt(checked, 20, "CONTROL: too few markers scanned -- the sweep itself is probably broken")


func test_every_marker_is_in_bounds_and_shape_is_20x16() -> void:
	var offenders: Array = []
	for id in DUNGEONS:
		var cave = _caves[id]
		for f in (cave.floor_layouts as Dictionary):
			var rows: Array = cave.floor_layouts[f]
			if rows.size() != cave.MAP_HEIGHT:
				offenders.append("%s floor %s has %d rows, expected %d" % [id, str(f), rows.size(), cave.MAP_HEIGHT])
			for y in range(rows.size()):
				var row: String = rows[y]
				if row.length() != cave.MAP_WIDTH:
					offenders.append("%s floor %s row %d has %d chars, expected %d" % [id, str(f), y, row.length(), cave.MAP_WIDTH])
	assert_eq(offenders, [], "every floor must be a real 20x16 grid: %s" % str(offenders))


func test_every_dungeon_declares_a_portal_pair_a_flip_switch_and_a_trap() -> void:
	for id in DUNGEONS:
		var cave = _caves[id]
		var portal_errors := DungeonPuzzleLayer.validate_portal_pairs(cave.floor_layouts, cave.portal_links)
		assert_eq(portal_errors, [], "%s: portal table must be internally consistent: %s" % [id, str(portal_errors)])
		var portals := DungeonPuzzleLayer.scan_portals(cave.floor_layouts)
		assert_gt(portals.size(), 0, "%s: must declare at least one portal pair" % id)
		var has_flip := false
		var has_trap := false
		for sw_id in (cave.switch_effects as Dictionary):
			var eff: Dictionary = cave.switch_effects[sw_id]
			if eff.has("flip"):
				has_flip = true
			if eff.has("trap"):
				has_trap = true
		assert_true(has_flip, "%s: must declare at least one flip-switch (S plate or L lever)" % id)
		assert_true(has_trap, "%s: must declare at least one trap (a switch trap or a mimic chest)" % id)


func test_at_least_two_dungeons_carry_a_mimic_chest() -> void:
	var with_mimic := 0
	for id in DUNGEONS:
		var cave = _caves[id]
		if not (cave.trap_chests as Array).is_empty():
			with_mimic += 1
	assert_gte(with_mimic, 2, "at least two of the five W1 dungeons must carry a mimic chest (trap_chests)")


func test_every_trap_chest_key_matches_a_real_treasure_marker() -> void:
	for id in DUNGEONS:
		var cave = _caves[id]
		var placed: Dictionary = {}
		for f in (cave.floor_layouts as Dictionary):
			var idx := 0
			var rows: Array = cave.floor_layouts[f]
			for y in range(rows.size()):
				var row: String = rows[y]
				for x in range(row.length()):
					if row[x] == "T":
						placed["%s_f%s_c%d" % [cave.cave_id, str(f), idx]] = true
						idx += 1
		for key in (cave.trap_chests as Array):
			assert_true(placed.has(key), "%s: trap_chests entry '%s' has no matching T marker" % [id, key])
		var real_chests: int = placed.size() - (cave.trap_chests as Array).size()
		assert_gte(real_chests, 2, "%s: must keep at least two REAL (non-mimic) chests" % id)


## Data-integrity companion to the mutation control above: a lock with no matching pickup anywhere
## in the dungeon is a dead prop by construction, independent of maze shape -- authored, not derived.
func test_every_lock_has_at_least_one_matching_resource_pickup() -> void:
	var checked := 0
	for id in DUNGEONS:
		var cave = _caves[id]
		var pickups := DungeonMechanics.scan_pickups(cave.floor_layouts)
		var locks := DungeonMechanics.scan_locks(cave.floor_layouts)
		var have_counts := {}
		for pk in pickups:
			var r: String = str(pk["resource"])
			have_counts[r] = int(have_counts.get(r, 0)) + 1
		var need_counts := {}
		for lk in locks:
			var r2: String = str(lk["resource"])
			need_counts[r2] = int(need_counts.get(r2, 0)) + 1
		for r3 in need_counts:
			checked += 1
			assert_gte(int(have_counts.get(r3, 0)), int(need_counts[r3]),
				"%s: %d '%s' lock(s) but only %d matching pickup(s) -- at least one lock is unopenable" % [id, int(need_counts[r3]), r3, int(have_counts.get(r3, 0))])
	assert_gt(checked, 0, "CONTROL: at least one W1 dungeon must declare a lock, or this test is vacuous")


func _resolvable_item_ids() -> Dictionary:
	var ok: Dictionary = {}
	var items_file := FileAccess.open("res://data/items.json", FileAccess.READ)
	var items = JSON.parse_string(items_file.get_as_text())
	items_file.close()
	if items is Dictionary:
		for iid in (items as Dictionary).keys():
			ok[iid] = true
	var equip_file := FileAccess.open("res://data/equipment.json", FileAccess.READ)
	var equipment = JSON.parse_string(equip_file.get_as_text())
	equip_file.close()
	if equipment is Dictionary:
		for cat in ["weapons", "armors", "accessories"]:
			for eid in (equipment as Dictionary).get(cat, {}):
				ok[eid] = true
	return ok


func test_every_forced_item_chest_id_resolves() -> void:
	var ok := _resolvable_item_ids()
	assert_gt(ok.size(), 0, "CONTROL: parsed item/equipment ids -- zero makes this vacuous")
	var checked := 0
	for id in DUNGEONS:
		var cave = _caves[id]
		var placed: Dictionary = {}
		for f in (cave.floor_layouts as Dictionary):
			var idx := 0
			var rows: Array = cave.floor_layouts[f]
			for y in range(rows.size()):
				var row: String = rows[y]
				for x in range(row.length()):
					if row[x] == "T":
						placed["%s_f%s_c%d" % [cave.cave_id, str(f), idx]] = true
						idx += 1
		for key in (cave.forced_item_chests as Dictionary):
			assert_true(placed.has(key), "%s: forced_item_chests entry '%s' has no matching T marker" % [id, key])
			var value: String = str(cave.forced_item_chests[key])
			var item_id: String = value.substr(10) if value.begins_with("equipment:") else value
			checked += 1
			assert_true(ok.has(item_id), "%s: forced_item_chests['%s'] = '%s' does not resolve in items/equipment" % [id, key, value])
	assert_gt(checked, 5, "CONTROL: too few forced_item_chests entries checked")
