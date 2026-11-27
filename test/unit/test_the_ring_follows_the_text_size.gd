extends GutTest

## The ring picker (autobattle ability/item rings, the autogrind OPTIONS ring) drew every string at a fixed 10 / 13 / 15 px,
## and its selected label sat in the middle on one line: measured (9d493ba09) at 278 px on the autogrind ring against the 212 px
## gap between the 3 and 9 o'clock nodes, so at 100% a long name ran into the side nodes. Every string now follows Text Size;
## the middle lines keep their authored baselines while they fit, else stack and wrap inside a circle that clears every node
## (the selection may end in "…" beside its whole outer label), and the title moves above the ring when the middle cannot hold it.
## Every rect judged here comes from label_rect / centre_layout, the functions _draw itself draws from, in ring_font().

const RP := "res://src/ui/RadialPicker.gd"
const VP := Vector2(1280, 720)

var _saved = null


func before_each() -> void:
	_saved = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _saved


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, or every preset loop passes empty: " + str(p))
	return p


func _opts(labels: Array) -> Array:
	var out: Array = []
	for i in labels.size():
		out.append({"id": "o%02d" % i, "label": labels[i]})
	return out


## The autogrind OPTIONS ring's rows as _options_ring_spec writes them, each state at its longest (27 rows: three pages).
func _autogrind() -> Dictionary:
	return {"title": "Autogrind Options", "kind": "autogrind_options", "options": _opts([
		"Ludicrous: OFF        (H)", "Permadeath: OFF       (P)", "Auto-Advance: OFF     (W)",
		"Stop at HP: 25%", "Stop after: 100 battles", "Stop on Death: OFF", "Stop when Out of Items: OFF",
		"Toggle This Rule        (Tab)", "Explain These Rules", "Cycle Member: Everyone", "Cycle Ability: Fireball",
		"Cycle Status: poison", "Preset: Casual          (1)", "Preset: Standard        (2)", "Preset: Hardcore        (3)",
		"Save as Preset          (S)", "Delete Last Preset      (D)", "Resume Saved Grind      (R)",
		"Custom Slot 1           (4)", "Custom Slot 2           (5)", "Custom Slot 3           (6)",
		"Export to File          (E)", "Import from File        (I)", "Copy Share Code   (Shift+E)",
		"Paste Share Code  (Shift+I)", "Switch Profile: " + "W".repeat(_profile_name_max()), "Restore Shipped Profiles"])}


## The Switch Profile row (.838) at its longest: a name at AutogrindSystem.PROFILE_NAME_MAX, in W, the widest glyph.
func _profile_name_max() -> int:
	var cap: int = int(AutogrindSystem.get_script().get_script_constant_map().get("PROFILE_NAME_MAX", 0))
	assert_gt(cap, 0, "FLOOR: AutogrindSystem.PROFILE_NAME_MAX must resolve, or the longest profile row is empty")
	return cap


func _longest(names: Array) -> Array:
	names.sort_custom(func(a, b): return str(a).length() > str(b).length())
	return names.slice(0, 10)


## The ability and item rings' worst pages: the ten longest names the game has.
func _ability() -> Dictionary:
	var n: Array = []
	for id in JobSystem.abilities.keys():
		n.append(str(JobSystem.abilities[id].get("name", id)))
	return {"title": "Ability", "kind": "ability_id", "options": _opts(_longest(n))}


func _item() -> Dictionary:
	var n: Array = []
	for id in ItemSystem.items.keys():
		if int(ItemSystem.items[id].get("category", 0)) in [0, 1, 2, 3]:
			n.append(str(ItemSystem.items[id].get("name", id)))
	return {"title": "Item", "kind": "item_id", "options": _opts(_longest(n))}


func _ring(scale: float, spec: Dictionary, selected: int) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(VP)
	add_child_autofree(vp)
	var s := spec.duplicate(true)
	s["selected"] = selected
	var r: Control = load(RP).new()
	r.setup(s)
	vp.add_child(r)
	r.size = VP
	_ring_font = r.call("ring_font")
	return r


var _ring_font: Font = null
var _closest := INF
var _edge := INF
var _edge_at := ""


func _font() -> Font:
	return _ring_font


func _squash(t: String) -> String:
	return " ".join(t.split(" ", false))


