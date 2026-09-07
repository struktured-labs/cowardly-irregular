extends GutTest

## Sandrift's low sandstone mesa elevation pass (2026-09-06): the Elder's Tent overlooks the
## oasis from a raised ledge (tier 1), '/' dune-climbs at (17,12) and (21,12) flank the tent.
## Also regression-pins the save point move off (13,10), which was oasis WATER (unreachable).

const HG := preload("res://src/exploration/HeightGrid.gd")
const TILE := 32
const RAMPS := [Vector2i(17, 12), Vector2i(21, 12)]

var _v: Node


func before_each() -> void:
	_v = SandriftVillageScene.new()
	add_child_autofree(_v)
	await get_tree().process_frame
	await get_tree().process_frame


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE)), int(floor(pos.y / TILE)))


func test_height_data_matches_map_dimensions() -> void:
	assert_eq(_v._height_grid.size(), SandriftVillageScene.MAP_HEIGHT, "height rows == MAP_HEIGHT")
	for row in _v._height_grid:
		assert_eq((row as Array).size(), SandriftVillageScene.MAP_WIDTH, "each height row == MAP_WIDTH")


func test_at_least_two_tiers_exist() -> void:
	var tiers := {}
	for row in _v._height_grid:
		for h in row:
			tiers[h] = true
	assert_gte(tiers.size(), 2, "mesa and desert floor are distinct tiers")


func test_ramps_connect_tiers_exactly_one_apart() -> void:
	assert_eq(_v._stair_cells.size(), RAMPS.size())
	for s in RAMPS:
		assert_true(_v._stair_cells.has(s), "dune-climb at %s" % s)
		assert_true(_v._is_cell_walkable(s), "dune-climb %s walkable" % s)
		var bridged := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var hn := HG.height_at(_v._height_grid, s + d)
			if hn < 0:
				continue
			assert_lte(absi(hn - HG.height_at(_v._height_grid, s)), 1, "ramp %s never bridges a two-tier jump" % s)
			if absi(hn - HG.height_at(_v._height_grid, s)) == 1:
				bridged = true
		assert_true(bridged, "ramp %s actually bridges a one-tier step" % s)


func test_save_point_off_water_and_reachable_from_spawn() -> void:
	var target := _cell(_v._get_save_point_position())
	assert_ne(target, Vector2i(13, 10), "regression: save point must not sit back on the oasis water cell")
	assert_true(_v._is_cell_walkable(target), "save point cell is walkable")
	var start := _cell(_v.spawn_points["default"])
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
