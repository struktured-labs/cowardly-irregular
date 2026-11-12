extends GutTest

## The ONE overlap judge (test/unit/helpers/overlap_audit.gd) judged a bare Label by its box and a widget's own plate
## against its own label: cowir-overworld's field census read 57 pairs at 1.0, most of them those two (2026-11-12).
## A text surface is judged by its ink, and surfaces under one declared widget do not collide with each other.

const Audit := preload("res://test/unit/helpers/overlap_audit.gd")

var _root: Control


func before_each() -> void:
	_root = Control.new()
	_root.size = Vector2(1280, 720)
	add_child_autofree(_root)


func _label(text: String, pos: Vector2, size: Vector2, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	_root.add_child(l)
	return l


func _panel(pos: Vector2, size: Vector2, parent: Node = null) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	(parent if parent != null else _root).add_child(p)
	return p


func test_a_centred_label_is_judged_by_its_words_not_its_band() -> void:
	var banner := _label("Harmonia", Vector2(0, 100), Vector2(1280, 48), HORIZONTAL_ALIGNMENT_CENTER)
	var corner := _panel(Vector2(20, 100), Vector2(120, 48))
	await get_tree().process_frame
	var box: Rect2 = Audit.screen_rect(banner)
	var ink: Rect2 = Audit.ink_rect(banner)
	assert_almost_eq(box.size.x, 1280.0, 0.5, "CONTROL: the banner's BOX spans the screen")
	assert_lt(ink.size.x, 400.0, "its ink is the width of the word (%.0f px)" % ink.size.x)
	assert_almost_eq(ink.get_center().x, 640.0, 2.0, "and sits where a centred label draws it")
	var hits: Array = Audit.collisions(Audit.surfaces(_root), {})
	assert_eq(hits, [], "a panel in the band's corner, 400 px from the word, is not an overlap")
	corner.position = Vector2(600, 100)
	await get_tree().process_frame
	assert_eq(Audit.collisions(Audit.surfaces(_root), {}).size(), 1, "CONTROL: a panel ON the word still is")


func test_right_and_left_alignment_put_the_ink_at_that_edge() -> void:
	var left := _label("Gold", Vector2(100, 200), Vector2(600, 30), HORIZONTAL_ALIGNMENT_LEFT)
	var right := _label("Gold", Vector2(100, 300), Vector2(600, 30), HORIZONTAL_ALIGNMENT_RIGHT)
	await get_tree().process_frame
	assert_almost_eq(Audit.ink_rect(left).position.x, 100.0, 1.0, "left-aligned ink starts at the box's left")
	assert_almost_eq(Audit.ink_rect(right).end.x, 700.0, 1.0, "right-aligned ink ends at the box's right")
	assert_almost_eq(Audit.ink_rect(left).size.x, Audit.ink_rect(right).size.x, 0.5, "CONTROL: the same word, the same width")


func test_a_background_keeps_its_box() -> void:
	var p := _panel(Vector2(50, 50), Vector2(300, 200))
	await get_tree().process_frame
	var found: Array = Audit.surfaces(_root)
	assert_eq(found.size(), 1, "CONTROL: the panel is the one surface")
	assert_eq((found[0]["rect"] as Rect2).size, Vector2(300, 200), "a panel is what it paints: its whole box")
	assert_eq(str(found[0]["widget"]), "", "and with no widgets declared it belongs to none")
	assert_not_null(p)


func test_one_widgets_own_parts_do_not_collide_but_two_widgets_do() -> void:
	var tracker := Control.new()
	tracker.name = "QuestTracker"
	_root.add_child(tracker)
	var plate := _panel(Vector2(900, 40), Vector2(300, 80), tracker)
	plate.name = "Plate"
	var line := Label.new()
	line.name = "Line"
	line.text = "Find the chicken"
	line.position = Vector2(910, 50)
	line.size = Vector2(280, 24)
	tracker.add_child(line)  # a SIBLING of the plate, so "a surface's descendants are its content" does not cover it
	var minimap := _panel(Vector2(1100, 60), Vector2(160, 160))
	minimap.name = "Minimap"
	await get_tree().process_frame
	var bare: Array = Audit.collisions(Audit.surfaces(_root), {})
	assert_eq(bare.size(), 3, "CONTROL: with no widgets declared, plate x line, plate x minimap and line x minimap all read as overlaps: %s" % str(bare))
	var grouped: Array = Audit.collisions(Audit.surfaces(_root, [tracker]), {})
	assert_eq(grouped.size(), 2, "the tracker's plate and its own line are one thing: %s" % str(grouped))
	for hit in grouped:
		assert_true("Minimap" in str(hit), "what remains is the tracker ON the minimap, a real overlap: %s" % hit)
	var both: Array = Audit.collisions(Audit.surfaces(_root, [tracker, minimap]), {})
	assert_eq(both.size(), 2, "two different widgets still collide with each other")
