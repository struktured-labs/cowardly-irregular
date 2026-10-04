extends GutTest

## The Party Chat control hint was sized while detached, so its minimum was still the 16px width (544) and it ran 44px past the 520px panel.

const MENU := preload("res://src/ui/PartyChatMenu.gd")

var _held_constants: Dictionary = {}


func before_each() -> void:
	_held_constants = GameState.game_constants.duplicate(true)


func after_each() -> void:
	GameState.game_constants = _held_constants


func _open_menu() -> Control:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var menu = MENU.new()
	layer.add_child(menu)
	if menu.has_method("open"):
		menu.open()
	await get_tree().process_frame
	await get_tree().process_frame
	return menu


## Every Label whose parent is a plain Control (not a Container that lays it out) must sit inside that parent.
func _labels_outside_their_panel(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is Label):
			continue
		var p := n.get_parent()
		if not (p is Control) or p is Container or (p as Control).size.x <= 0.0:
			continue
		var l: Label = n
		if l.position.x < 0.0 or l.position.x + l.size.x > (p as Control).size.x + 0.5:
			out.append("'%s' spans %.0f..%.0f in a %.0f-wide panel" % [l.text.left(24), l.position.x, l.position.x + l.size.x, (p as Control).size.x])
	return out


func test_the_hint_is_the_width_the_menu_gives_it() -> void:
	var menu = await _open_menu()
	var hint: Label = menu._hint_label
	assert_not_null(hint, "CONTROL: the menu builds its hint")
	assert_gt(hint.get_minimum_size().x, 0.0, "CONTROL: the hint has text to measure")
	assert_eq(hint.size.x, float(MENU.PANEL_W - 40), "the hint must be the width the menu sets, not its detached 16px minimum")


func test_no_label_runs_past_the_panel_with_no_chats() -> void:
	var menu = await _open_menu()
	assert_eq(_labels_outside_their_panel(menu), [], "a label wider than its panel draws over the border")


func test_no_label_runs_past_the_panel_with_chats_listed() -> void:
	GameState.game_constants["cutscene_flag_chapter4_complete"] = true
	GameState.game_constants["cutscene_flag_chapter5_complete"] = true
	var menu = await _open_menu()
	assert_gt(PartyChatSystem.available_count(), 0, "CONTROL: chats are listed, so their rows are measured too")
	assert_eq(_labels_outside_their_panel(menu), [], "a label wider than its panel draws over the border")
