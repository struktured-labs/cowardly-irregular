extends GutTest

## Census #4 (main 27587): ControlsMenu `_fit_column_label` stepped a binding label's font down to 10px and trimmed
## it with an ellipsis, so "R / RB / R1 (Right Shoulder)" lost its end and a Text Size was taken straight back off.
## Now it wraps at its own size inside its column and its row grows to hold it; the rows below move down.

const CM := "res://src/ui/ControlsMenu.gd"
const BINDING_PX := 13

var _saved = null


func before_each() -> void:
	_saved = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _saved


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, or every preset loop passes empty: " + str(p))
	return p


func _menu_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var layer := CanvasLayer.new()
	vp.add_child(layer)
	var m: Control = load(CM).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


## [{label, row, col_w}] for every label sitting in a binding column.
func _bindings(m: Control) -> Array:
	var out: Array = []
	var xs: Array = m._col_x()
	var ws: Array = m._col_w()
	for i in range(m._highlight_refs.size()):
		var h: Control = m._highlight_refs[i]
		for c in h.get_children():
			if not (c is Label) or (c as Label).text == "":
				continue
			for k in range(1, xs.size()):
				if absf((c as Label).position.x - float(xs[k])) < 2.0:
					out.append({"label": c, "row": i, "col_w": float(ws[k - 1])})
	return out


func _one_line_w(l: Label) -> float:
	return l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, TextScale.scaled(BINDING_PX)).x


## CONTROL: at 200% some binding's one-line text is wider than its column, so the arms below can see a shrink or a trim.
## Also prints every label that does not fit on one line at 100%: those are the rows the old code shrank there.
func test_control_a_binding_outgrows_its_column() -> void:
	var at_one: Array = []
	var m1: Control = await _menu_at(1.0)
	for b in _bindings(m1):
		if _one_line_w(b["label"]) > float(b["col_w"]) + 0.5:
			at_one.append("'%s' %.0f in %.0f" % [(b["label"] as Label).text, _one_line_w(b["label"]), b["col_w"]])
	gut.p("AT 1.0, wider than the column: %s" % [at_one])
	var over: int = 0
	var m2: Control = await _menu_at(2.0)
	var all2: Array = _bindings(m2)
	assert_gt(all2.size(), 6, "PRECONDITION: the binding labels were found")
	for b in all2:
		if _one_line_w(b["label"]) > float(b["col_w"]) + 0.5:
			over += 1
	assert_gt(over, 0, "CONTROL: at 200% at least one binding is wider than its column on one line")


## Every preset: the binding keeps the Text Size, is not trimmed, stays inside its column and ends inside its own row.
func test_a_binding_keeps_its_size_and_wraps_inside_its_row() -> void:
	var bad: Array = []
	var wrapped_at_two: int = 0
	for scale in _presets():
		var m: Control = await _menu_at(float(scale))
		for b in _bindings(m):
			var l: Label = b["label"]
			var row_h: float = float(m._row_hgt.get(b["row"], -1.0))
			if l.get_theme_font_size("font_size") != TextScale.scaled(BINDING_PX):
				bad.append("%.2fx '%s' drawn at %d px, the setting asks %d" % [scale, l.text, l.get_theme_font_size("font_size"), TextScale.scaled(BINDING_PX)])
			if l.clip_text or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
				bad.append("%.2fx '%s' is clipped or trimmed" % [scale, l.text])
			if l.size.x > float(b["col_w"]) + 0.5:
				bad.append("%.2fx '%s' is %.0f wide in a %.0f column" % [scale, l.text, l.size.x, b["col_w"]])
			var bottom: float = l.position.y + l.get_minimum_size().y
			if bottom > row_h + 0.5:
				bad.append("%.2fx '%s' ends at %.0f in a %.0f row" % [scale, l.text, bottom, row_h])
			if is_equal_approx(float(scale), 2.0) and l.get_line_count() > 1:
				wrapped_at_two += 1
	assert_gt(wrapped_at_two, 0, "CONTROL: at 200% some binding actually wraps to more than one line")
	assert_eq(bad, [], "a binding wraps at its Text Size inside its column and row: %s" % [bad])


## Every preset: rows stack by their own heights, never overlap, the click target is the drawn row, and the
## scroll height ends at the last row's own bottom. A row with nothing wrapped keeps the authored height.
func test_the_rows_stack_by_their_own_heights() -> void:
	var bad: Array = []
	for scale in _presets():
		var m: Control = await _menu_at(float(scale))
		var n: int = m._highlight_refs.size()
		var wrapped_rows: Dictionary = {}
		for b in _bindings(m):
			if (b["label"] as Label).get_line_count() > 1:
				wrapped_rows[b["row"]] = true
		for i in range(n):
			var h: Control = m._highlight_refs[i]
			var rh: float = float(m._row_hgt[i])
			if absf(h.size.y - rh) > 0.5:
				bad.append("%.2fx row %d draws %.0f, recorded %.0f" % [scale, i, h.size.y, rh])
			for c in h.get_children():
				if c is Button and absf((c as Button).size.y - rh) > 0.5:
					bad.append("%.2fx row %d clicks %.0f tall, draws %.0f" % [scale, i, (c as Button).size.y, rh])
			if not wrapped_rows.has(i) and int(rh) != int(m._row_h()):
				bad.append("%.2fx row %d wraps nothing yet is %.0f, not %d" % [scale, i, rh, m._row_h()])
			if i + 1 < n and float(m._row_top[i + 1]) < float(m._row_top[i]) + rh - 0.5:
				bad.append("%.2fx row %d starts at %.0f, inside row %d (ends %.0f)" % [scale, i + 1, m._row_top[i + 1], i, float(m._row_top[i]) + rh])
		var last_bottom: float = float(m._row_top[n - 1]) + float(m._row_hgt[n - 1])
		if absf(m.rows_content_height() - last_bottom) > 0.5:
			bad.append("%.2fx scroll height %.0f, last row ends %.0f" % [scale, m.rows_content_height(), last_bottom])
	assert_eq(bad, [], "rows stack by their own heights: %s" % [bad])


## A binding whose text changes after the build (a rebind) re-lays the rows: its row grows and the next one moves down.
func test_a_longer_binding_regrows_its_row() -> void:
	var m: Control = await _menu_at(1.0)
	var first: int = m.ROW_ACTION_FIRST
	var l: Label = null
	for b in _bindings(m):
		if b["row"] == first and absf((b["label"] as Label).position.x - float(m._col_x()[1])) < 2.0:
			l = b["label"]
	assert_not_null(l, "PRECONDITION: the first action row has a gamepad label")
	if l == null:
		return
	var before_h: float = float(m._row_hgt[first])
	var next_top: float = float(m._row_top[first + 1])
	l.text = "Left Shoulder / Left Bumper / L1 (held, then released)"
	m._relayout_rows()
	assert_gt(float(m._row_hgt[first]), before_h, "the row grows to hold the longer binding")
	assert_almost_eq(float(m._row_top[first + 1]), next_top + float(m._row_hgt[first]) - before_h, 0.5, "and the next row moves down by exactly that")
	await get_tree().process_frame
	assert_gt(l.get_line_count(), 1, "the label itself wraps the longer binding")
	assert_lte(l.position.y + l.get_minimum_size().y, float(m._row_hgt[first]) + 0.5, "and the label's own wrapped height ends inside the grown row")
