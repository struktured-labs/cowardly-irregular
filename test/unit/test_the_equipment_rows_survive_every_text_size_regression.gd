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
##
## ⛔ AND TWO THINGS THOSE THREE ARMS CANNOT SEE, both added below.
##
## 1. EVERY ONE OF THEM IS ABOUT Y. Three measurement arms, zero width expressions — on a screen
##    whose name boxes are literal `Vector2(280, 32)` and `Vector2(420, 32)` while the fonts inside
##    them scale. A Label with neither `clip_text` nor a wrap clamps its size UP to its content, so
##    the assigned width is a suggestion and `size.x` is the DRAWN width. (The description label is
##    already safe: anchored with `clip_text`, the idiom this file established after its text drew
##    897px inside an 800px row.)
##
## 2. THE MODE IS A SWEEP DIMENSION AND WAS NEVER SET. `Mode.SLOT_SELECT` builds the three slot
##    rows; `Mode.ITEM_SELECT` builds the item LIST through `_create_item_row`; only one exists at a
##    time. So `_create_item_row` — the 420px box, the unbounded stat line — has never been
##    measured at any preset. Identical hole to JobMenu's, where omitting the mode left a whole
##    panel unbuilt and a column-pitch mutation INERT against every arm.
##
## The fixture above is also the shortest corpus the screen has: a bare Combatant equips nothing, so
## every slot row reads "(empty)" — seven characters, on which no width arm can fail.

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
	## ⛔ READ THROUGH `get_script_constant_map()`, NOT `settings.TEXT_SIZE_PRESETS`. A direct const
	## read on a renamed or removed constant is a RUNTIME ERROR mid-arm, and GUT scores an aborted
	## body as a PASS — so this pin would go GREEN in precisely the case it exists for. The map form
	## yields [] and reds by name. And if the map form were wrong the other way round it would red
	## on a CLEAN tree, which is the safe direction for an instrument change.
	var settings: Script = load("res://src/ui/SettingsMenu.gd")
	var shipped: Array = settings.get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_eq(TEXT_SCALES, shipped,
		"this file sweeps %s but SettingsMenu offers %s" % [str(TEXT_SCALES), str(shipped)])


## The catalog's longest name per slot, as a FIXTURE CHOICE ONLY. `length()` is a proxy for width,
## not width — the bound this lane published from it was wrong twice — so this picks something
## plausibly wide to build with, and arm 5 measures every item by `get_string_size` instead of
## trusting it.
func _longest_id(catalog: Dictionary) -> String:
	var best := ""
	var best_len := -1
	for item_id in catalog:
		var nm := str((catalog[item_id] as Dictionary).get("name", item_id))
		if nm.length() > best_len:
			best_len = nm.length()
			best = str(item_id)
	return best


## The menu at a preset, on a chosen slot, in a chosen MODE, with the slots actually filled.
func _menu_for(scale: float, slot: int, item_select: bool) -> Control:
	if GameState:
		GameState.text_size_scale = scale
	var pc = CombatantScript.new()
	pc.combatant_name = "Bram"
	pc.equipped_weapon = _longest_id(EquipmentSystem.weapons)
	pc.equipped_armor = _longest_id(EquipmentSystem.armors)
	pc.equipped_accessory = _longest_id(EquipmentSystem.accessories)
	add_child_autofree(pc)
	var m = EquipmentMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	## `setup` defers the build, so the mode and slot assigned after it are what the deferred build
	## reads — there is no second build to await. Passing no pools makes `setup` fall back to the
	## whole catalog, which is what the screen does in play.
	m.setup(pc)
	m.selected_slot = slot
	if item_select:
		m.mode = EquipmentMenuScript.Mode.ITEM_SELECT
	await get_tree().process_frame
	await get_tree().process_frame
	return m


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


