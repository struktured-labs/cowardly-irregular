extends GutTest

## cowir-main 23304: in .788 the back_closes mutation (Back no longer un-zooms) closed the ability list while zoomed and
## godot crashed with signal 11. Routing made that unreachable; this pins it impossible by construction: every way a
## list can close while zoomed leaves no card behind, no zoom latched, and no crash.

const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")
const LONG := "Calls down a pillar of lightning that strikes every foe at once, then lingers as static that may stun anything still standing when it clears."


func _rows() -> Array:
	return [{"id": "ability_menu_thundaga", "label": "Thundaga", "tooltip": LONG, "submenu": [{"id": "ability_thundaga_enemy_0", "label": "Goblin"}]}]


func _opened() -> Array:
	var holder := Control.new()
	add_child_autofree(holder)
	holder.size = Vector2(1280, 720)
	var root = Win98MenuClass.new()
	holder.add_child(root)
	var items := [{"id": "ability_menu", "label": "Ability", "submenu": _rows()}, {"id": "attack_menu", "label": "Attack"}]
	root.setup("Fighter", items, Vector2(400, 420), "fighter")
	for i in 3:
		await get_tree().process_frame
	root._can_accept_input = true
	root._do_open_submenu(0, items[0])
	for i in 3:
		await get_tree().process_frame
	var sub = root.submenu
	if sub:
		sub._can_accept_input = true
		sub._toggle_zoom()
		for i in 3:
			await get_tree().process_frame
	return [holder, root, sub]


func _cards(holder: Node) -> int:
	var n := 0
	for c in holder.find_children("*", "", true, false):
		if c is AbilityZoomCard and not c.is_queued_for_deletion():
			n += 1
	return n


func _close(how: String, root, sub) -> void:
	match how:
		"to_root":
			sub._close_submenu_to_root()
		"root_force_close":
			root.force_close()
		"close_all":
			sub.close_all()
		"list_freed":
			root.submenu = null
			sub.queue_free()


func test_closing_a_zoomed_list_any_way_leaves_no_card() -> void:
	var left: Array = []
	for how in ["to_root", "root_force_close", "close_all", "list_freed"]:
		var t: Array = await _opened()
		var holder: Node = t[0]
		var sub = t[2]
		assert_not_null(sub, "CONTROL (%s): the Ability list opened" % how)
		if sub == null:
			continue
		assert_true(sub.is_zoomed() and _cards(holder) == 1, "CONTROL (%s): the list is zoomed with its card up" % how)
		_close(how, t[1], sub)
		if is_instance_valid(sub) and not sub.is_queued_for_deletion():
			assert_false(sub.is_zoomed(), "%s leaves the list open but must not leave it zoomed" % how)
		for i in 3:
			await get_tree().process_frame
		if _cards(holder) != 0:
			left.append("%s left %d card(s)" % [how, _cards(holder)])
	assert_eq(left, [], "a list that closes while zoomed must take its card with it")


func test_teardown_unlatches_the_zoom() -> void:
	var t: Array = await _opened()
	var sub = t[2]
	assert_not_null(sub, "CONTROL: the Ability list opened")
	if sub == null:
		return
	assert_true(sub.is_zoomed(), "CONTROL: zoomed")
	sub._cleanup_tooltip()
	assert_false(sub.is_zoomed(), "teardown frees the card, so it must clear the zoom too, or the next refresh rebuilds a card on a closing list")
	assert_null(sub.zoom_card(), "and the card is gone")
