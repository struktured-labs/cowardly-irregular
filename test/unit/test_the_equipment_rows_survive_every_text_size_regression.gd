extends GutTest

## EquipmentMenu was the best-built of the four census files and still ignored Text Size: its row
## strides are DERIVED — `_slot_stride` from `_slot_body_y` from `_ui_line_height` — but that
## helper took a RAW font size, so the geometry was correct in shape and frozen at the default
## scale while 19 `add_theme_font_size_override` literals never moved either.
##
## The fix scales the helper, so every derived y and stride follows from one place, and callers
## keep passing the BASE size. That keeps one source of truth for the override and for the box
## that holds it — the two-expressions-for-one-quantity trap that cost this lane a correction on
## LensMenu earlier today.
##
## 🛑 Three arms, per cowir-main's rule: the font GREW, the grown text FITS measured on the built
## node, and a shrink-the-container mutation proving arm 2 reads drawn text rather than a box.

const EquipmentMenuScript = preload("res://src/ui/EquipmentMenu.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")

const TEXT_SCALES := [0.8, 1.0, 1.25, 1.5, 2.0]


func _menu_at(scale: float) -> Control:
	if GameState:
		GameState.text_size_scale = scale
	var pc = CombatantScript.new()
	pc.combatant_name = "Bram"
	add_child_autofree(pc)
	var m = EquipmentMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.setup(pc)
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func after_each() -> void:
	if GameState:
		GameState.text_size_scale = 1.0


func test_the_sweep_matches_the_shipped_presets() -> void:
	var settings := load("res://src/ui/SettingsMenu.gd")
	assert_eq(TEXT_SCALES, settings.TEXT_SIZE_PRESETS as Array,
		"this file sweeps %s but SettingsMenu offers %s"
		% [str(TEXT_SCALES), str(settings.TEXT_SIZE_PRESETS)])


## ARM 1 — without this, the fit arm below passes on a raw font, because small text fits by
## construction. Reads the slot row's own labels rather than a helper's return value.
func test_the_row_fonts_grow_with_the_setting() -> void:
	var sizes := {}
	for scale in TEXT_SCALES:
		var m = await _menu_at(scale)
		if m._slot_labels.is_empty():
			continue
		var biggest := 0
		for child in (m._slot_labels[0] as Control).get_children():
			var l := child as Label
			if l != null:
				biggest = maxi(biggest, l.get_theme_font_size("font_size"))
		sizes[scale] = biggest
	assert_eq(sizes.size(), TEXT_SCALES.size(),
		"PRECONDITION: slot rows must build at every scale, got %d of %d"
		% [sizes.size(), TEXT_SCALES.size()])
	assert_gt(int(sizes.get(2.0, 0)), int(sizes.get(1.0, 0)),
		"slot row text must be LARGER at 200%% than 100%% (200%%=%s, 100%%=%s)"
		% [str(sizes.get(2.0)), str(sizes.get(1.0))])
	assert_lt(int(sizes.get(0.8, 0)), int(sizes.get(1.0, 0)),
		"and SMALLER at 80%% — a one-sided check passes on a font clamped at its maximum")


## ARM 2 — the derived stride must actually clear the text it was derived for.
func test_slot_rows_never_collide_at_any_text_size() -> void:
	var bad: Array[String] = []
	var measured := 0
	for scale in TEXT_SCALES:
		var m = await _menu_at(scale)
		var rows: Array = m._slot_labels
		for i in range(rows.size() - 1):
			var a: Control = rows[i]
			var b: Control = rows[i + 1]
			measured += 1
			if a.position.y + a.size.y > b.position.y:
				bad.append("%.2fx: slot %d ends %.0f, slot %d starts %.0f"
					% [scale, i, a.position.y + a.size.y, i + 1, b.position.y])
	assert_gt(measured, 5,
		"CONTROL: adjacent slot rows must have been compared — only %d pairs" % measured)
	assert_eq(bad, [] as Array[String],
		"equipment slot rows collide: %s" % [", ".join(bad)])


## And no label may draw below the row that holds it — the stride is derived FROM these labels, so
## this is the arm that catches the derivation going out of step with what it reserves for.
func test_no_slot_label_draws_past_its_row() -> void:
	var over: Array[String] = []
	var measured := 0
	for scale in TEXT_SCALES:
		var m = await _menu_at(scale)
		for i in range(m._slot_labels.size()):
			var row: Control = m._slot_labels[i]
			for child in row.get_children():
				var l := child as Label
				if l == null or str(l.text).strip_edges() == "":
					continue
				measured += 1
				if l.position.y + l.size.y > row.size.y:
					over.append("%.2fx slot %d: '%s' ends %.0f in a %.0f row"
						% [scale, i, str(l.text).substr(0, 14),
						   l.position.y + l.size.y, row.size.y])
	assert_gt(measured, 10,
		"CONTROL: slot labels must have been measured across the sweep — only %d" % measured)
	assert_eq(over, [] as Array[String],
		"an equipment slot label draws past its own row: %s" % [", ".join(over)])