## Every way a ring at this size breaks: outer labels at the wrong px, overlapping or off screen; middle lines at the wrong px,
## overlapping each other, outside the centre circle, or not saying the selected label (a cut one must end in "…").
func _judge(tag: String, r: Control, truncs: Array) -> Array:
	var bad: Array = []
	var page: Array = r.call("_page_slice")
	var n := page.size()
	var rects: Array = []
	for i in n:
		var lr: Rect2 = r.call("label_rect", i, n, str(page[i]["label"]))
		rects.append(lr)
		if absf(lr.size.y - _font().get_height(TextScale.scaled(10))) > 0.5:
			bad.append("%s slot %d drawn %.0f tall, the Text Size asks %.0f" % [tag, i, lr.size.y, _font().get_height(TextScale.scaled(10))])
		var m := minf(minf(lr.position.x, VP.x - lr.end.x), minf(lr.position.y, VP.y - lr.end.y))
		if m < _edge:
			_edge = m
			_edge_at = "%s slot %d '%s'" % [tag, i, str(page[i]["label"]).left(24)]
		if not Rect2(Vector2.ZERO, VP).encloses(lr):
			bad.append("%s slot %d '%s' at %s runs off the screen" % [tag, i, str(page[i]["label"]).left(20), lr])
	for i in n:
		for j in range(i + 1, n):
			if (rects[i] as Rect2).intersects(rects[j]):
				bad.append("%s slots %d and %d overlap" % [tag, i, j])
			var a: Rect2 = rects[i]
			var b2: Rect2 = rects[j]
			_closest = minf(_closest, maxf(maxf(a.position.x - b2.end.x, b2.position.x - a.end.x), maxf(a.position.y - b2.end.y, b2.position.y - a.end.y)))
	var c := VP * 0.5
	var cr: float = r.call("centre_radius")
	var lines: Array = r.call("centre_layout")
	var prev := -INF
	var sel_text := ""
	var title_text := ""
	var page_text := ""
	for l in lines:
		var rr: Rect2 = l["rect"]
		if l["where"] == "above":
			title_text += ("" if title_text == "" else " ") + str(l["text"])
			if not Rect2(Vector2.ZERO, VP).encloses(rr):
				bad.append("%s the title line '%s' above the ring runs off the screen" % [tag, l["text"]])
			for o in rects:
				if (o as Rect2).intersects(rr):
					bad.append("%s the title line '%s' above the ring overlaps a ring label" % [tag, l["text"]])
			continue
		if rr.position.y < prev - 0.5:
			bad.append("%s middle line '%s' starts at %.0f inside the line above (ends %.0f)" % [tag, str(l["text"]).left(20), rr.position.y, prev])
		prev = rr.end.y
		for corner in [rr.position, Vector2(rr.end.x, rr.position.y), Vector2(rr.position.x, rr.end.y), rr.end]:
			if (corner - c).length() > cr + 0.5:
				bad.append("%s middle line '%s' reaches %.0f px from the centre, past the %.0f px that clears the nodes" % [tag, str(l["text"]).left(20), (corner - c).length(), cr])
				break
		if int(l["px"]) == TextScale.scaled(15):
			sel_text += ("" if sel_text == "" else " ") + str(l["text"])
		elif int(l["px"]) == TextScale.scaled(13):
			title_text += ("" if title_text == "" else " ") + str(l["text"])
		elif int(l["px"]) == TextScale.scaled(10):
			page_text += ("" if page_text == "" else " ") + str(l["text"])
		else:
			bad.append("%s middle line '%s' drawn at %d px" % [tag, l["text"], l["px"]])
	## The title and page line have no other copy on screen, so they are never cut (main 28184).
	if _squash(title_text) != _squash(str(r.get("spec").get("title", ""))):
		bad.append("%s the title reads '%s'" % [tag, title_text])
	if int(r.call("_page_count")) > 1 and not _squash(page_text).begins_with("%d / %d" % [int(r.get("_page")) + 1, int(r.call("_page_count"))]):
		bad.append("%s the page line reads '%s'" % [tag, page_text])
	if page_text.contains("…"):
		bad.append("%s the page line is cut: '%s'" % [tag, page_text])
	var want := _squash(str(r.call("_label_of", r.get("_options")[int(r.get("_selected"))])))
	sel_text = _squash(sel_text)
	if sel_text != want:
		if sel_text.ends_with("…") and want.begins_with(sel_text.trim_suffix("…").strip_edges().split(" ")[0]):
			truncs.append("%s '%s' -> '%s'" % [tag, want, sel_text])
			## A cut middle is allowed only beside a whole copy (adhoc 28183): the selected slot's outer label is the full string.
			var si: int = int(r.get("_selected")) - int(r.get("_page")) * 10
			var full_w := _font().get_string_size(str(r.call("_label_of", r.get("_options")[int(r.get("_selected"))])), HORIZONTAL_ALIGNMENT_LEFT, -1, TextScale.scaled(10)).x
			if absf((rects[si] as Rect2).size.x - full_w) > 0.5:
				bad.append("%s the middle cuts '%s' and its outer label is not the whole string either" % [tag, want])
		else:
			bad.append("%s the middle says '%s', the selection is '%s'" % [tag, sel_text, want])
	return bad


