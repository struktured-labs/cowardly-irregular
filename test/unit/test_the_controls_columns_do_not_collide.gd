extends GutTest

## Regression (cowir-main's .568 render QA, 2026-10-04): on the Controls screen the Gamepad column ran into the Keyboard column:
## "R / RB / R1 (Right Shoulder)W", "Back / Select / Minus / ShareTab", "L3 / L-Stick (Left Stick Click)L". The labels were sized
## before add_child, so they grew to their text. Each column label now fits its column (font steps down, ellipsis last).

const ControlsMenuScript := preload("res://src/ui/ControlsMenu.gd")

## Column left edges in ControlsMenu: gamepad 320, keyboard 490, mouse 610.
const NEXT_COLUMN := {320.0: 490.0, 490.0: 610.0}


func _text_width(l: Label) -> float:
	return l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x


func test_no_binding_label_runs_into_the_next_column() -> void:
	var m: Control = ControlsMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	await get_tree().process_frame
	await get_tree().process_frame
	var checked := 0
	var offenders: Array[String] = []
	var stack: Array = [m]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is Label):
			continue
		var l: Label = n
		if not NEXT_COLUMN.has(l.position.x) or l.text == "":
			continue
		checked += 1
		var limit: float = NEXT_COLUMN[l.position.x]
		var drawn_end: float = l.position.x + minf(_text_width(l), l.size.x) if l.clip_text else l.position.x + _text_width(l)
		if drawn_end > limit:
			offenders.append("'%s' ends at %.0f, next column at %.0f" % [l.text, drawn_end, limit])
	assert_gt(checked, 6, "SCOPE: the walk reached the binding rows' gamepad and keyboard labels")
	assert_eq(offenders, [] as Array[String], "a column label must end before the next column: %s" % [offenders])
