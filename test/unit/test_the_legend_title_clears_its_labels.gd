extends GutTest

## The pad legend (ControllerOverlay, shown during autogrind) drew its "CONTROLS" title at a fixed (10, 16), and the
## L shoulder's label "Tier (L+R)" at (45, 24): two 11 px strings printed through each other in BOTH contexts.
## The title is now centred, and every string's rect comes from the one measure _draw uses (drawn_text_rects).
## Corpus: every static *_context() the script declares, so a new context is judged without being listed here.

const CO := preload("res://src/ui/ControllerOverlay.gd")
const SLACK := 0.5


func _contexts() -> Dictionary:
	var out := {}
	for m in (CO as GDScript).get_script_method_list():
		var n: String = str(m.get("name", ""))
		if n.ends_with("_context") and int(m.get("flags", 0)) & METHOD_FLAG_STATIC:
			out[n] = CO.call(n)
	return out


func test_the_floor_names_every_member_this_file_drives() -> void:
	var names: Array = (CO as GDScript).get_script_method_list().map(func(m): return str(m["name"]))
	for f in ["drawn_text_rects", "title_pos", "label_pos", "autogrind_context", "autogrind_ludicrous_context"]:
		assert_has(names, f, "ControllerOverlay.%s must exist" % f)
	var consts: Dictionary = (CO as GDScript).get_script_constant_map()
	for c in ["OVERLAY_SIZE", "TEXT_PX", "TITLE"]:
		assert_true(consts.has(c), "ControllerOverlay.%s must exist" % c)
	assert_not_null(ThemeDB.fallback_font, "PRECONDITION: the font the legend draws with")
	assert_gte(_contexts().size(), 2, "CONTROL: the derived corpus holds the legend's contexts (%s)" % [_contexts().keys()])


## CONTROL: the shipped title position DID collide, so the disjointness arm below can fail.
func test_the_old_title_printed_through_the_shoulder_label() -> void:
	var f: Font = ThemeDB.fallback_font
	var old := Rect2(10, 16 - f.get_ascent(CO.TEXT_PX), f.get_string_size(CO.TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, CO.TEXT_PX).x, f.get_height(CO.TEXT_PX))
	var l_label: Rect2 = CO.drawn_text_rects(CO.autogrind_context())["l"]
	assert_true(old.grow(-SLACK).intersects(l_label.grow(-SLACK)), "CONTROL: at (10, 16) the title overlapped '%s' (%s vs %s)" % [CO.autogrind_context()["l"], old, l_label])


func test_no_two_strings_overlap_and_all_stay_in_the_legend() -> void:
	var box := Rect2(Vector2.ZERO, CO.OVERLAY_SIZE).grow(SLACK)
	var bad: Array = []
	var seen := 0
	for cname in _contexts():
		var rects: Dictionary = CO.drawn_text_rects(_contexts()[cname])
		var ids: Array = rects.keys()
		seen += ids.size()
		for i in ids.size():
			var a: Rect2 = rects[ids[i]]
			if not box.encloses(a):
				bad.append("%s: '%s' leaves the legend (%s)" % [cname, ids[i], a])
			for j in range(i + 1, ids.size()):
				if a.grow(-SLACK).intersects((rects[ids[j]] as Rect2).grow(-SLACK)):
					bad.append("%s: '%s' and '%s' print through each other" % [cname, ids[i], ids[j]])
	assert_gt(seen, 8, "CONTROL: the sweep measured real strings (%d)" % seen)
	assert_eq(bad, [], "every string the legend draws has its own room: %s" % [bad])


## The title is the one centred string: it sits in the middle of the legend, so a shoulder label on either side is clear of it.
func test_the_title_is_centred() -> void:
	var t: Rect2 = CO.drawn_text_rects({})["title"]
	assert_gt(t.size.x, 10.0, "CONTROL: the title has width")
	assert_almost_eq(t.get_center().x, CO.OVERLAY_SIZE.x / 2.0, 1.0, "the title is centred over the pad")
