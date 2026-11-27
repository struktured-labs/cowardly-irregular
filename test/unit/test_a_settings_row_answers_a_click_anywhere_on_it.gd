extends GutTest

## Settings rows took the mouse through a Button sized from literals (400 x 56-80) while each row is 752 wide and grows
## with Text Size: a click on a row's right half, or on the lower part of a grown row, did nothing. The Controls screen
## guards the same shape (test_the_controls_screen_grows_with_the_text arm 5); Settings did not.

const SM := "res://src/ui/SettingsMenu.gd"

var _saved = null


func before_each() -> void:
	_saved = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _saved


func _presets() -> Array:
	var p: Array = (load(SM) as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step (%s)" % [p])
	return p


func _menu_at(scale: float) -> Control:
	GameState.text_size_scale = scale
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var m: Control = load(SM).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func test_the_floor_names_what_this_file_drives() -> void:
	var props: Array = (load(SM) as GDScript).get_script_property_list().map(func(p): return str(p["name"]))
	assert_has(props, "_settings_items", "SettingsMenu._settings_items must exist")


## Every row's click target covers exactly the row that is drawn, at every Text Size.
func test_every_click_target_is_its_whole_row_at_every_size() -> void:
	var bad: Array = []
	var judged := 0
	var wider_than_400 := 0
	for s in _presets():
		var m := await _menu_at(float(s))
		for it in m._settings_items:
			var row: Control = it["control"]
			for c in row.get_children():
				if not (c is Button):
					continue
				judged += 1
				if row.size.x > 400.5:
					wider_than_400 += 1
				var b := c as Button
				if not Rect2(b.position, b.size).is_equal_approx(Rect2(Vector2.ZERO, row.size)):
					bad.append("%d%% %s: click target %s, row %s" % [int(roundf(float(s) * 100.0)), it.get("id", "?"), Rect2(b.position, b.size), row.size])
		m.get_parent().queue_free()
		await get_tree().process_frame
	assert_gt(judged, 100, "CONTROL: click targets were judged (%d)" % judged)
	assert_gt(wider_than_400, 0, "CONTROL: rows are wider than the literal 400 px, so a 400 px target could be told apart (%d)" % wider_than_400)
	assert_eq(bad, [], "every Settings row answers a click anywhere on it:\n%s" % "\n".join(PackedStringArray(bad.slice(0, 12))))


## Behaviour, not just geometry (adhoc 28702): the mouse moved onto a row's RIGHT half, low in the row, selects that row
## through the real viewport input path. Hover selects without activating, so no setting is changed by the test.
func test_the_mouse_on_a_rows_right_half_selects_it() -> void:
	for s in [1.0, 2.0]:
		var m := await _menu_at(s)
		var vp: SubViewport = m.get_parent()
		var view := Rect2(m._scroll.global_position, m._scroll.size)
		var target := -1
		var at := Vector2.ZERO
		for i in m._settings_items.size():
			if i == m.selected_index:
				continue
			var r: Rect2 = (m._settings_items[i]["control"] as Control).get_global_rect()
			var p := Vector2(r.end.x - 24.0, r.end.y - 4.0)
			if r.size.x > 500.0 and view.has_point(p) and p.x > r.position.x + 420.0:
				target = i
				at = p
				break
		assert_gt(target, -1, "PRECONDITION: a fully visible row at %.0f%% to point at, beyond the old 400 px target" % (s * 100.0))
		if target < 0:
			continue
		assert_ne(m.selected_index, target, "CONTROL: the row is not already selected")
		for p in [at + Vector2(-6, -2), at]:
			var ev := InputEventMouseMotion.new()
			ev.position = p
			ev.global_position = p
			vp.push_input(ev)
			await get_tree().process_frame
		assert_eq(m.selected_index, target, "%.0f%%: the mouse at %s on row %d's right half, low in the row, selects it" % [s * 100.0, at, target])
		vp.queue_free()
		await get_tree().process_frame
