extends GutTest

## The Formations page scaled its fonts (a source-shape ratchet checked that) but laid every row out
## from literals: tip at y 32, requirements at 52, an 86px pitch, a 760px one-line note. From 125% the
## note ran ~97px past each side of the panel, and the lines of each row grew into one another.
## Arms: the font GREW; every line FITS (ink, judged against the same row at 100%) at every preset;
## the selected formation scrolls into view; and 100% keeps the shipped layout.

const MENU := "res://src/ui/FormationsMenu.gd"

var _saved_scale = null


func _presets() -> Array:
	var consts: Dictionary = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map()
	var p: Array = consts.get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve with >1 step: " + str(p))
	return p


func before_each() -> void:
	_saved_scale = GameState.text_size_scale if "text_size_scale" in GameState else null


func after_each() -> void:
	if _saved_scale != null:
		GameState.text_size_scale = _saved_scale


func _built_at(scale: float) -> Node:
	GameState.text_size_scale = scale
	var m: Node = load(MENU).new()
	add_child_autofree(m)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


## Drawn extent: a wrapping or clipping Label draws inside its width; a plain one draws its minimum,
## seated by its alignment. Height is always the minimum (a stale out-of-tree size is not ink).
func _ink(l: Label) -> Rect2:
	var m: Vector2 = l.get_minimum_size()
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF or l.clip_text:
		return Rect2(l.position, Vector2(l.size.x, m.y))
	var x: float = l.position.x
	if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x = l.position.x + l.size.x - m.x
	elif l.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		x = l.position.x + (l.size.x - m.x) / 2.0
	return Rect2(Vector2(x, l.position.y), m)


func _parts(r: Control) -> Array:
	var out: Array = []
	for n in ["Name", "Cost", "Tip", "Req"]:
		out.append([n, _ink(r.get_node(n) as Label)])
	return out


func _overlap(a: Rect2, b: Rect2) -> float:
	var i: Rect2 = a.intersection(b)
	return i.size.y if i.has_area() else 0.0


func test_the_fonts_follow_the_setting() -> void:
	var small: Node = await _built_at(0.8)
	var s: int = ((small._rows[0] as Control).get_node("Name") as Label).get_theme_font_size("font_size")
	var big: Node = await _built_at(2.0)
	var b: int = ((big._rows[0] as Control).get_node("Name") as Label).get_theme_font_size("font_size")
	assert_gt(b, s, "the formation name must GROW with Text Size: 80%% %d, 200%% %d" % [s, b])


func test_every_line_fits_at_every_preset() -> void:
	## The authored page's own overlaps at 100%, per row and pair: growth is judged against these.
	var ref: Dictionary = {}
	var m0: Node = await _built_at(1.0)
	for i in m0._rows.size():
		var p: Array = _parts(m0._rows[i] as Control)
		for a in p.size():
			for b in range(a + 1, p.size()):
				ref["%d %s %s" % [i, p[a][0], p[b][0]]] = _overlap(p[a][1], p[b][1])
	var bad: Array = []
	var judged := 0
	for scale in _presets():
		var m: Node = await _built_at(float(scale))
		var w: float = (m._list as Control).size.x
		for i in m._rows.size():
			var r: Control = m._rows[i] as Control
			var bottom: float = (r.get_node("RowBG") as Control).size.y
			var p: Array = _parts(r)
			for a in p.size():
				var ra: Rect2 = p[a][1]
				judged += 1
				if ra.position.x < 0.0 or ra.end.x > w + 0.5 or ra.end.y > bottom + 0.5:
					bad.append("%.2fx row %d %s %s leaves the row (w %.0f, bottom %.0f)" % [scale, i, p[a][0], ra, w, bottom])
				for b in range(a + 1, p.size()):
					var key: String = "%d %s %s" % [i, p[a][0], p[b][0]]
					var got: float = _overlap(ra, p[b][1])
					if got > float(ref.get(key, 0.0)) + 0.5:
						bad.append("%.2fx row %d %s meets %s by %.1fpx (100%% %.1f)" % [scale, i, p[a][0], p[b][0], got, float(ref.get(key, 0.0))])
		var note: Rect2 = _ink(m._note as Label)
		var panel_x: float = (m._list as Control).position.x
		if note.position.x < panel_x - 0.5 or note.end.x > panel_x + w + 0.5:
			bad.append("%.2fx the note %s leaves the panel [%.0f, %.0f]" % [scale, note, panel_x, panel_x + w])
		if note.end.y > (m._list as Control).position.y + 0.5:
			bad.append("%.2fx the note ends %.0f below the list top %.0f" % [scale, note.end.y, (m._list as Control).position.y])
		var title: Rect2 = _ink(m._title as Label)
		if title.end.y > note.position.y + 0.5:
			bad.append("%.2fx the title ends %.0f below the note %.0f" % [scale, title.end.y, note.position.y])
	assert_gt(judged, 60, "CONTROL: every line of every row at every preset must be judged")
	assert_eq(bad, [], "every Formations line must fit: %s" % [bad])


## CONTROL for the note arm: unwrapped at 200% the note really is wider than the panel, so the arm has teeth.
func test_the_note_would_not_fit_on_one_line_at_200() -> void:
	var m: Node = await _built_at(2.0)
	var note: Label = m._note as Label
	var one_line: float = note.get_theme_font("font").get_string_size(note.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		note.get_theme_font_size("font_size")).x
	assert_gt(one_line, (m._list as Control).size.x, "CONTROL: at 200%% the note is %.0fpx unwrapped" % one_line)
	assert_gt(note.get_line_count(), 1, "so it must wrap to more than one line")


func test_the_selected_formation_scrolls_into_view() -> void:
	var m: Node = await _built_at(2.0)
	assert_gt(float(m._scroll_max), 0.0, "CONTROL: at 200% the page must outgrow the screen")
	var ev := InputEventAction.new()
	ev.action = "ui_down"
	ev.pressed = true
	for i in m._rows.size():
		m._input(ev)
	var sel: Control = m._rows[m._selected] as Control
	var shown_bottom: float = sel.position.y + sel.size.y + (m._inner as Control).position.y
	assert_eq(int(m._selected), m._rows.size() - 1, "CONTROL: down reached the last formation")
	assert_lte(shown_bottom, (m._list as Control).size.y + 0.5,
		"the selected formation must be fully in view: bottom %.0f, list %.0f" % [shown_bottom, (m._list as Control).size.y])


func test_the_default_text_size_keeps_the_shipped_layout() -> void:
	var m: Node = await _built_at(1.0)
	var w: float = (m._list as Control).size.x
	assert_eq((m._list as Control).position.y, 92.0, "the rows start at the authored 92")
	assert_eq((m._note as Label).position.y, 58.0, "the note stays at the authored 58")
	assert_eq(float(m._scroll_max), 0.0, "nothing scrolls at 100%")
	assert_eq((m._note as Label).get_line_count(), 1, "and the note is one line")
	for i in m._rows.size():
		var r: Control = m._rows[i] as Control
		assert_eq(r.position.y, float(i) * 86.0, "row %d at the authored pitch" % i)
		assert_eq((r.get_node("Tip") as Control).position.y, 32.0, "tip at the authored 32")
		assert_eq((r.get_node("Req") as Control).position.y, 52.0, "requirements at the authored 52")
		assert_eq((r.get_node("Cost") as Control).position.x, w - 220.0, "cost at the authored spot")
