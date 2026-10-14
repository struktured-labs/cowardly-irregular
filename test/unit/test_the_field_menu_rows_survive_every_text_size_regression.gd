extends GutTest

## The field menu (the overworld menu — Party, Items, Quest Log, Save) is the most-used menu in the
## game, and its rows were laid out with literals while the label inside them scales:
##
##     item_height = 28          the pitch between rows
##     item.size   = (200, 24)   the row
##     highlight   = (180, 24)   the selection
##     label font  = TextScale.scaled(14)
##
## Text Size offers 200% (SettingsMenu.TEXT_SIZE_PRESETS tops out at 2.0). At that scale the label
## is 28px on a 24px row at a 28px pitch, so the rows collided with each other and the labels ran
## outside their own highlight. Nothing guarded it: no test named OverworldMenu and a text scale
## together, which is why it survived every other Text Size fix this month.
##
## 🛑 DRIVES THE REAL PRESETS. A guard that checks one scale proves the layout works at one scale;
## the defect is a FUNCTION of the scale, so the arm has to sweep the values the player can pick.

const OverworldMenuScript = preload("res://src/ui/OverworldMenu.gd")

## The scales SettingsMenu actually offers. Mirrored, not imported, so a preset being REMOVED does
## not silently shrink this sweep — the control below asserts they still agree.
const TEXT_SCALES := [0.8, 1.0, 1.25, 1.5, 2.0]


const CombatantScript = preload("res://src/battle/Combatant.gd")


## ⚠️ `setup()` is not optional here: `_menu_options` starts EMPTY and only setup fills it from
## BASE_MENU_OPTIONS, so a menu built without it draws no rows at all and every arm below would
## skip its loop and pass having measured nothing. The `measured` controls exist for that reason.
func _menu_at(scale: float) -> Control:
	if GameState:
		GameState.text_size_scale = scale
	var pc = CombatantScript.new()
	pc.combatant_name = "Bram"
	add_child_autofree(pc)
	var m = OverworldMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.setup([pc])
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func after_each() -> void:
	if GameState:
		GameState.text_size_scale = 1.0


## CONTROL: the sweep must still match what the player can choose, or a preset added above 2.0
## goes untested while this file reads as covering "every text size".
func test_the_sweep_matches_the_shipped_presets() -> void:
	## ⛔ READ THROUGH `get_script_constant_map()`, NOT `settings.TEXT_SIZE_PRESETS`. A direct const
	## read on a renamed or removed constant is a RUNTIME ERROR mid-arm, and GUT scores an aborted
	## body as a PASS — so this pin would go GREEN in precisely the case it exists for. The map form
	## yields [] and reds by name. And if the map form were wrong the other way round it would red
	## on a CLEAN tree, which is the safe direction for an instrument change.
	var settings: Script = load("res://src/ui/SettingsMenu.gd")
	var presets: Array = settings.get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_eq(TEXT_SCALES, presets,
		"this file sweeps %s but SettingsMenu offers %s" % [str(TEXT_SCALES), str(presets)])


## The info block UNDER the rows has the same shape and was missed by the first version of this
## fix: play time / location / corruption stepped by a literal 16 with `TextScale.scaled(11)`
## labels, which that font outgrows at 150% and above. Fixing the rows and leaving these would
## have been half a fix in a file I had just opened.
func test_the_info_lines_never_collide_at_any_text_size() -> void:
	var bad: Array[String] = []
	var measured := 0
	for scale in TEXT_SCALES:
		var m = await _menu_at(scale)
		var found: Array = []
		_collect_labels(m, found)
		var play: Label = null
		var loc: Label = null
		for l in found:
			if str((l as Label).text).begins_with("Play Time:"):
				play = l
			elif str((l as Label).text).begins_with("Location:"):
				loc = l
		if play == null or loc == null:
			continue
		measured += 1
		if play.position.y + play.size.y > loc.position.y:
			bad.append("%.2fx: play time ends %.0f, location starts %.0f"
				% [scale, play.position.y + play.size.y, loc.position.y])
	assert_gt(measured, 3,
		"CONTROL: the info lines must have been found at most scales — only %d" % measured)
	assert_eq(bad, [] as Array[String],
		"the field menu's info lines overlap each other: %s" % [", ".join(bad)])


