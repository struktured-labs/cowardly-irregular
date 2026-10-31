extends GutTest

## cowir-main, reading the 2026-10-31 bubble shots: an edge-clamped bubble's tail did not point back
## at its speaker. The tip sat a fixed 16px under the bubble with its x clamped near the edge, so a
## head below and off to one side got a stub aimed at nobody. The tail now aims at the head, x and y.

const BW := 200.0
const BH := 40.0


func _tail(anchor_local: Vector2) -> PackedVector2Array:
	var b := BattleSpeechBubble.new()
	add_child_autofree(b)
	var p := Polygon2D.new()
	b.add_child(p)
	b._build_tail(p, Vector2(BW, BH), anchor_local)
	return p.polygon


func _base(poly: PackedVector2Array) -> Vector2:
	return (poly[0] + poly[1]) * 0.5


func test_a_head_off_the_edge_and_below_gets_a_tail_aimed_at_it() -> void:
	var head := Vector2(-150, BH + 150)
	var poly := _tail(head)
	assert_eq(poly.size(), 3, "CONTROL: the tail is a triangle")
	var aim: Vector2 = (poly[2] - _base(poly)).normalized()
	var want: Vector2 = (head - _base(poly)).normalized()
	assert_gt(aim.dot(want), 0.97,
		"the tip must point at the head (cos %.3f); a tip fixed 16px down aimed ~22 degrees off" % aim.dot(want))


func test_the_tail_never_outgrows_its_cap() -> void:
	var poly := _tail(Vector2(-600, BH + 400))
	assert_lte((poly[2] - _base(poly)).length(), BattleSpeechBubble.TAIL_MAX_PX + 0.01,
		"a far head gets a capped tail, not a line across the field")


func test_a_near_head_is_reached_not_overshot() -> void:
	var head := Vector2(BW * 0.5, BH + 20)
	var poly := _tail(head)
	assert_almost_eq(poly[2].distance_to(head), 0.0, 0.5, "a head within reach is where the tip lands")


func test_the_base_stays_on_the_bottom_edge() -> void:
	var poly := _tail(Vector2(-150, BH + 150))
	assert_almost_eq(poly[0].y, BH - 2.0, 0.01, "base on the bubble's bottom edge")
	assert_almost_eq(poly[1].y, BH - 2.0, 0.01, "both base points")


func test_a_head_level_with_the_bubble_still_gets_a_downward_tail() -> void:
	var poly := _tail(Vector2(BW + 80, BH - 10))
	assert_gt(poly[2].y, _base(poly).y, "a tail must leave the bubble downward, toward where the speaker stands")
