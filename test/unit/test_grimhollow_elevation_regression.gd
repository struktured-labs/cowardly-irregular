extends GutTest

## Grimhollow's sunken hollow (struktured 2026-09-06): a switchback spiral descent (rim -> floor)
## in the NE corner. Pins the tier count, ramp legality, and that the rim spawn can actually
## walk the spiral down to the save point, crossing ramps at multiple distinct heights.

const GRIMHOLLOW_SCRIPT := "res://src/maps/villages/GrimhollowVillage.gd"
const HG := preload("res://src/exploration/HeightGrid.gd")
const TILE := 32.0

var _v: Node


func before_each() -> void:
	_v = load(GRIMHOLLOW_SCRIPT).new()
	add_child_autofree(_v)
	await get_tree().process_frame
	await get_tree().process_frame


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE)), int(floor(pos.y / TILE)))


func test_height_data_matches_map_dims() -> void:
	assert_eq(_v._height_grid.size(), _v.MAP_HEIGHT, "height rows == MAP_HEIGHT")
	for row in _v._height_grid:
		assert_eq(row.size(), _v.MAP_WIDTH, "height row width == MAP_WIDTH")


func test_spiral_has_at_least_three_distinct_tiers() -> void:
	var tiers := {}
	for row in _v._height_grid:
		for h in row:
			tiers[h] = true
	assert_gte(tiers.size(), 3, "sunken hollow spiral needs at least 3 distinct tiers (rim/mid/floor)")


func test_every_ramp_bridges_a_one_tier_step() -> void:
	assert_gt(_v._stair_cells.size(), 0, "CONTROL: the spiral has ramp cells")
	for cell in _v._stair_cells:
		var here: int = HG.height_at(_v._height_grid, cell)
		var bridges := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + d
			var hn := HG.height_at(_v._height_grid, n)
			if hn >= 0 and absi(hn - here) == 1:
				bridges = true
		assert_true(bridges, "ramp %s bridges a legal one-tier step" % cell)


## The rim spawn must walk the spiral down to the floor save point, crossing ramps at
## 2+ distinct heights on the way — the structural signature of a spiral, not a single step.
func test_rim_spawn_reaches_the_floor_save_point_through_the_spiral() -> void:
	var start := _cell(_v.spawn_points["default"])
	var seen := {start: true}
	var parent := {}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and _v._can_step(c, n):
				seen[n] = true
				parent[n] = c
				queue.append(n)

	var save_cell := _cell(_v._get_save_point_position())
	assert_true(seen.has(save_cell), "floor save point reachable from the rim spawn")
	if not seen.has(save_cell):
		return

	var path: Array[Vector2i] = []
	var cur: Vector2i = save_cell
	while cur != start:
		path.append(cur)
		cur = parent[cur]
	path.append(start)

	var ramp_heights := {}
	for c in path:
		if _v._stair_cells.has(c):
			ramp_heights[HG.height_at(_v._height_grid, c)] = true
	assert_gte(ramp_heights.size(), 2, "the walk down crosses ramp cells at 2+ distinct heights (the spiral's switchback turns)")
