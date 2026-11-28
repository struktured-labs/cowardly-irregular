extends GutTest

## The Records page scaled its fonts (a source-shape guard checked that) but laid every row out from
## literals: a 19px name line, a quip pinned 22px above a ~47px row, a 220px value box. Large Text
## Size grew the text inside those boxes, so lines overlapped and ran past the row.
## Arms: the font GREW; the grown text FITS (ink extents, not boxes) at every preset; every row can
## be scrolled into view; and 100% keeps the shipped layout exactly.

const RECORDS := "res://src/ui/RecordsMenu.gd"

var _saved_scale = null
var _saved_history: Array = []


func _presets() -> Array:
	var consts: Dictionary = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map()
	var p: Array = consts.get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve with >1 step: " + str(p))
	return p


func before_each() -> void:
	_saved_scale = GameState.text_size_scale if "text_size_scale" in GameState else null
	_saved_history = AutogrindSystem.session_history.duplicate(true)
	## The longest value and quip the page can write: a graded session with a long stop reason.
	AutogrindSystem.session_history = [{"battles": 999, "exp_per_min": 99999.0, "duration_sec": 35999.0,
		"reason": "HP threshold reached (30%) — Scriptweaver at 12%", "total_exp": 59997000}]


func after_each() -> void:
	if _saved_scale != null:
		GameState.text_size_scale = _saved_scale
	AutogrindSystem.session_history = _saved_history


func _built_at(scale: float) -> Node:
	GameState.text_size_scale = scale
	var m: Node = load(RECORDS).new()
	add_child_autofree(m)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


## Drawn extent of a no-wrap Label: its minimum is its text, and alignment decides which end it sits.
func _ink(l: Label) -> Rect2:
	var m: Vector2 = l.get_minimum_size()
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return Rect2(l.position, Vector2(l.size.x, maxf(l.size.y, m.y)))
	var x: float = l.position.x
	if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x = l.position.x + l.size.x - m.x
	return Rect2(Vector2(x, l.position.y), m)


func test_the_fonts_follow_the_setting() -> void:
	var small: Node = await _built_at(0.8)
	var s: int = ((small._rows[0] as Control).get_child(1) as Label).get_theme_font_size("font_size")
	var big: Node = await _built_at(2.0)
	var b: int = ((big._rows[0] as Control).get_child(1) as Label).get_theme_font_size("font_size")
	assert_gt(b, s, "the record name must GROW with Text Size: 80%% %d, 200%% %d" % [s, b])


func test_every_line_fits_its_row_at_every_preset() -> void:
	var bad: Array = []
	var judged := 0
	var outgrew := 0
	for scale in _presets():
		var m: Node = await _built_at(float(scale))
		var w: float = (m._list as Control).size.x
		for row in m._rows:
			var r: Control = row as Control
			var bg_bottom: float = (r.get_child(0) as Control).size.y
			var name_l: Label = r.get_child(1) as Label
			var parts: Array = [_ink(name_l), _ink(r.get_child(2) as Label), _ink(r.get_child(3) as Label)]
			if name_l.get_minimum_size().y > 19.0:
				outgrew += 1
			var tag: String = "%.2fx %s" % [scale, name_l.text]
			for i in parts.size():
				var a: Rect2 = parts[i]
				judged += 1
				if a.position.x < 0.0 or a.end.x > w + 0.5 or a.end.y > bg_bottom + 0.5:
					bad.append("%s part %d %s leaves the row (w %.0f, bottom %.0f)" % [tag, i, a, w, bg_bottom])
				for j in range(i + 1, parts.size()):
					if a.intersects(parts[j] as Rect2):
						bad.append("%s parts %d and %d overlap: %s ∩ %s" % [tag, i, j, a, parts[j]])
		var title: Label = m.get_child(1) as Label
		if title.position.y + title.get_minimum_size().y > (m._list as Control).position.y + 0.5:
			bad.append("%.2fx title ends %.0f below the list top %.0f" % [scale,
				title.position.y + title.get_minimum_size().y, (m._list as Control).position.y])
		var hint: Label = m._hint as Label
		if (m._list as Control).get_rect().end.y > hint.position.y + 0.5:
			bad.append("%.2fx the list runs into the hint" % scale)
	assert_gt(judged, 100, "CONTROL: the arm must judge every line of every row at every preset")
	assert_gt(outgrew, 0, "CONTROL: some name line must outgrow the authored 19px, or this arm has no teeth")
	assert_eq(bad, [], "every record line must fit its row: %s" % [bad])


func test_every_row_can_be_scrolled_into_view() -> void:
	var m: Node = await _built_at(2.0)
	var list: Control = m._list as Control
	assert_gt(float(m._scroll_max), 0.0, "CONTROL: at 200% the page must outgrow the screen")
	var last: Control = m._rows[m._rows.size() - 1] as Control
	var ev := InputEventAction.new()
	ev.action = "ui_down"
	ev.pressed = true
	for i in m._rows.size():
		m._input(ev)
	var shown_bottom: float = last.position.y + last.size.y + (m._inner as Control).position.y
	assert_lte(shown_bottom, list.size.y + 0.5,
		"pressing down must bring the last record fully into the list: bottom %.0f, list %.0f"
			% [shown_bottom, list.size.y])
	assert_true((m._hint as Label).text.contains("Scroll"), "the hint must say the page scrolls")


func test_the_default_text_size_keeps_the_shipped_layout() -> void:
	var m: Node = await _built_at(1.0)
	var vp: Vector2 = m.get_viewport_rect().size
	var authored: float = clampf(maxf(100.0, (vp.y - 40.0) - 72.0) / float(m._rows.size()), 40.0, 56.0)
	assert_eq((m._list as Control).position.y, 72.0, "the list starts at the authored 72")
	assert_almost_eq(float(m._pitch), authored, 0.01, "the pitch is the authored one")
	assert_eq(float(m._scroll_max), 0.0, "nothing scrolls at 100%")
	assert_false((m._hint as Label).text.contains("Scroll"), "and the hint is unchanged")
	var w: float = (m._list as Control).size.x
	for row in m._rows:
		var r: Control = row as Control
		assert_almost_eq((r.get_child(3) as Label).position.y, authored - 22.0, 0.01, "quip at the authored y")
		assert_eq((r.get_child(2) as Label).position, Vector2(w - 236.0, 4.0), "value at the authored spot")
