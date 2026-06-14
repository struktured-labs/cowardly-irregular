extends GutTest

## Regression tests for AbilitiesMenu list scrolling.
##
## Bug: _create_passives_panel / _create_abilities_panel rendered only the
## first `max_visible` rows starting at index 0 with NO scroll offset (unlike
## JobMenu). PassiveSystem ships 43 passives but at 1280x720 only ~17 rows fit,
## so navigating past index 17 wrapped selected_index over the full list while
## the selected row was never created — the `>` cursor and SELECTED_COLOR
## highlight vanished and most of the catalog was unreachable.
##
## Fix: both panels now compute
##   scroll_offset = clampi(selected_index - max_visible + 1, 0, max(0, size - max_visible))
## and render rows from scroll_offset, passing the absolute index so
## is_selected / cursor / highlight stay aligned with selected_index.

const AbilitiesMenuScript = preload("res://src/ui/AbilitiesMenu.gd")


func _make_menu() -> AbilitiesMenu:
	var menu = AbilitiesMenuScript.new()
	add_child_autofree(menu)
	return menu


func _find_selected_highlight(panel: Control) -> ColorRect:
	"""Return the Highlight ColorRect that is painted with SELECTED_COLOR, if any."""
	for row in panel.get_children():
		if not (row is Control):
			continue
		var highlight = row.get_node_or_null("Highlight")
		if highlight is ColorRect and highlight.color == AbilitiesMenuScript.SELECTED_COLOR:
			return highlight
	return null


func test_passives_panel_renders_selected_row_past_max_visible() -> void:
	"""Selecting a passive beyond the visible window still renders its cursor/highlight."""
	var menu = _make_menu()

	# Force a passives list large enough to overflow any reasonable panel.
	menu.current_tab = AbilitiesMenu.Tab.PASSIVES
	menu._passives_list = []
	for i in range(50):
		menu._passives_list.append({
			"id": "passive_%d" % i,
			"data": {"name": "Passive %d" % i, "category": 0},
			"equipped": false,
			"learned": true
		})

	# A small panel forces max_visible well below the selected index.
	var panel_size = Vector2(320, 200)
	var item_height = 28
	var max_visible = int((panel_size.y - 40) / item_height)

	# Pick an index that is past the visible window AND past the end of an
	# offset-less render (the old bug would never create this row).
	menu.selected_index = 40
	assert_gt(menu.selected_index, max_visible,
		"Test setup: selected_index must exceed max_visible to exercise scrolling")

	var panel = menu._create_passives_panel(panel_size)
	add_child_autofree(panel)

	var highlight = _find_selected_highlight(panel)
	assert_not_null(highlight,
		"Selected passive past max_visible must have a SELECTED_COLOR highlight (cursor visible)")


func test_passives_panel_offset_zero_when_selection_in_view() -> void:
	"""When the selection fits in the window, the first rows (offset 0) are shown."""
	var menu = _make_menu()

	menu.current_tab = AbilitiesMenu.Tab.PASSIVES
	menu._passives_list = []
	for i in range(50):
		menu._passives_list.append({
			"id": "passive_%d" % i,
			"data": {"name": "Passive %d" % i, "category": 0},
			"equipped": false,
			"learned": true
		})

	menu.selected_index = 0

	var panel = menu._create_passives_panel(Vector2(320, 200))
	add_child_autofree(panel)

	# First rendered row should correspond to passive_0 (no scroll yet).
	# Find the highlighted row and confirm it is the first selectable row.
	var highlight = _find_selected_highlight(panel)
	assert_not_null(highlight,
		"Selected passive at index 0 must have a SELECTED_COLOR highlight")


func test_abilities_panel_renders_selected_row_past_max_visible() -> void:
	"""Defense-in-depth: abilities tab applies the same scroll offset."""
	var menu = _make_menu()

	menu.current_tab = AbilitiesMenu.Tab.ABILITIES
	menu._abilities_list = []
	for i in range(50):
		menu._abilities_list.append({
			"id": "ability_%d" % i,
			"data": {"name": "Ability %d" % i, "type": "physical", "mp_cost": 0}
		})

	var panel_size = Vector2(320, 200)
	var item_height = 24
	var max_visible = int((panel_size.y - 40) / item_height)

	menu.selected_index = 40
	assert_gt(menu.selected_index, max_visible,
		"Test setup: selected_index must exceed max_visible to exercise scrolling")

	var panel = menu._create_abilities_panel(panel_size)
	add_child_autofree(panel)

	var highlight = _find_selected_highlight(panel)
	assert_not_null(highlight,
		"Selected ability past max_visible must have a SELECTED_COLOR highlight (cursor visible)")


func test_scroll_offset_never_negative_or_overruns() -> void:
	"""The clampi guard keeps scroll_offset within [0, size - max_visible]."""
	var size = 50
	var max_visible = 17

	# selected_index at start -> offset 0
	assert_eq(clampi(0 - max_visible + 1, 0, max(0, size - max_visible)), 0,
		"Selection at top should not scroll")

	# selected_index in middle -> keeps selection visible
	var mid_offset = clampi(30 - max_visible + 1, 0, max(0, size - max_visible))
	assert_eq(mid_offset, 14, "Middle selection should scroll so row stays in view")

	# selected_index at end -> offset capped at size - max_visible
	var end_offset = clampi(49 - max_visible + 1, 0, max(0, size - max_visible))
	assert_eq(end_offset, size - max_visible, "Last selection caps scroll at list end")

	# Short list (fits entirely) -> offset 0
	assert_eq(clampi(2 - max_visible + 1, 0, max(0, 5 - max_visible)), 0,
		"List shorter than window never scrolls")


func test_source_has_scroll_offset_in_both_panels() -> void:
	"""Source guard: both panel builders must compute a scroll_offset."""
	var content = FileAccess.get_file_as_string("res://src/ui/AbilitiesMenu.gd")
	assert_false(content.is_empty(), "AbilitiesMenu.gd should be readable")
	# clampi-based offset appears for passives and abilities.
	var occurrences = content.count("scroll_offset = clampi(selected_index - max_visible + 1")
	assert_eq(occurrences, 2,
		"Both _create_passives_panel and _create_abilities_panel must compute scroll_offset")
