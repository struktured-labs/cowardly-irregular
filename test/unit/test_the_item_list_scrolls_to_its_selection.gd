extends GutTest

## ⛔ THE ITEMS MENU NEVER SCROLLED. It rendered `range(0, max_visible)` from index 0 and
## highlighted `i == selected_item_index`, so the moment the selection passed the first screenful
## NO rendered row matched it: the cursor vanished and the player was confirming an item they could
## not see. 172 items ship in the game.
##
## 🔑 EVERY OTHER WINDOWED MENU ALREADY HAD AN OFFSET — JobMenu, AbilitiesMenu (x2) and
## EquipmentMenu all route through MenuScroll, whose own docstring says it replaced "the four
## sites". ItemsMenu was a fifth that nobody converted, and it is the longest list of the set.
##
## ⚠️ AND PAGING MADE IT REACHABLE IN TWO BUTTON PRESSES. A trigger pull moves ten rows, so a
## player leaves the visible window almost immediately — the fast routes added to this menu were
## landing the cursor in a region the menu could not draw.
##
## The invariant is not a coordinate: THE SELECTION MUST LIE INSIDE THE RENDERED WINDOW. Asserting
## a particular offset would pin a coincidental value and red on a correct resize.

const ItemsMenuScript := preload("res://src/ui/ItemsMenu.gd")


func _menu_with(count: int, selected: int) -> Node:
	var m: Node = ItemsMenuScript.new()
	add_child_autofree(m)
	var list: Array = []
	for i in range(count):
		list.append({"data": {"name": "Item %d" % i}, "quantity": 1, "id": "i%d" % i})
	m.set("_item_list", list)
	m.set("selected_item_index", selected)
	m.set("mode", 0)
	m.visible = true
	m._build_ui()
	return m

## ⛔ READ THE RENDERED ROWS, NOT THE OFFSET VARIABLE. My first version asserted
## `_item_scroll <= selected < _item_scroll + _item_labels.size()` and it PASSED with the original
## bug restored: the offset was still computed correctly while the loop drew rows 0..24 from it.
## The variable and the render agreed by coincidence, which is the whole failure mode. These read
## each row's own Name label, so an arm can only pass if the player could actually see the item.
func _rendered_names(m: Node) -> Array:
	var out: Array = []
	for row in m.get("_item_labels"):
		var n = row.get_node_or_null("Name")
		if n != null:
			out.append(str(n.text))
	return out


## CONTROL: the fixture must actually produce rendered rows, or every arm below passes over nothing.
func test_the_menu_renders_rows() -> void:
	var m := _menu_with(100, 0)
	assert_gt(int(m.get("_item_labels").size()), 0,
		"no rows rendered — the fixture never reached the list branch and the arms below are vacuous")


func test_a_selection_past_the_first_screenful_is_inside_the_window() -> void:
	var m := _menu_with(100, 90)
	var names := _rendered_names(m)
	assert_gt(names.size(), 0, "CONTROL: rows must be rendered")
	assert_true(names.has("Item 90"),
		"the SELECTED item is not among the drawn rows — the cursor is invisible and the player is "
		+ "confirming an item they cannot see. Drawn: %s … %s" % [names[0], names[names.size() - 1]])


func test_the_last_item_is_reachable_on_screen() -> void:
	var m := _menu_with(172, 171)
	var names := _rendered_names(m)
	assert_true(names.has("Item 171"),
		"the LAST of 172 items is not drawn. Drawn: %s … %s" % [names[0], names[names.size() - 1]])


## A short list must not scroll at all — the window only moves when the selection would leave it.
func test_a_short_list_does_not_scroll() -> void:
	var m := _menu_with(3, 2)
	assert_eq(_rendered_names(m)[0], "Item 0",
		"a list that fits on screen must still start at row 0")


## The highlight is driven by _update_selection, which compares the LABEL index. With a window that
## index is relative, so the absolute row has to be reconstructed — get this wrong and the wrong
## row lights up, which is worse than no highlight at all.
func test_the_highlighted_row_is_the_selected_one() -> void:
	var m := _menu_with(100, 90)
	m._update_selection()
	var off: int = int(m.get("_item_scroll"))
	var labels: Array = m.get("_item_labels")
	var lit: Array = []
	for i in range(labels.size()):
		var cur = labels[i].get_node_or_null("Cursor")
		if cur != null and str(cur.text).strip_edges() == ">":
			lit.append(off + i)
	assert_eq(lit, [90],
		"exactly the selected absolute row must carry the cursor; lit rows were %s" % [lit])


## ⛔ RATCHET, so a sixth menu cannot join the unwindowed set. Every src/ui file that computes a
## max_visible window must render from an OFFSET — the defect was a render starting at 0.
func test_no_windowed_menu_renders_from_zero() -> void:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	var offenders: Array = []
	var scanned := 0
	var dir := DirAccess.open("res://src/ui")
	assert_ne(dir, null, "CONTROL: src/ui must be readable")
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".gd"):
			var path := "res://src/ui/".path_join(name)
			var code: String = GdSource.code_of(path)
			if code.contains("max_visible"):
				scanned += 1
				# A windowed render must name an offset in the same file.
				if not (code.contains("MenuScroll.window_offset(") or code.contains("scroll_offset")
						or code.contains("_scroll")):
					offenders.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	assert_gt(scanned, 2, "CONTROL: the scan must find the windowed menus, or this arm is vacuous")
	assert_true(offenders.is_empty(),
		"these compute a max_visible window and never offset the render — the selection leaves the "
		+ "drawn rows and the cursor disappears: %s" % [offenders])
