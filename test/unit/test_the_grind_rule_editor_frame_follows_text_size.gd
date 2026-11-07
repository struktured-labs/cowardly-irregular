extends GutTest

## Part 2 of the grind rule editor's Text Size (the cells were .783): its frame (title, status, profile panel, details panel,
## the two-line legend, the reset dialog) drew at literal sizes. Each now takes the setting only until its own text would leave
## its box. Found on the way, live at 100%: the status line sat at size.x - 140, so its longest flash ("Nothing can follow
## Stop Grinding -- it ends the session.") ran ~200 px off the right edge of the screen.

const GE := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const LONGEST := "Nothing can follow Stop Grinding -- it ends the session."

var _ag: Dictionary
var _saved: float = 1.0


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_saved = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved
	AutogrindState.restore(_ag)


func _presets() -> Array:
	var consts: Dictionary = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map()
	var p: Array = consts.get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, got %s" % [p])
	return p


func _editor_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var ed: Control = load(GE).new()
	ed.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(ed)
	await get_tree().process_frame
	ed.setup()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(ed.get_viewport().get_visible_rect().size, Vector2(1280, 720), "CONTROL: the editor is laid out on a 1280x720 screen")
	return ed


## Where a frame label's text is DRAWN, in the editor's coordinates: a right-aligned label draws at the right end of its box.
func _drawn(l: Label, ed: Control) -> Rect2:
	var origin: Vector2 = l.global_position - ed.global_position
	var m: Vector2 = l.get_minimum_size()
	if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		origin.x += l.size.x - m.x
	return Rect2(origin, m)


## The frame: every visible Label that is not inside a grid cell.
func _frame_labels(ed: Control) -> Array:
	var out: Array = []
	for n in ed.find_children("*", "Label", true, false):
		var l := n as Label
		if not l.is_visible_in_tree() or str(l.text).strip_edges() == "" or l.is_queued_for_deletion():
			continue
		if ed._grid_container != null and ed._grid_container.is_ancestor_of(l):
			continue
		out.append(l)
	return out


func test_the_title_grows_with_the_setting() -> void:
	var seen: Array = []
	for scale in _presets():
		var ed: Control = await _editor_at(float(scale))
		seen.append(ed._title_label.get_theme_font_size("font_size"))
	assert_gt(int(seen[_presets().find(1.25)]), int(seen[_presets().find(1.0)]), "the title must grow from 100%% to 125%%: %s" % [seen])
	for i in range(1, seen.size()):
		assert_gte(int(seen[i]), int(seen[i - 1]), "the title shrank as Text Size rose: %s" % [seen])


func test_the_longest_status_stays_on_screen() -> void:
	for scale in _presets():
		var ed: Control = await _editor_at(float(scale))
		ed._status_label.text = LONGEST
		await get_tree().process_frame
		var r := _drawn(ed._status_label, ed)
		assert_gte(r.position.x, 0.0, "at %sx the status starts off the left edge: %s" % [scale, r])
		assert_lte(r.end.x, 1280.0, "at %sx the longest status runs off the right edge of the screen: %s" % [scale, r])


func test_no_frame_text_collides_or_leaves_the_screen() -> void:
	var bad: Array = []
	var judged := 0
	for scale in _presets():
		var ed: Control = await _editor_at(float(scale))
		ed._status_label.text = LONGEST
		await get_tree().process_frame
		var labels := _frame_labels(ed)
		var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
		for i in labels.size():
			var a := _drawn(labels[i], ed)
			judged += 1
			if not screen.encloses(a):
				bad.append("%sx: '%s' %s leaves the screen" % [scale, str(labels[i].text).left(24), a])
			for j in range(i + 1, labels.size()):
				if a.intersects(_drawn(labels[j], ed)):
					bad.append("%sx: '%s' overlaps '%s'" % [scale, str(labels[i].text).left(20), str(labels[j].text).left(20)])
	assert_gt(judged, 30, "FLOOR: %d frame labels judged" % judged)
	assert_eq(bad, [], "the editor's frame drew text outside its room: %s" % [bad])


func test_a_row_insert_label_keeps_its_cell() -> void:
	var ed: Control = await _editor_at(1.0)
	var seen := 0
	for c in ed._grid_container.get_children():
		if c is Control and (c as Control).has_meta("cell_type") and str((c as Control).get_meta("cell_type")) == "row_insert":
			for l in (c as Control).get_children():
				if l is Label:
					seen += 1
					assert_lte((l as Label).position.x + (l as Label).size.x, (c as Control).custom_minimum_size.x + 0.5,
						"'[++]' is %.0f wide from x %.0f in a %.0f px cell" % [(l as Label).size.x, (l as Label).position.x, (c as Control).custom_minimum_size.x])
	assert_gt(seen, 0, "CONTROL: a row-insert cell was built")
