extends GutTest

## The equipment choice rows drew their description with NO width and NO wrap, so it rendered at
## CONTENT width: `returned_sword` ends at 897px inside an 800px row, and nothing in EquipmentMenu
## sets `clip_contents`, so it painted over the panel border and off the right of a 1280 screen.
## It is the 1 of 21 weapons over 100 chars; the next is 82.
##
## Same corpus as the PartyStatusScreen fix, whose weapon description overprinted the "Armor"
## label. This is the other menu that reads it.
##
## ⚠️ WHY `clip_text` IS THE LOAD-BEARING PROPERTY, not the overrun behaviour. A Label's assigned
## width is clamped up to its minimum size as it stands in that frame, and that minimum is the
## content width at the DEFAULT font (1499px for this text at 16, against 843 at the overridden 9);
## `size` then keeps the clamped value after the minimum settles. `clip_text` is what takes the
## text out of the minimum size at all. The arms below pin both, because the overrun alone looks
## correct and holds nothing.
##
## ⚠️ THE INSTRUMENT MUST RESPECT WHAT BOUNDS THE LABEL or it reports the fix instead of measuring
## it: `size.x` is the bound only when trimming is on, and the font's content width otherwise.
##
## ⚠️ EVERY ARM PAGES THE WHOLE CATALOG. `_item_labels` holds only the rows inside the scroll
## WINDOW, so a sweep at index 0 measures the first screenful and stops — the first version of this
## file did that and its own control caught it: worst description in view 35 chars, while the
## offending item sits at index 20.

const MenuScript = preload("res://src/ui/EquipmentMenu.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")

var _menu: Control = null
var _pc = null


func before_each() -> void:
	_pc = CombatantScript.new()
	_pc.combatant_name = "Bram"
	add_child_autofree(_pc)
	var js = get_tree().root.get_node_or_null("JobSystem")
	if js != null and js.has_method("assign_job"):
		js.call("assign_job", _pc, "fighter")
	_menu = MenuScript.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(_menu)
	_menu.setup(_pc)


## Awaits a frame: the label's rect comes from ANCHORS against a row the caller sizes after the row
## is built, so it is only correct once layout has run.
func _show(slot: int, pick: int) -> void:
	_menu.mode = MenuScript.Mode.ITEM_SELECT
	_menu.selected_slot = slot
	_menu.selected_item_index = pick
	_menu._build_ui()
	await get_tree().process_frame
	await get_tree().process_frame


func _count(slot: int) -> int:
	match slot:
		0: return (_menu.available_weapons as Array).size()
		1: return (_menu.available_armors as Array).size()
		2: return (_menu.available_accessories as Array).size()
	return 0


func _rows() -> Array:
	var out: Array = []
	for n in _menu._item_labels:
		if is_instance_valid(n) and n is Control:
			out.append(n)
	return out


func _labels_of(row: Control) -> Array:
	var out: Array = []
	for c in row.get_children():
		if c is Label:
			out.append(c)
	return out


## What the label puts on screen.
func _drawn_width(l: Label) -> float:
	if l.clip_text or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
		return l.size.x
	var font: Font = l.get_theme_font("font")
	if font == null:
		return 0.0
	var fsz: int = l.get_theme_font_size("font_size")
	if fsz <= 0:
		fsz = 9
	return font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x


func test_control_the_menu_builds_rows_and_has_a_catalog_to_page() -> void:
	for slot in 3:
		await _show(slot, 0)
		assert_gt(_rows().size(), 0, "slot %d must build at least one item row" % [slot])
		assert_gt(_count(slot), 0, "slot %d must have a catalog" % [slot])


func test_control_a_description_in_the_catalog_would_overflow_unbounded() -> void:
	## ⚠️ READS THE CATALOG, NOT THE LABEL. Measuring the label here would measure the BOUNDED
	## width and report a fit the fix satisfies by construction. The raw description is the only
	## honest fixture.
	await _show(0, 0)
	var rows: Array = _rows()
	assert_gt(rows.size(), 0, "PRECONDITION: weapons must build rows")
	if rows.is_empty():
		return
	var row: Control = rows[0]
	var font: Font = row.get_theme_font("font")
	assert_not_null(font, "CONTROL: a theme font is needed to measure")
	if font == null:
		return
	var avail: float = row.size.x - 54.0 - 8.0
	var worst := 0.0
	var worst_len := 0
	for id in (_menu.available_weapons as Array):
		var raw: String = str(EquipmentSystem.get_weapon(id).get("description", ""))
		var w: float = font.get_string_size(raw, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		if w > worst:
			worst = w
			worst_len = raw.length()
	assert_gt(worst, avail,
		"the weapon catalog must hold a description wider than the panel leaves (%.0f px of %.0f, %d chars) — else this file guards nothing" % [
			worst, avail, worst_len])


func test_no_row_label_draws_past_the_row_it_sits_in() -> void:
	## THE DEFECT, derived over all three slots and every item in each.
	for slot in 3:
		for i in _count(slot):
			await _show(slot, i)
			for row in _rows():
				for l in _labels_of(row):
					var ends: float = l.position.x + _drawn_width(l)
					assert_lte(ends, row.size.x,
						"slot %d item %d: '%s' ends at %.0f of a %.0f-wide row (%s)" % [
							slot, i, l.name, ends, row.size.x, l.text.substr(0, 36)])


func test_the_description_clips_rather_than_expanding_to_its_text() -> void:
	## The mechanism. `clip_text` is what removes the text from the Label's minimum size; the
	## overrun behaviour only decides what the truncation LOOKS like. Reds if either is dropped —
	## and dropping clip_text alone leaves a label that looks configured and holds no width.
	var checked := 0
	for i in _count(0):
		await _show(0, i)
		for row in _rows():
			var d := row.get_node_or_null("Description") as Label
			if d == null or d.text == "":
				continue
			checked += 1
			assert_true(d.clip_text,
				"the description must clip, or its width is undone by its own minimum size")
			assert_ne(d.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING,
				"and must mark the truncation, so a cut line does not read as a complete one")
			## BOTH bounds. An upper bound alone accepts a box of width ZERO, which shows the player
			## no description at all and is not better than one that overflows — measured: dropping
			## `anchor_right` collapses the width to nothing and red 0 arms until this line existed.
			assert_almost_eq(d.size.x, row.size.x - 54.0 - 8.0, 1.0,
				"the box must span the row it was given (%.0f of an intended %.0f) — too narrow hides the text, too wide spills it" % [
					d.size.x, row.size.x - 54.0 - 8.0])
	assert_gt(checked, 0, "PRECONDITION: at least one row must carry a description")


func test_the_whole_description_is_still_in_the_label() -> void:
	## Clipping must not EDIT the text. The row shows as much as fits, but `text` keeps the full
	## string — which is what any later consumer (a tooltip, a reader, a wider panel) needs, and
	## what an approach that trimmed the string itself would have thrown away.
	var checked := 0
	for i in _count(0):
		await _show(0, i)
		var ids: Array = _menu.available_weapons as Array
		for row in _rows():
			var d := row.get_node_or_null("Description") as Label
			if d == null or d.text == "":
				continue
			var match_found := false
			for id in ids:
				if str(EquipmentSystem.get_weapon(id).get("description", "")) == d.text:
					match_found = true
					break
			checked += 1
			assert_true(match_found,
				"the label text must be a catalog description verbatim, got '%s'" % [d.text.substr(0, 48)])
	assert_gt(checked, 0, "PRECONDITION: at least one row must carry a description")
