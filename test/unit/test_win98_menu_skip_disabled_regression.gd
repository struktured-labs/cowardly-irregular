extends GutTest

## Regression test: Win98Menu navigation must skip disabled rows.
##
## Bug: Up/Down navigation in Win98Menu stepped selected_index by +/-1 with
## wrap but never skipped items flagged {"disabled": true}. In ShopScene's
## magic character-select the list mixes selectable members with disabled
## "(Already known)" / "(No one can learn this!)" rows, so the cursor could
## rest on a disabled row where A does nothing — reading as a stuck cursor.
## Fix mirrors TitleScreen._move_selection: _step_selection() skips disabled
## rows (wrapping), and setup() no longer opens on a leading disabled row.
##
## See src/ui/Win98Menu.gd:_step_selection, setup().

const Win98MenuScript = preload("res://src/ui/Win98Menu.gd")


func _make_menu(items: Array) -> Win98Menu:
	var menu = Win98MenuScript.new()
	add_child_autofree(menu)
	# Drive setup directly; we only inspect selected_index / menu_items, no input.
	menu.setup("Test", items, Vector2.ZERO, "fighter")
	return menu


## _step_selection(+1) must skip a disabled row in the middle of the list.
func test_step_down_skips_disabled_middle_row() -> void:
	var menu := _make_menu([
		{"id": "a", "label": "A"},
		{"id": "b", "label": "B (disabled)", "disabled": true},
		{"id": "c", "label": "C"},
	])
	# setup() lands on first enabled row (index 0).
	assert_eq(menu.selected_index, 0, "Should start on first enabled row")

	menu._step_selection(1)
	assert_eq(menu.selected_index, 2, "Down should skip disabled index 1 -> land on 2")


## _step_selection(-1) must skip a disabled row.
func test_step_up_skips_disabled_row() -> void:
	var menu := _make_menu([
		{"id": "a", "label": "A"},
		{"id": "b", "label": "B (disabled)", "disabled": true},
		{"id": "c", "label": "C"},
	])
	menu.selected_index = 2

	menu._step_selection(-1)
	assert_eq(menu.selected_index, 0, "Up should skip disabled index 1 -> land on 0")


## Navigation must wrap around past trailing disabled rows.
func test_step_down_wraps_past_trailing_disabled() -> void:
	var menu := _make_menu([
		{"id": "a", "label": "A"},
		{"id": "b", "label": "B (disabled)", "disabled": true},
		{"id": "c", "label": "C (disabled)", "disabled": true},
	])
	# Only index 0 is selectable; stepping down should wrap back to 0.
	menu.selected_index = 0

	menu._step_selection(1)
	assert_eq(menu.selected_index, 0, "Down with trailing disabled should wrap to only enabled row 0")


## All-disabled list must not infinite-loop and must leave selection unchanged.
func test_step_all_disabled_leaves_selection_unchanged() -> void:
	var menu := _make_menu([
		{"id": "a", "label": "(No one can learn this!)", "disabled": true},
		{"id": "b", "label": "(disabled)", "disabled": true},
	])
	var before := menu.selected_index

	menu._step_selection(1)
	assert_eq(menu.selected_index, before, "All-disabled list: down leaves selection unchanged")

	menu._step_selection(-1)
	assert_eq(menu.selected_index, before, "All-disabled list: up leaves selection unchanged")


## Empty list must be a no-op (no crash, no out-of-range).
func test_step_empty_list_is_noop() -> void:
	var menu = Win98MenuScript.new()
	add_child_autofree(menu)
	menu.menu_items = []
	menu.selected_index = 0

	menu._step_selection(1)
	assert_eq(menu.selected_index, 0, "Empty list: step should not change selection")


## setup() must not open with the cursor on a leading disabled row.
func test_setup_skips_leading_disabled_row() -> void:
	var menu := _make_menu([
		{"id": "hdr", "label": "(Already known)", "disabled": true},
		{"id": "m", "label": "Mage - Learn", "disabled": false},
	])
	assert_eq(menu.selected_index, 1, "setup() should skip leading disabled row -> start on index 1")


## setup() with an all-disabled list falls back to index 0 (no crash).
##
## We drive setup() on a NOT-in-tree menu and read selected_index immediately,
## isolating the bounded fall-back scan in setup() (src/ui/Win98Menu.gd ~L431):
##   selected_index = 0
##   for i in range(size): if not disabled: selected_index = i; break
## With every row disabled the break never fires, so the index stays 0.
## (Adding the menu to the tree first would run the async _build_menu()
## frame-advance machinery, which is unrelated to the fall-back contract.)
func test_setup_all_disabled_falls_back_to_zero() -> void:
	var menu = Win98MenuScript.new()
	autofree(menu)  # not added to the tree: setup() skips _build_menu()
	# Seed a non-zero index to prove setup() actively resets it to 0.
	menu.selected_index = 1
	menu.setup("Test", [
		{"id": "a", "label": "(No items)", "disabled": true},
		{"id": "b", "label": "(No items)", "disabled": true},
	], Vector2.ZERO, "fighter")
	assert_false(menu.is_inside_tree(), "Sanity: menu not in tree, so no _build_menu() side-effects")
	assert_eq(menu.selected_index, 0, "All-disabled setup() should fall back to index 0")
