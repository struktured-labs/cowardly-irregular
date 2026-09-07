extends GutTest

## Frosthold's ice-terrace elevation pass (2026-09-06): overlook (tier 2) / ice shelf (tier 1) /
## tundra floor (tier 0), '^' stairs cascade down at (8,8)/(20,8) then (12,12)/(18,12).

const HG := preload("res://src/exploration/HeightGrid.gd")
const TILE := 32
const STAIRS := [Vector2i(8, 8), Vector2i(20, 8), Vector2i(12, 12), Vector2i(18, 12)]

var _v: Node


func before_each() -> void:
	_v = FrostholdVillageScene.new()
	add_child_autofree(_v)
	await get_tree().process_frame
	await get_tree().process_frame


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE)), int(floor(pos.y / TILE)))


func test_height_data_matches_map_dimensions() -> void:
	assert_eq(_v._height_grid.size(), FrostholdVillageScene.MAP_HEIGHT, "height rows == MAP_HEIGHT")
	for row in _v._height_grid:
		assert_eq((row as Array).size(), FrostholdVillageScene.MAP_WIDTH, "each height row == MAP_WIDTH")


func test_at_least_two_tiers_exist() -> void:
	var tiers := {}
	for row in _v._height_grid:
		for h in row:
			tiers[h] = true
	assert_gte(tiers.size(), 2, "overlook / shelf / tundra are distinct tiers")


func test_stairs_connect_tiers_exactly_one_apart() -> void:
	assert_eq(_v._stair_cells.size(), STAIRS.size())
	for s in STAIRS:
		assert_true(_v._stair_cells.has(s), "stair at %s" % s)
		assert_true(_v._is_cell_walkable(s), "stair %s walkable" % s)
		var bridged := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var hn := HG.height_at(_v._height_grid, s + d)
			if hn < 0:
				continue
			assert_lte(absi(hn - HG.height_at(_v._height_grid, s)), 1, "stair %s never bridges a two-tier jump" % s)
			if absi(hn - HG.height_at(_v._height_grid, s)) == 1:
				bridged = true
		assert_true(bridged, "stair %s actually bridges a one-tier step" % s)


func test_save_point_reachable_from_spawn() -> void:
	var start := _cell(_v.spawn_points["default"])
	var target := _cell(_v._get_save_point_position())
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and _v._can_step(c, n):
				seen[n] = true
				queue.append(n)
	assert_true(seen.has(target), "save point at %s reachable from spawn %s" % [target, start])
