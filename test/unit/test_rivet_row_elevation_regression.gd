extends GutTest

## Elevation regression for Rivet Row's loading-dock tier (2026-09-06, CrossCode pass extension).
## Pins height_data/map_data dims, tier count, ramp legality, and save-point reachability —
## the FreightElevator counts as an extra edge alongside _can_step so the flood fill doesn't
## falsely report the dock unreachable if the ramp regresses.

const RIVET_ROW := "res://src/maps/villages/RivetRowVillage.gd"
const HeightGridScript := preload("res://src/exploration/HeightGrid.gd")
const TILE := 32

var _v: Node


func before_each() -> void:
	_v = load(RIVET_ROW).new()
	add_child_autofree(_v)
	await get_tree().process_frame
	await get_tree().process_frame


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE)), int(floor(pos.y / TILE)))


func _elevator_edges() -> Array:
	var edges: Array = []
	for b in _v.buildings.get_children():
		if "bottom_position" in b and "top_position" in b:
			edges.append([_cell(b.bottom_position), _cell(b.top_position)])
	return edges


func _flood_with_elevators(start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var queue: Array = [start]
	var head := 0
	var edges := _elevator_edges()
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + step
			if not seen.has(n) and _v._can_step(cur, n):
				seen[n] = true
				queue.append(n)
		for pair in edges:
			var a: Vector2i = pair[0]
			var b: Vector2i = pair[1]
			if cur == a and not seen.has(b):
				seen[b] = true
				queue.append(b)
			elif cur == b and not seen.has(a):
				seen[a] = true
				queue.append(a)
	return seen


func test_height_data_matches_map_data_dims() -> void:
	assert_eq(_v._height_grid.size(), 20, "20 height rows")
	for row in _v._height_grid:
		assert_eq((row as Array).size(), 26, "26 cols per height row")


func test_at_least_two_distinct_tiers() -> void:
	var seen := {}
	for row in _v._height_grid:
		for h in row:
			seen[h] = true
	assert_gte(seen.size(), 2, "dock tier1 and the yard tier0 must both appear")


func test_every_ramp_connects_tiers_exactly_one_apart() -> void:
	var checked := 0
	for cell in _v._stair_cells:
		var own_h: int = HeightGridScript.height_at(_v._height_grid, cell)
		var bridges_a_step := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + d
			var nh: int = HeightGridScript.height_at(_v._height_grid, n)
			if nh < 0:
				continue
			assert_lte(absi(nh - own_h), 1, "ramp %s neighbour %s must not jump more than one tier" % [cell, n])
			if absi(nh - own_h) == 1:
				bridges_a_step = true
		assert_true(bridges_a_step, "ramp %s must actually bridge a one-tier step" % cell)
		checked += 1
	assert_gt(checked, 0, "control: at least one ramp checked")


func test_elevator_has_two_endpoints_on_different_tiers() -> void:
	var edges := _elevator_edges()
	assert_gt(edges.size(), 0, "control: FreightElevator must be found under buildings")
	for pair in edges:
		var ha: int = HeightGridScript.height_at(_v._height_grid, pair[0])
		var hb: int = HeightGridScript.height_at(_v._height_grid, pair[1])
		assert_ne(ha, hb, "elevator endpoints %s/%s must sit on different tiers" % [pair[0], pair[1]])


func test_save_point_reachable_from_spawn() -> void:
	var start := _cell(_v.spawn_points["default"])
	var reachable := _flood_with_elevators(start)
	assert_gt(reachable.size(), 100, "control: flood must cover most of the village, not just the spawn cell")
	var save_cell := _cell(_v._get_save_point_position())
	assert_true(reachable.has(save_cell), "save point %s must be reachable from spawn %s" % [save_cell, start])
	var dock_cell := _cell(_v.spawn_points["dock_tier"])
	assert_true(reachable.has(dock_cell), "the dock tier itself must be reachable from spawn")
