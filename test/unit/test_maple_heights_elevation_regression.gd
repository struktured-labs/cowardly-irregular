extends GutTest

## Maple Heights' split-level suburbia (struktured 2026-09-06): a modest raised residential
## shelf (house #1 + yard) with retaining-wall cliffs. Pins the tier count, step legality, and
## that the save point stays reachable from the entrance under the real _can_step rule.

const MAPLE_SCRIPT := "res://src/maps/villages/MapleHeightsVillage.gd"
const HG := preload("res://src/exploration/HeightGrid.gd")
const TILE := 32.0

var _v: Node


func before_each() -> void:
	_v = load(MAPLE_SCRIPT).new()
	add_child_autofree(_v)
	await get_tree().process_frame
	await get_tree().process_frame


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE)), int(floor(pos.y / TILE)))


func _flood(start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and _v._can_step(c, n):
				seen[n] = true
				queue.append(n)
	return seen


## True if the cell itself or one of its 4 neighbors is in the reachable set — matches how
## SavePoint's proximity-based interaction actually works (InteractGeometry.SAVE_RADIUS).
func _near_reachable(cell: Vector2i, reachable: Dictionary) -> bool:
	for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if reachable.has(cell + d):
			return true
	return false


func test_height_data_matches_map_dims() -> void:
	assert_eq(_v._height_grid.size(), _v.MAP_HEIGHT, "height rows == MAP_HEIGHT")
	for row in _v._height_grid:
		assert_eq(row.size(), _v.MAP_WIDTH, "height row width == MAP_WIDTH")


func test_raised_shelf_has_at_least_two_tiers() -> void:
	var tiers := {}
	for row in _v._height_grid:
		for h in row:
			tiers[h] = true
	assert_gte(tiers.size(), 2, "the raised shelf and the street level are distinct tiers")


func test_every_step_bridges_a_one_tier_step() -> void:
	assert_gt(_v._stair_cells.size(), 0, "CONTROL: the shelf has step cells")
	for cell in _v._stair_cells:
		var here: int = HG.height_at(_v._height_grid, cell)
		var bridges := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + d
			var hn := HG.height_at(_v._height_grid, n)
			if hn >= 0 and absi(hn - here) == 1:
				bridges = true
		assert_true(bridges, "step %s bridges a legal one-tier step" % cell)


func test_save_point_reachable_from_entrance() -> void:
	var reachable := _flood(_cell(_v.spawn_points["default"]))
	assert_gt(reachable.size(), 200, "CONTROL: the flood reached a meaningful chunk of the map")
	var save_cell := _cell(_v._get_save_point_position())
	assert_true(_near_reachable(save_cell, reachable), "save point near a cell reachable from the entrance")