## CONTROL: at 100% a selectable label on one line is wider than the circle the middle text must stay inside.
func test_control_a_long_label_cannot_sit_in_the_middle_on_one_line() -> void:
	var r := _ring(1.0, _autogrind(), 6)
	assert_not_null(_font(), "PRECONDITION: the ring names its font")
	var w := _font().get_string_size("Stop when Out of Items: OFF", HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	assert_gt(w, 2.0 * float(r.call("centre_radius")), "CONTROL: the longest label is %.0f px at 15 px, wider than the middle" % w)


## CONTROL: the overlap check reds on a known pair (one slot's real label rect twice), so "no pair overlaps" can fail.
func test_control_the_overlap_check_sees_a_known_overlap() -> void:
	var r := _ring(2.0, _autogrind(), 0)
	var a: Rect2 = r.call("label_rect", 1, 10, "Stop when Out of Items: OFF")
	var b: Rect2 = r.call("label_rect", 1, 10, "Stop when Out of Items: OFF")
	assert_true(a.intersects(b), "CONTROL: the same slot's rect overlaps itself")


func test_every_ring_page_fits_at_every_size() -> void:
	var bad: Array = []
	var truncs: Array = []
	var seen := 0
	for scale in _presets():
		for spec in [_autogrind(), _ability(), _item()]:
			var total: int = (spec["options"] as Array).size()
			for start in range(0, total, 10):
				## The longest label on this page is the selected one, the middle's worst case.
				var best := start
				for k in range(start, mini(total, start + 10)):
					if str(spec["options"][k]["label"]).length() > str(spec["options"][best]["label"]).length():
						best = k
				var r := _ring(float(scale), spec, best)
				seen += 1
				bad.append_array(_judge("%.2fx %s p%d" % [float(scale), spec["title"], start / 10 + 1], r, truncs))
	assert_gt(seen, 10, "PRECONDITION: every ring page at every preset was judged")
	gut.p("RING truncations (%d): %s" % [truncs.size(), truncs])
	gut.p("RING smallest screen margin of any outer label: %.1f px (%s)" % [_edge, _edge_at])
	gut.p("RING closest outer pair: %.1f px apart · ring font is the engine fallback: %s" % [_closest, str(_font() == ThemeDB.fallback_font)])
	assert_eq(bad, [], "the ring fits at every Text Size: %s" % [bad])


## 100%: the outer labels are where the shipped ring drew them, and a label that fits keeps its authored middle baselines.
func test_a_short_ring_at_100_percent_is_unchanged() -> void:
	var r := _ring(1.0, _item(), 0)
	var c := VP * 0.5
	var f := _font()
	var page: Array = r.call("_page_slice")
	for i in page.size():
		var a := -PI / 2.0 + TAU * float(i) / float(page.size())
		var out := Vector2(cos(a), sin(a))
		var lp := c + out * 132.0 + out * (26.0 + 12.0)
		var w := f.get_string_size(str(page[i]["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		if out.x < -0.2:
			lp.x -= w
		elif absf(out.x) <= 0.2:
			lp.x -= w * 0.5
		var lr: Rect2 = r.call("label_rect", i, page.size(), str(page[i]["label"]))
		assert_almost_eq(lr.position, Vector2(lp.x, lp.y + 4.0 - f.get_ascent(10)), Vector2(0.5, 0.5), "slot %d sits where it always did" % i)
	var lines: Array = r.call("centre_layout")
	assert_eq(lines.size(), 2, "PRECONDITION: one title line and one selected line")
	assert_almost_eq(float(lines[0]["rect"].position.y), c.y - 18.0 - f.get_ascent(13), 0.5, "the title keeps its authored baseline")
	assert_almost_eq(float(lines[1]["rect"].position.y), c.y + 4.0 - f.get_ascent(15), 0.5, "the selected label keeps its authored baseline")
	assert_eq([int(lines[0]["px"]), int(lines[1]["px"])], [13, 15], "and their authored px")
