extends GutTest

## The Controls screen grew to 13 rows of 40px in a 576px panel: "Test Buttons" drew over the conflicts line, "Map This
## Pad" over the footer, and the Action/Gamepad/Keyboard/Mouse header (placed when one row sat above it) was buried
## under the Nintendo Mode row. Rows are 32px now and the header has its own band above the action rows.

const CMENU := preload("res://src/ui/ControlsMenu.gd")


func _menu() -> Control:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child_autofree(host)
	var m: Control = CMENU.new()
	m.size = Vector2(1280, 720)
	host.add_child(m)
	return m


func _headers(m: Control) -> Array:
	var out: Array = []
	for c in m._panel.get_children():
		if c is Label and str(c.text) in ["Action", "Gamepad", "Keyboard", "Mouse"]:
			out.append(c)
	return out


func test_no_row_covers_the_footer_lines() -> void:
	var m := _menu()
	await get_tree().process_frame
	var rows: Array = m._highlight_refs
	assert_gt(rows.size(), 10, "CONTROL: the menu built its rows (%d)" % rows.size())
	var lowest := 0.0
	for r in rows:
		lowest = maxf(lowest, (r as Control).position.y + (r as Control).size.y)
	for l in [m._flash_label, m._conflict_label, m._footer_label]:
		assert_true(lowest <= (l as Label).position.y, "the last row ends at %.0f, above the line at %.0f ('%s')" % [lowest, l.position.y, str(l.text).substr(0, 20)])
	assert_true(m._footer_label.position.y + m._footer_label.size.y <= m._panel.size.y, "the footer ends inside the panel")


func test_the_column_header_has_its_own_band() -> void:
	var m := _menu()
	await get_tree().process_frame
	var heads := _headers(m)
	assert_eq(heads.size(), 4, "CONTROL: four column headers")
	for h in heads:
		var hr := Rect2((h as Label).position, (h as Label).get_minimum_size())
		for r in m._highlight_refs:
			var rr := Rect2((r as Control).position, (r as Control).size)
			assert_false(hr.intersects(rr), "'%s' at y=%.0f is not under the row at y=%.0f" % [h.text, hr.position.y, rr.position.y])
		var first_action: Control = m._highlight_refs[CMENU.ROW_ACTION_FIRST]
		assert_true(hr.end.y <= first_action.position.y and first_action.position.y - hr.end.y < 8.0, "'%s' sits directly above the first action row" % h.text)


func test_the_footer_is_not_cut_off() -> void:
	var m := _menu()
	await get_tree().process_frame
	var f: Label = m._footer_label
	assert_false(f.clip_text, "the footer wraps rather than clipping its last hints")
	assert_true(f.get_line_count() <= 2, "the footer fits its two lines (%d)" % f.get_line_count())
