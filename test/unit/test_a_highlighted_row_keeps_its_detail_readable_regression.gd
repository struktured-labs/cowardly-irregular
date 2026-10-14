extends GutTest

## Every list menu paints the row you are standing on with SELECTED_COLOR and prints the row's
## detail — MP cost, item description, a job's ability list — in DISABLED_COLOR. Measured against
## each other those two are **1.46:1**, so the detail on the row you selected is the one that
## disappears, while the same text stays legible on every row you are NOT on (3.01:1).
##
##   DISABLED_COLOR on SELECTED_COLOR   1.46:1     <- the defect
##   SUBTITLE_COLOR on SELECTED_COLOR   4.61:1     <- the repo's own fix, already in JobMenu
##   SUBTITLE_COLOR on PANEL_COLOR      9.47:1
##
## JobMenu recorded this in 2026 as "DISABLED_COLOR there measured ~1.5:1 and the job vanished on
## whichever card you were on" and added SUBTITLE_COLOR — but only for the slot panel. The job
## LIST rows two functions away kept the grey, and so did AbilitiesMenu's MP cost and
## EquipmentMenu's description. The fix existed; it had not been carried.
##
## 🛑 WALKS THE BUILT SCENE, NOT THE SOURCE. A source scan asserts which constant is named; it
## cannot see a row that takes its colour from a theme, a parent, or a second code path. This finds
## the ColorRect actually painted SELECTED_COLOR and reads the Labels actually sitting on it.

const AbilitiesMenuScript = preload("res://src/ui/AbilitiesMenu.gd")
const EquipmentMenuScript = preload("res://src/ui/EquipmentMenu.gd")
const JobMenuScript = preload("res://src/ui/JobMenu.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")

## WCAG AA for small text is 4.5:1. The bar here is 3.0 — deliberately below the shipped fix's
## 4.61 — so this guard fails on the DEFECT rather than on a designer picking a slightly dimmer
## blue. A threshold set at exactly the shipped value turns every palette tweak into a red.
const MIN_CONTRAST := 3.0


func _relative_luminance(c: Color) -> float:
	var ch := [c.r, c.g, c.b]
	var lin := []
	for v in ch:
		lin.append(v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


func _contrast(a: Color, b: Color) -> float:
	var la := _relative_luminance(a)
	var lb := _relative_luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## ⚠️ The JOB is not decoration here: `AbilitiesMenu` builds its list from
## `character.get_known_abilities()`, which is empty without one — and an empty list draws no rows,
## so the arm below would find nothing highlighted and pass having measured no colours at all.
## That is why it carries a precondition rather than trusting the walk.
func _character() -> Combatant:
	var pc = CombatantScript.new()
	pc.combatant_name = "Bram"
	pc.job = JobSystem.get_job("fighter")
	add_child_autofree(pc)
	return pc


## Every row currently painted with `sel` — found by the ColorRect that paints it, so a row whose
## highlight arrives by another route is still caught.
func _highlighted_rows(node: Node, sel: Color, out: Array) -> void:
	for child in node.get_children():
		if child is ColorRect:
			var rect := child as ColorRect
			if rect.color.is_equal_approx(sel):
				out.append(rect.get_parent())
		_highlighted_rows(child, sel, out)


## The worst-contrast Label sitting on a highlighted row, as "menu/text contrast".
func _unreadable(menu: Node, sel: Color, label: String) -> Array[String]:
	var rows: Array = []
	_highlighted_rows(menu, sel, rows)
	var bad: Array[String] = []
	for row in rows:
		for child in (row as Node).get_children():
			var l := child as Label
			if l == null or str(l.text).strip_edges() == "":
				continue
			var fg: Color = l.get_theme_color("font_color")
			var c := _contrast(fg, sel)
			if c < MIN_CONTRAST:
				bad.append("%s '%s' %.2f:1" % [label, str(l.text).substr(0, 20), c])
	return bad


## CONTROL: the contrast maths must reproduce the two numbers this file is built on, or every
## verdict below is computed by something that does not measure contrast.
func test_the_contrast_formula_reproduces_the_recorded_values() -> void:
	var sel := Color(0.2, 0.3, 0.5)
	assert_almost_eq(_contrast(Color(0.4, 0.4, 0.4), sel), 1.46, 0.02,
		"CONTROL: DISABLED_COLOR on SELECTED_COLOR is the ~1.5:1 JobMenu recorded")
	assert_almost_eq(_contrast(Color(0.72, 0.75, 0.85), sel), 4.61, 0.02,
		"CONTROL: SUBTITLE_COLOR on SELECTED_COLOR is the fix")
	assert_almost_eq(_contrast(Color.WHITE, Color.BLACK), 21.0, 0.1,
		"CONTROL: the formula's fixed point")
	assert_true(_contrast(Color(0.4, 0.4, 0.4), sel) < MIN_CONTRAST,
		"CONTROL: the bar must actually reject the defect's colour")
	assert_true(_contrast(Color(0.72, 0.75, 0.85), sel) >= MIN_CONTRAST,
		"CONTROL: and accept the fix's")


func test_the_selected_ability_row_shows_its_mp_cost() -> void:
	var m = AbilitiesMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.setup(_character())
	await get_tree().process_frame
	await get_tree().process_frame
	var rows: Array = []
	_highlighted_rows(m, m.SELECTED_COLOR, rows)
	assert_gt(rows.size(), 0,
		"PRECONDITION: a row must be highlighted, or this arm reads nothing")
	var bad := _unreadable(m, m.SELECTED_COLOR, "AbilitiesMenu")
	assert_eq(bad, [] as Array[String],
		"the MP cost of the ability you are standing on is unreadable on its own highlight: %s"
		% [", ".join(bad)])


func test_the_selected_equipment_row_shows_its_description() -> void:
	var m = EquipmentMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.setup(_character())
	await get_tree().process_frame
	await get_tree().process_frame
	var bad := _unreadable(m, m.SELECTED_COLOR, "EquipmentMenu")
	assert_eq(bad, [] as Array[String],
		"a highlighted equipment row hides its own detail: %s" % [", ".join(bad)])


func test_the_selected_job_row_shows_its_detail() -> void:
	var m = JobMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.setup(_character())
	await get_tree().process_frame
	await get_tree().process_frame
	var bad := _unreadable(m, m.SELECTED_COLOR, "JobMenu")
	assert_eq(bad, [] as Array[String],
		"a highlighted job row hides its own detail: %s" % [", ".join(bad)])
