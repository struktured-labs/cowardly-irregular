extends GutTest

## The Items menu's rows are as wide as the list (panel minus 8) with the count on the right edge, but each row took the
## mouse through a Button sized 220 x 32 from literals: a click on the name's tail or on the count did nothing. Same
## shape as Settings (test_a_settings_row_answers_a_click_anywhere_on_it). Target rows are 280 x 48 and match already.

const ITEMS := "res://src/ui/ItemsMenu.gd"
const _STOCK := ["potion", "hi_potion", "ether", "antidote", "phoenix_down", "elixir"]


func _menu() -> Node:
	var stock: Dictionary = {}
	for id in _STOCK:
		stock[id] = 2
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var menu: Control = load(ITEMS).new()
	menu.setup([], stock)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	return menu


func test_the_floor_names_what_this_file_drives() -> void:
	var props: Array = (load(ITEMS) as GDScript).get_script_property_list().map(func(p): return str(p["name"]))
	assert_has(props, "_item_labels", "ItemsMenu._item_labels must exist")
	assert_has(props, "selected_item_index", "ItemsMenu.selected_item_index must exist")


func test_every_item_rows_click_target_is_its_whole_row() -> void:
	var menu: Node = await _menu()
	var rows: Array = menu._item_labels.filter(func(r): return is_instance_valid(r))
	assert_gt(rows.size(), 2, "CONTROL: the stocked list drew item rows (%d)" % rows.size())
	var bad: Array = []
	var wide := 0
	for r in rows:
		var row := r as Control
		if row.size.x > 220.5:
			wide += 1
		var hits: Array = row.get_children().filter(func(c): return c is Button)
		assert_eq(hits.size(), 1, "PRECONDITION: one click target per row")
		if hits.is_empty():
			continue
		var b := hits[0] as Button
		if not Rect2(b.position, b.size).is_equal_approx(Rect2(Vector2.ZERO, row.size)):
			bad.append("click target %s, row %s" % [Rect2(b.position, b.size), row.size])
	assert_gt(wide, 0, "CONTROL: item rows are wider than the literal 220 px, so a 220 px target can be told apart")
	assert_eq(bad, [], "every item row answers a click anywhere on it:\n%s" % "\n".join(PackedStringArray(bad)))


## Behaviour through the real input path: the mouse on a row's COUNT (its right edge) selects that row.
func test_the_mouse_on_an_items_count_selects_it() -> void:
	var menu: Node = await _menu()
	var vp: SubViewport = menu.get_parent()
	var rows: Array = menu._item_labels.filter(func(r): return is_instance_valid(r))
	assert_gt(rows.size(), 2, "PRECONDITION: rows to point at")
	if rows.size() < 3:
		return
	var target := 2
	var qty := (rows[target] as Control).get_node_or_null("Quantity") as Control
	assert_not_null(qty, "PRECONDITION: the row shows its count")
	if qty == null:
		return
	var p: Vector2 = qty.get_global_rect().get_center()
	assert_gt(p.x - (rows[target] as Control).get_global_rect().position.x, 220.0, "CONTROL: the count sits past the old 220 px target")
	assert_ne(menu.selected_item_index, menu._item_scroll + target, "CONTROL: the row is not already selected")
	for q in [p + Vector2(-6, -2), p]:
		var ev := InputEventMouseMotion.new()
		ev.position = q
		ev.global_position = q
		vp.push_input(ev)
		await get_tree().process_frame
	assert_eq(menu.selected_item_index, menu._item_scroll + target, "the mouse on row %d's count selects it" % target)
