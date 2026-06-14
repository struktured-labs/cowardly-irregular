extends GutTest

## Regression tests for EquipmentMenu item-select scroll window
##
## Bug: _create_items_panel rendered `for i in range(min(items.size(), max_visible))`
## with NO scroll offset, while _handle_item_input wraps selected_item_index modulo
## the FULL items list. With >max_visible (~9 at 720p) items in a slot, selecting
## item 10+ rendered no matching row and the cursor (keyed on index == selected_item_index)
## vanished — items beyond the visible window were invisible and unequippable via
## gamepad/keyboard. This is the project's silent-failure class: no crash, content
## silently unreachable.
##
## Fix: mirror JobMenu's scroll pattern — scroll_offset = max(0, selected_item_index
## - max_visible + 1), render absolute item_idx = i + scroll_offset, pass item_idx to
## _create_item_row so the highlight/cursor resolves for scrolled-into-view selections.

const EquipmentMenuScript = preload("res://src/ui/EquipmentMenu.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")

const PANEL_SIZE := Vector2(600, 640)  # mirrors right-panel size at 1280x720


func _make_menu(item_count: int) -> EquipmentMenu:
	"""Build an EquipmentMenu with a weapon slot containing `item_count` synthetic ids."""
	var menu: EquipmentMenu = EquipmentMenuScript.new()
	add_child_autofree(menu)

	var c = CombatantScript.new()
	add_child_autofree(c)
	menu.character = c

	# Weapon slot (index 0) populated with more than max_visible entries.
	var weapons: Array = []
	for i in range(item_count):
		weapons.append("weapon_%d" % i)
	menu.available_weapons = weapons
	menu.selected_slot = 0
	menu.mode = EquipmentMenuScript.Mode.ITEM_SELECT
	return menu


func _selected_index_for_panel(panel: Control) -> int:
	"""Return the absolute item index whose rendered row shows the selection cursor,
	or -1 if no visible row is selected. Mirrors _create_item_row's cursor logic."""
	for child in panel.get_children():
		var cursor = child.get_node_or_null("Cursor")
		if cursor and cursor.text == ">":
			# Decode index from the item name label (weapon_<idx>) — robust to row order.
			for sub in child.get_children():
				if sub is Label and sub.text.begins_with("weapon_"):
					return int(sub.text.substr("weapon_".length()))
	return -1


func _visible_indices(panel: Control) -> Array:
	var indices: Array = []
	for child in panel.get_children():
		for sub in child.get_children():
			if sub is Label and sub.text.begins_with("weapon_"):
				indices.append(int(sub.text.substr("weapon_".length())))
	return indices


func test_panel_caps_rows_at_max_visible() -> void:
	"""Sanity: a large catalog still only renders max_visible rows."""
	var menu = _make_menu(20)
	menu.selected_item_index = 0
	var panel = menu._create_items_panel(PANEL_SIZE)
	add_child_autofree(panel)

	var max_visible = int((PANEL_SIZE.y - 50) / 60)
	var visible = _visible_indices(panel)
	assert_eq(visible.size(), max_visible,
		"Should render exactly max_visible rows, not all %d items" % 20)
	# With selection at 0, the window starts at the top.
	assert_eq(visible.min(), 0, "Window should start at item 0 when selection is 0")


func test_selection_past_window_stays_rendered() -> void:
	"""Core regression: a selection beyond max_visible must still render its row."""
	var menu = _make_menu(20)
	var max_visible = int((PANEL_SIZE.y - 50) / 60)

	# Selecting item index 15 (well past the ~9 visible rows) must keep it on-screen.
	menu.selected_item_index = 15
	var panel = menu._create_items_panel(PANEL_SIZE)
	add_child_autofree(panel)

	var visible = _visible_indices(panel)
	assert_true(visible.has(15),
		"Selected item 15 must be among the rendered rows (was invisible pre-fix). Visible: %s" % str(visible))
	assert_eq(_selected_index_for_panel(panel), 15,
		"The rendered cursor (>) must mark the absolute selected index 15")


func test_last_item_is_reachable() -> void:
	"""The very last catalog entry must be selectable and visible."""
	var menu = _make_menu(20)
	menu.selected_item_index = 19  # last weapon
	var panel = menu._create_items_panel(PANEL_SIZE)
	add_child_autofree(panel)

	assert_true(_visible_indices(panel).has(19),
		"Last item (19) must be rendered when selected")
	assert_eq(_selected_index_for_panel(panel), 19,
		"Cursor must mark the last item when it is selected")


func test_scroll_window_follows_selection() -> void:
	"""The visible window slides so the selection is always its last visible row."""
	var menu = _make_menu(20)
	var max_visible = int((PANEL_SIZE.y - 50) / 60)

	menu.selected_item_index = 12
	var panel = menu._create_items_panel(PANEL_SIZE)
	add_child_autofree(panel)

	var visible = _visible_indices(panel)
	var expected_offset = max(0, 12 - max_visible + 1)
	assert_eq(visible.min(), expected_offset,
		"Window should start at scroll_offset %d" % expected_offset)
	assert_eq(visible.max(), 12, "Selection (12) should be the bottom visible row")


func test_small_catalog_unaffected() -> void:
	"""A catalog that fits entirely still renders every row with no scroll."""
	var menu = _make_menu(3)
	menu.selected_item_index = 2
	var panel = menu._create_items_panel(PANEL_SIZE)
	add_child_autofree(panel)

	var visible = _visible_indices(panel)
	assert_eq(visible.size(), 3, "All 3 items should render")
	assert_eq(_selected_index_for_panel(panel), 2, "Cursor marks selected item 2")


func test_source_uses_scroll_offset() -> void:
	"""Source guard: _create_items_panel must apply a scroll offset window."""
	var content = FileAccess.get_file_as_string("res://src/ui/EquipmentMenu.gd")
	assert_false(content.is_empty(), "EquipmentMenu.gd should be readable")
	assert_true(content.contains("scroll_offset"),
		"EquipmentMenu must compute a scroll_offset so selections past max_visible stay in view")
	assert_true(content.contains("selected_item_index - max_visible + 1"),
		"scroll_offset should follow the selection like JobMenu does")
	# The render loop must pass an absolute item index, not the raw loop counter.
	assert_true(content.contains("_create_item_row(item_id, item_idx)"),
		"Row must be built with the absolute item_idx so the highlight resolves")
