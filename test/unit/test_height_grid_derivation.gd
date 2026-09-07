extends GutTest

## HeightGrid is the pure math under village elevation: faces hang SOUTH of a step onto
## the lower cell, every other illegal step is an edge bit on the higher cell, and stairs
## are the only one-tier connectors. Scene-free so it can be exhaustive.

const HG := preload("res://src/exploration/HeightGrid.gd")


func _grid(rows: Array) -> Array:
	return HG.parse(rows)


func test_parse_and_height_at() -> void:
	var g := _grid(["012", "333"])
	assert_eq(HG.height_at(g, Vector2i(2, 0)), 2)
	assert_eq(HG.height_at(g, Vector2i(0, 1)), 3)
	assert_eq(HG.height_at(g, Vector2i(5, 0)), -1, "off-grid x reads -1")
	assert_eq(HG.height_at(g, Vector2i(0, 9)), -1, "off-grid y reads -1")
	assert_eq(HG.parse([]).size(), 0, "empty height data parses to an empty grid")


func test_stair_cells_reads_both_chars() -> void:
	var s := HG.stair_cells(["g^g", "g/g"])
	assert_eq(s.size(), 2)
	assert_eq(s[Vector2i(1, 0)], "^")
	assert_eq(s[Vector2i(1, 1)], "/")


func test_can_step_same_height_true_and_cliff_false() -> void:
	var g := _grid(["22", "11"])
	assert_true(HG.can_step(g, {}, Vector2i(0, 0), Vector2i(1, 0)), "same height is walkable")
	assert_false(HG.can_step(g, {}, Vector2i(0, 0), Vector2i(0, 1)), "a one-tier drop with no stair is a wall")
	assert_false(HG.can_step(g, {}, Vector2i(0, 1), Vector2i(0, 0)), "and so is the climb")
	assert_false(HG.can_step(g, {}, Vector2i(0, 0), Vector2i(0, -1)), "off-grid is never steppable")


func test_stair_bridges_exactly_one_tier() -> void:
	var g := _grid(["2", "1", "0"])
	var stairs := {Vector2i(0, 1): "^"}
	assert_true(HG.can_step(g, stairs, Vector2i(0, 0), Vector2i(0, 1)), "2 -> stair@1 legal")
	assert_true(HG.can_step(g, stairs, Vector2i(0, 1), Vector2i(0, 2)), "stair@1 -> 0 same height legal")
	var two := _grid(["3", "1"])
	assert_false(HG.can_step(two, {Vector2i(0, 1): "^"}, Vector2i(0, 0), Vector2i(0, 1)), "a stair never bridges two tiers")


func test_south_step_paints_face_on_lower_cell() -> void:
	var g := _grid(["222", "111"])
	var out := HG.derive(g, {})
	assert_eq(out["faces"].size(), 3, "every lower cell under the ledge gets a face")
	assert_true(out["faces"].has(Vector2i(1, 1)))
	assert_eq(out["edges"].size(), 0, "a pure south step needs no edge strips")


func test_stair_cell_gets_no_face_and_wall_cell_gets_no_face() -> void:
	var g := _grid(["222", "111"])
	var out := HG.derive(g, {Vector2i(1, 1): "^"}, {Vector2i(2, 1): true})
	assert_false(out["faces"].has(Vector2i(1, 1)), "stair is the connector, never a face")
	assert_false(out["faces"].has(Vector2i(2, 1)), "a wall already blocks; no face overdraw")
	assert_true(out["faces"].has(Vector2i(0, 1)))


func test_west_east_north_steps_become_edge_bits_on_the_higher_cell() -> void:
	# A raised 1x1 plaza in a field: its W/E/N sides are lips, its S side is a face.
	var g := _grid(["000", "010", "000"])
	var out := HG.derive(g, {})
	var c := Vector2i(1, 1)
	assert_eq(int(out["edges"].get(c, 0)), HG.EDGE_N | HG.EDGE_E | HG.EDGE_W, "three lips on the high cell")
	assert_true(out["faces"].has(Vector2i(1, 2)), "south face on the lower cell")
	assert_false(out["edges"].has(Vector2i(0, 1)), "lower cells carry no bits — the high cell owns the edge")


func test_flat_grid_derives_nothing() -> void:
	var out := HG.derive(_grid(["000", "000"]), {})
	assert_eq(out["faces"].size(), 0)
	assert_eq(out["edges"].size(), 0)
