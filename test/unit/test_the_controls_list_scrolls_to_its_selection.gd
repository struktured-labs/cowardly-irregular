extends GutTest

## main 26309: the Controls rows grow with Text Size and the list SCROLLS when it outgrows the panel, never shrinks to fit.
## Walks the cursor down and back up at every preset: the selected row is always wholly inside the clipped window.

const CM := "res://src/ui/ControlsMenu.gd"

var _saved = null


func before_each() -> void:
	_saved = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _saved


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step (%s)" % [p])
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


func test_the_floor_names_every_member_this_file_drives() -> void:
	var m: Array = (load(CM) as GDScript).get_script_method_list().map(func(x): return str(x["name"]))
	for f in ["_update_selection", "_scroll_to_selection", "rows_content_height", "_row_h"]:
		assert_has(m, f, "ControlsMenu.%s must exist" % f)


func _off_window(m: Control, tag: String) -> String:
	var row: Control = m._highlight_refs[m.selected_index]
	var r := row.get_global_rect()
	var w: Rect2 = (m._rows_clip as Control).get_global_rect()
	if r.position.y < w.position.y - 0.5 or r.end.y > w.end.y + 0.5:
		return "%s row %d %s outside the window %s" % [tag, m.selected_index, r, w]
	return ""


func test_the_selected_row_is_always_wholly_in_view() -> void:
	var bad: Array = []
	var overflowed := 0
	var steps := 0
	for s in _presets():
		var m := await _menu_at(float(s))
		assert_true((m._rows_clip as Control).clip_contents, "CONTROL @%s: the row window clips" % s)
		if m.rows_content_height() > (m._rows_clip as Control).size.y:
			overflowed += 1
		var order: Array = range(m._item_count) + range(m._item_count - 2, -1, -1)
		for i in order:
			m.selected_index = i
			m._update_selection()
			await get_tree().process_frame
			steps += 1
			var why := _off_window(m, "%s%%" % int(roundf(float(s) * 100.0)))
			if why != "":
				bad.append(why)
		m.get_parent().get_parent().queue_free()
		await get_tree().process_frame
	assert_gt(steps, 10 * _presets().size(), "CONTROL: the cursor walked every row (%d steps)" % steps)
	assert_gt(overflowed, 0, "CONTROL: at least one preset outgrows the window, so the walk exercises a real scroll")
	assert_eq(bad, [], "the selected row stays in view:\n%s" % "\n".join(PackedStringArray(bad)))


## 100% is the shipped layout: nothing outgrows the window, so the list never scrolls.
func test_the_default_size_never_scrolls() -> void:
	var m := await _menu_at(1.0)
	assert_lte(m.rows_content_height(), (m._rows_clip as Control).size.y, "at 100%% every row fits the window")
	for i in range(m._item_count):
		m.selected_index = i
		m._update_selection()
		assert_eq((m._rows_content as Control).position.y, 0.0, "row %d scrolled the list at 100%%" % i)