## ARM 4 — THE WIDTH, in BOTH modes. Reads `size.x` for the same reason arms 2 and 3 read `size.y`:
## an unclipped Label's box is clamped up to its content, so the box IS the drawn text. A clipped
## one (the description) reports its box, which is also what it draws. One reading covers both.
func test_no_row_label_draws_past_its_row_width() -> void:
	var over: Array[String] = []
	var measured := 0
	var cells_with_rows := 0
	for scale in TEXT_SCALES:
		for slot in 3:
			for item_select in [false, true]:
				var m = await _menu_for(scale, slot, item_select)
				var rows: Array = m._item_labels if item_select else m._slot_labels
				if not rows.is_empty():
					cells_with_rows += 1
				for i in range(rows.size()):
					var row: Control = rows[i]
					for child in row.get_children():
						var l := child as Label
						if l == null or str(l.text).strip_edges() == "":
							continue
						measured += 1
						if l.position.x + l.size.x > row.size.x + 1.0:
							over.append("%.2fx %s slot %d row %d: '%s' ends %.0f in a %.0f-wide row"
								% [scale, "list" if item_select else "slots", slot, i,
								   str(l.text).substr(0, 18), l.position.x + l.size.x, row.size.x])
	## A DERIVED denominator, not a bound. Every preset x slot x mode cell must have built rows, or
	## a mode that silently builds nothing makes this arm pass on a sweep it never ran.
	assert_eq(cells_with_rows, TEXT_SCALES.size() * 3 * 2,
		"CONTROL: %d of %d (preset x slot x mode) cells built any rows"
		% [cells_with_rows, TEXT_SCALES.size() * 3 * 2])
	assert_gt(measured, 0, "CONTROL: at least one row label must have been measured")
	assert_eq(over, [] as Array[String],
		"an equipment row label draws past its own row: %s" % [", ".join(over)])


## ARM 5 — EXHAUSTIVE OVER THE CATALOG, because arm 4 can only see the rows that happen to be on
## screen: the item list scrolls, `max_visible` is derived from the panel height, and the sweep
## above never moves `selected_item_index`. So arm 4 measures the first windowful and the other
## items are measured by nothing.
##
## This measures EVERY item's name at EVERY preset against the width the row actually leaves it,
## with the font and size READ OFF A BUILT ROW rather than assumed, and the denominator DERIVED
## from the catalog sizes — so it cannot claim to be exhaustive while skipping most of the corpus.
func test_every_equipment_name_fits_its_row_at_every_text_size() -> void:
	var catalogs: Array = [
		EquipmentSystem.weapons, EquipmentSystem.armors, EquipmentSystem.accessories]
	var corpus := 0
	for c in catalogs:
		corpus += (c as Dictionary).size()
	var expect := corpus * TEXT_SCALES.size()
	assert_gt(corpus, 0, "PRECONDITION: EquipmentSystem must have loaded a catalog to sweep")

	var over: Array[String] = []
	var skipped: Array[String] = []
	var measured := 0
	for scale in TEXT_SCALES:
		for slot in 3:
			var m = await _menu_for(scale, slot, true)
			var rows: Array = m._item_labels
			if rows.is_empty():
				skipped.append("%.2fx slot %d: the item list built no rows" % [scale, slot])
				continue
			var row: Control = rows[0]
			var probe := row.get_node_or_null("Name") as Label
			if probe == null:
				skipped.append("%.2fx slot %d: row 0 carries no Name label" % [scale, slot])
				continue
			var f: Font = probe.get_theme_font("font")
			var fs: int = probe.get_theme_font_size("font_size")
			if f == null or fs <= 0:
				skipped.append("%.2fx slot %d: Name label has no font to measure with (size %d)"
					% [scale, slot, fs])
				continue
			var room: float = row.size.x - probe.position.x
			for item_id in (catalogs[slot] as Dictionary):
				var nm := str(((catalogs[slot] as Dictionary)[item_id] as Dictionary).get("name", item_id))
				measured += 1
				## ⚠ WIDTH -1, NEVER the box width. A width-limited query wraps the string to the
				## box and hands back the box, so the instrument agrees with the bug and the
				## overflow arm goes green.
				var w: float = f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				if w > room + 1.0:
					over.append("%.2fx %s '%s' needs %.0f px with %.0f to the row edge"
						% [scale, str(EquipmentMenuScript.SLOTS[slot]), nm, w, room])
	## EVERY skip collected and asserted empty: four silent `continue`s with a loose lower bound is
	## how an arm claims "every item, every preset" while covering a fraction of it.
	assert_eq(skipped, [] as Array[String],
		"cells skipped instead of measured: %s" % [", ".join(skipped)])
	assert_eq(measured, expect,
		"EXHAUSTIVE: measured %d of %d (catalog %d x presets %d) cells"
		% [measured, expect, corpus, TEXT_SCALES.size()])
	assert_eq(over, [] as Array[String],
		"an equipment name does not fit its row: %s" % [", ".join(over)])
