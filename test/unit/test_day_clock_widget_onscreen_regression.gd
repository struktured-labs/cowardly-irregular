extends GutTest

## struktured 2026-08-22, playtest: "the night indicator on upper right is clipped in the village".
## It was clipped EVERYWHERE, and the village is only where he caught it. _ready set
## PRESET_CENTER_TOP (anchor at x=0.5) and then ALSO set position.x = viewport_width/2 - 36, so the
## centring was applied twice: the 72px dial's left edge landed at viewport_width - 36 and half of
## it hung past the right edge. It also captured the viewport size once at _ready, so it could
## never survive a resolution change.
##
## Pinned as a RELATIONSHIP — the dial's rect must lie inside the viewport — not as a coordinate,
## so moving the clock stays green while pushing it off-screen reds.

const CLOCK := preload("res://src/ui/DayClockWidget.gd")


func _dial_of(w) -> Control:
	return w.get_node_or_null("DayClockDial")


func test_the_dial_sits_fully_inside_the_viewport() -> void:
	var w = CLOCK.new()
	add_child_autofree(w)
	await get_tree().process_frame
	var dial := _dial_of(w)
	assert_not_null(dial, "CONTROL: the dial exists — a null here would pass every check below vacuously")
	var vp := get_viewport().get_visible_rect().size
	assert_gt(vp.x, 0.0, "CONTROL: a real viewport width")
	var r := Rect2(dial.global_position, dial.size)
	assert_gte(r.position.x, 0.0, "dial runs off the LEFT edge (x=%.1f)" % r.position.x)
	assert_lte(r.position.x + r.size.x, vp.x,
		"dial runs off the RIGHT edge: ends at %.1f, viewport is %.1f wide" % [r.position.x + r.size.x, vp.x])
	assert_gte(r.position.y, 0.0, "dial runs off the TOP")
	assert_lte(r.position.y + r.size.y, vp.y, "dial runs off the BOTTOM")


func test_it_is_horizontally_centred_not_pushed_to_an_edge() -> void:
	# The whole defect was a rightward drift, so pin the thing that drifted: the dial's centre
	# should sit near the viewport's centre, whatever the resolution.
	var w = CLOCK.new()
	add_child_autofree(w)
	await get_tree().process_frame
	var dial := _dial_of(w)
	var vp := get_viewport().get_visible_rect().size
	var dial_centre := dial.global_position.x + dial.size.x / 2.0
	assert_almost_eq(dial_centre, vp.x / 2.0, 4.0,
		"dial centre %.1f should track the viewport centre %.1f" % [dial_centre, vp.x / 2.0])


func test_placement_does_not_depend_on_the_viewport_size_read_at_ready() -> void:
	# The old code baked get_viewport().get_visible_rect() into an offset at construction, so a
	# resolution change stranded it. Anchor-relative offsets have no such reference.
	var src := FileAccess.get_file_as_string("res://src/ui/DayClockWidget.gd")
	assert_gt(src.length(), 500, "CONTROL: read a real file")
	var i := src.find("func _ready")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_false(body.contains("get_visible_rect"),
		"_ready must not bake the viewport size into the dial's offset — it cannot survive a resize")
