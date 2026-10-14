extends GutTest

## The Lenses screen stacks three labels inside every row — name, state, passive — at y=6/26/46
## inside a `const ROW_H := 76`, with seven raw `font_size` literals and no TextScale anywhere.
## Text Size offers 200%, where those fonts are 28/22/20 and each line is taller than the 20px step
## below it, so a lens row drew its own three lines on top of each other and the last ran past the
## row into the one beneath.
##
## 🛑 All three arms, per cowir-main's rule (10:06Z): the font GREW, the grown text FITS measured on
## the built node, and a shrink-the-container mutation to prove the fit arm reads drawn text rather
## than a box. A fit-only arm passes on a raw font — small text fits by construction — and a
## font-only arm passes on the overflow.

const LensMenuScript = preload("res://src/ui/LensMenu.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")

## Mirrored from SettingsMenu rather than imported, with a control below that they still agree —
## a preset added above 2.0 must not silently leave this sweep.
const TEXT_SCALES := [0.8, 1.0, 1.25, 1.5, 2.0]


func _menu_at(scale: float) -> Control:
	if GameState:
		GameState.text_size_scale = scale
	var pc = CombatantScript.new()
	pc.combatant_name = "Bram"
	add_child_autofree(pc)
	var m = LensMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	if "party" in m:
		m.party = [pc]
	add_child_autofree(m)
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


## ARM 1: the setting must reach the text at all.
func test_the_row_fonts_grow_with_the_setting() -> void:
	var at := {}
	for scale in TEXT_SCALES:
		var m = await _menu_at(scale)
		if m._rows.is_empty():
			continue
		var r: Dictionary = m._rows[0]
		at[scale] = [
			(r["name"] as Label).get_theme_font_size("font_size"),
			(r["state"] as Label).get_theme_font_size("font_size"),
			(r["passive"] as Label).get_theme_font_size("font_size"),
		]
	assert_eq(at.size(), TEXT_SCALES.size(),
		"PRECONDITION: rows must build at every scale, got %d of %d"
		% [at.size(), TEXT_SCALES.size()])
	for i in 3:
		assert_gt(int((at.get(2.0, [0, 0, 0]) as Array)[i]), int((at.get(1.0, [0, 0, 0]) as Array)[i]),
			"row label %d must be LARGER at 200%% than 100%% — a raw font_size fits every box by "
			% i + "construction, so the fit arm below cannot see it")
		assert_lt(int((at.get(0.8, [0, 0, 0]) as Array)[i]), int((at.get(1.0, [0, 0, 0]) as Array)[i]),
			"row label %d must be SMALLER at 80%% — a one-sided check passes on a clamped font" % i)


## ARM 2: the three lines inside a row must not stack on each other, and the last must stay in the
## row. Reads each Label's BUILT rect: Control.size clamps UP to the text extent, so the rect is
## the drawn text — `font.get_height()` against an authored box reds correct layout instead.
func test_a_lens_row_never_stacks_its_own_lines() -> void:
	var bad: Array[String] = []
	var measured := 0
	for scale in TEXT_SCALES:
		var m = await _menu_at(scale)
		for i in range(m._rows.size()):
			var r: Dictionary = m._rows[i]
			var holder: Control = r["holder"]
			var name_l: Label = r["name"]
			var state_l: Label = r["state"]
			var pass_l: Label = r["passive"]
			measured += 1
			if name_l.position.y + name_l.size.y > state_l.position.y:
				bad.append("%.2fx row %d: name ends %.0f, state starts %.0f"
					% [scale, i, name_l.position.y + name_l.size.y, state_l.position.y])
			elif state_l.position.y + state_l.size.y > pass_l.position.y:
				bad.append("%.2fx row %d: state ends %.0f, passive starts %.0f"
					% [scale, i, state_l.position.y + state_l.size.y, pass_l.position.y])
			elif pass_l.position.y + pass_l.size.y > holder.size.y:
				bad.append("%.2fx row %d: passive ends %.0f in a %.0f row"
					% [scale, i, pass_l.position.y + pass_l.size.y, holder.size.y])
	assert_gt(measured, 10,
		"CONTROL: rows must have been measured across the sweep — only %d" % measured)
	assert_eq(bad, [] as Array[String],
		"a Lenses row stacks its own lines: %s" % [", ".join(bad)])


## And the rows must not run into each other, nor the status line into the last row.
func test_the_lens_rows_and_status_keep_clear_of_each_other() -> void:
	var bad: Array[String] = []
	var measured := 0
	for scale in TEXT_SCALES:
		var m = await _menu_at(scale)
		for i in range(m._rows.size() - 1):
			var a: Control = (m._rows[i] as Dictionary)["holder"]
			var b: Control = (m._rows[i + 1] as Dictionary)["holder"]
			measured += 1
			if a.position.y + a.size.y > b.position.y:
				bad.append("%.2fx: row %d ends %.0f, row %d starts %.0f"
					% [scale, i, a.position.y + a.size.y, i + 1, b.position.y])
		if not m._rows.is_empty() and m._status != null:
			var last: Control = (m._rows[m._rows.size() - 1] as Dictionary)["holder"]
			if last.position.y + last.size.y > m._status.position.y:
				bad.append("%.2fx: last row ends %.0f, status starts %.0f"
					% [scale, last.position.y + last.size.y, m._status.position.y])
	assert_gt(measured, 5,
		"CONTROL: adjacent rows must have been compared — only %d pairs" % measured)
	assert_eq(bad, [] as Array[String],
		"Lenses rows collide with each other or with the status line: %s" % [", ".join(bad)])
