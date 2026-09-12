extends GutTest

## The condition picker enumerates CONDITION_TYPES.keys(), and that dictionary has grown by four
## this session alone. Its panel is height-capped — `min(80 + n * 24, screen - 80)` — so past some
## count the rows stop fitting, and whether the entries beyond that point are REACHABLE depends
## entirely on the scroll window inside it.
##
## It scrolls correctly today: max_visible is derived from the capped height and scroll_start is
## centred on the selection. This is a null result made standing, because the hazard is one I am
## actively growing — every condition I add moves the catalog closer to the cap, and a clipped
## picker fails SILENTLY: the condition exists, validates, evaluates, and simply cannot be chosen.
##
## Checked at the project's real viewport (1280x720, project.godot), not an arbitrary size.

const GE := preload("res://src/ui/autobattle/AutobattleGridEditor.gd")
const VIEWPORT := Vector2(1280, 720)


func _editor() -> Node:
	var ge = GE.new()
	ge.size = VIEWPORT
	add_child_autofree(ge)
	return ge


## Every Label the picker actually rendered.
func _rendered_rows(ge) -> Array:
	var out: Array = []
	if ge._option_picker == null or not is_instance_valid(ge._option_picker):
		return out
	for child in ge._option_picker.get_children():
		if child is Label:
			out.append(str((child as Label).text))
	return out


func test_the_last_condition_in_the_catalog_can_be_selected() -> void:
	## The real path, and the realistic worst case: `always` is the LAST key in CONDITION_TYPES and
	## also the most common condition a player has selected when they open this picker, so the
	## normal case is the one that sits at the far end of the list.
	var keys: Array = AutobattleSystem.CONDITION_TYPES.keys()
	assert_gt(keys.size(), 20, "CONTROL: the catalog really is large enough to matter (%d)" % keys.size())
	var last_key: String = str(keys[keys.size() - 1])
	var last_label: String = str(AutobattleSystem.CONDITION_TYPES[last_key])

	var ge = _editor()
	ge.rules = [{"conditions": [{"type": last_key}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]
	ge.cursor_row = 0
	ge.cursor_col = 0
	ge._open_condition_editor()
	var rows: Array = _rendered_rows(ge)
	assert_gt(rows.size(), 1, "CONTROL: the picker rendered rows at all (%d)" % rows.size())
	var found: bool = false
	for r in rows:
		if str(r).contains(last_label):
			found = true
	assert_true(found,
		"the last condition in the catalog ('%s') was not rendered — it exists, validates and " % last_label
		+ "evaluates, and cannot be chosen. Rows shown: %s" % str(rows))


func test_the_first_condition_is_reachable_too() -> void:
	## The other end, because a scroll window centred on the selection can clip either side.
	var keys: Array = AutobattleSystem.CONDITION_TYPES.keys()
	var first_key: String = str(keys[0])
	var first_label: String = str(AutobattleSystem.CONDITION_TYPES[first_key])
	var ge = _editor()
	ge.rules = [{"conditions": [{"type": first_key}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]
	ge.cursor_row = 0
	ge.cursor_col = 0
	ge._open_condition_editor()
	var found: bool = false
	for r in _rendered_rows(ge):
		if str(r).contains(first_label):
			found = true
	assert_true(found, "the first condition ('%s') must be rendered when it is selected" % first_label)


func test_it_still_scrolls_when_the_catalog_outgrows_the_panel() -> void:
	## The future case, forced. Today 23-24 entries happen to FIT at 720p, so the arms above would
	## pass even if the scroll window were broken — they prove reachability, not scrolling. Hand it
	## a list that cannot fit and require the selected row to be rendered anyway.
	var ge = _editor()
	var many: Array = []
	for i in range(60):
		many.append({"id": "synthetic_%d" % i, "label": "Synthetic Option %d" % i})
	ge._open_option_picker({
		"title": "Overflow", "kind": "condition_type", "options": many, "selected": 57,
	})
	var rows: Array = _rendered_rows(ge)
	assert_gt(rows.size(), 5, "CONTROL: rows were rendered (%d)" % rows.size())
	assert_lt(rows.size(), many.size(),
		"CONTROL: 60 options must NOT all fit at this viewport, or this arm proves nothing about "
		+ "scrolling (rendered %d of %d)" % [rows.size(), many.size()])
	var found: bool = false
	for r in rows:
		if str(r).contains("Synthetic Option 57"):
			found = true
	assert_true(found,
		"a selection near the END of an over-long list must still be rendered — otherwise every "
		+ "condition past the panel height becomes unpickable as the catalog grows")