func _collect_labels(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Label:
			out.append(child)
		_collect_labels(child, out)


## ⛔ AND THE FIT ARMS ALONE ARE BLIND TO THE OTHER HALF OF THIS CLASS. @cowir-story measured it
## on four surfaces today: a fit-only guard passes on a RAW font, because small text fits its box
## by construction — two of their four surfaces had a guard that was green on the exact defect it
## was written for. The working rule is BOTH: the font GREW with the setting, and the grown text
## FITS. Either alone is green on a real defect, in opposite directions.
func test_the_label_font_actually_grows_with_the_setting() -> void:
	var sizes := {}
	for scale in TEXT_SCALES:
		var m = await _menu_at(scale)
		for row in m._menu_labels:
			var l := (row as Control).get_node_or_null("Label") as Label
			if l != null:
				sizes[scale] = l.get_theme_font_size("font_size")
				break
	assert_eq(sizes.size(), TEXT_SCALES.size(),
		"PRECONDITION: a label must be readable at every scale, got %d of %d"
		% [sizes.size(), TEXT_SCALES.size()])
	assert_gt(int(sizes.get(2.0, 0)), int(sizes.get(1.0, 0)),
		"the field menu label must be LARGER at 200%% than at 100%% — a raw font_size fits every "
		+ "box by construction, so the fit arms cannot see it (200%%=%s, 100%%=%s)"
		% [str(sizes.get(2.0)), str(sizes.get(1.0))])
	assert_lt(int(sizes.get(0.8, 0)), int(sizes.get(1.0, 0)),
		"and SMALLER at 80%% — a one-sided check passes on a font clamped at its maximum")


## THE REGRESSION: the LABEL's drawn line must fit the row it is in, and must not reach the row
## beneath it.
##
## ⛔ THIS ARM FIRST MEASURED THE ITEM RECTS AND WAS HOLLOW. With `item_height = 28` and
## `item.size = (200, 24)` the rects NEVER overlap — there is always a 4px gap — so reverting the
## fix left it green. The boxes were never the thing that collided; the TEXT was. A 28px font at
## 200% draws a ~34px line inside a 24px row and over the row below it, while every rect in the
## scene still looks tidy. Measure what is drawn, not what contains it.
func test_label_lines_never_reach_the_row_beneath_at_any_text_size() -> void:
	var bad: Array[String] = []
	var measured := 0
	for scale in TEXT_SCALES:
		var m = await _menu_at(scale)
		var rows: Array = m._menu_labels
		if rows.size() < 2:
			continue
		for i in range(rows.size()):
			var row: Control = rows[i]
			var l := row.get_node_or_null("Label") as Label
			if l == null:
				continue
			measured += 1
			## ⚠️ The BUILT NODE's rect, not `font.get_height(size)`. A Label clamps its own height
			## up to its content, so an authored box is routinely UNDER get_height while drawing
			## correctly — @cowir-story measured three correct shipped layouts failing that
			## predicate. The rect is what the node resolved to, which is the thing to compare.
			var line_h: float = l.size.y
			var text_bottom: float = row.position.y + l.position.y + line_h
			# inside its own row
			if l.position.y + line_h > row.size.y:
				bad.append("%.2fx: row %d text is %.0fpx in a %.0fpx row"
					% [scale, i, l.position.y + line_h, row.size.y])
				break
			# and clear of the next row's top
			if i + 1 < rows.size() and text_bottom > (rows[i + 1] as Control).position.y:
				bad.append("%.2fx: row %d text reaches %.0f, row %d starts %.0f"
					% [scale, i, text_bottom, i + 1, (rows[i + 1] as Control).position.y])
				break
	assert_gt(measured, 10,
		"CONTROL: labels must have been measured across the sweep — only %d" % measured)
	assert_eq(bad, [] as Array[String],
		"field menu label text collides with its own row or the row beneath: %s"
		% [", ".join(bad)])


## And a row's own label must stay inside the row — the highlight is anchored to it, so a label
## past the row's edge is a label outside the selection the player is looking at.
func test_every_label_stays_inside_its_row_at_any_text_size() -> void:
	var over: Array[String] = []
	var measured := 0
	for scale in TEXT_SCALES:
		var m = await _menu_at(scale)
		for row in m._menu_labels:
			var l := (row as Control).get_node_or_null("Label") as Label
			if l == null:
				continue
			var font: Font = l.get_theme_font("font")
			if font == null:
				continue
			measured += 1
			var fs: int = l.get_theme_font_size("font_size")
			## -1: this label does not autowrap, so a width-limited query would report the wrapped
			## size — the fixed geometry — for a label that draws one long line.
			var w: float = font.get_string_size(str(l.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var right: float = l.position.x + w
			if right > (row as Control).size.x:
				over.append("%.2fx: '%s' ends %.0f of %.0f"
					% [scale, str(l.text), right, (row as Control).size.x])
	assert_gt(measured, 10,
		"CONTROL: labels must have been measured at several scales — only %d" % measured)
	assert_eq(over, [] as Array[String],
		"a field menu label runs outside its own row: %s" % [", ".join(over)])
