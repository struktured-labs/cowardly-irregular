extends GutTest

## The W4 overworld survey showed "Objective >" printed over the minimap legend's "Cave" row: the edge arrow clamps
## to x <= 1140, y >= 60, which is inside the minimap panel (x 1136..1256) and its legend (down to y ~230). The
## minimap now reports the block it occupies and the arrow steps below it (or left of it near the bottom).

const VP := Vector2(1280, 720)


func _minimap() -> OverworldMinimap:
	var host := Node2D.new()
	add_child_autofree(host)
	var mm := OverworldMinimap.new()
	host.add_child(mm)
	var player := Node2D.new()
	host.add_child(player)
	mm.setup(host, player, 64, 64, 32, {})
	return mm


func test_the_minimap_reserves_its_panel_and_legend() -> void:
	var r: Rect2 = _minimap().reserved_rect()
	assert_gt(r.size.y, 200.0, "the block runs from the panel top through the six legend rows (%s)" % str(r))
	assert_true(r.has_point(Vector2(1150, 180)), "the 'Cave' legend row is inside the reserved block (%s)" % str(r))


func test_the_arrow_that_landed_on_the_legend_steps_below_it() -> void:
	var mm := _minimap()
	var reserved: Array = [mm.reserved_rect()]
	var where := Vector2(1140, 178)
	assert_true(Rect2(where, Vector2(120, 20)).intersects(reserved[0]), "CONTROL: the bug's position overlaps the legend")
	var moved := ObjectiveArrow.clear_of_hud(Rect2(where, Vector2(120, 20)), reserved, VP)
	assert_false(Rect2(moved, Vector2(120, 20)).intersects(reserved[0]), "the arrow no longer overlaps the minimap block (%s)" % str(moved))
	assert_lt(moved.y + 20.0, VP.y + 0.5, "and it is still on screen")


func test_an_arrow_clear_of_the_block_stays_put() -> void:
	var reserved: Array = [_minimap().reserved_rect()]
	var where := Vector2(60, 340)
	assert_eq(ObjectiveArrow.clear_of_hud(Rect2(where, Vector2(120, 20)), reserved, VP), where, "nothing to avoid, nothing moves")


func test_a_block_reaching_the_bottom_sends_the_arrow_left() -> void:
	var tall := Rect2(1136, 16, 128, 700)
	var moved := ObjectiveArrow.clear_of_hud(Rect2(1140, 600, 120, 20), [tall], VP)
	assert_false(Rect2(moved, Vector2(120, 20)).intersects(tall), "with no room below it steps left (%s)" % str(moved))
