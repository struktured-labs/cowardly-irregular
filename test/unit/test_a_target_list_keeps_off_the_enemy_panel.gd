extends GutTest

## An ability's or item's target list is a THIRD-level menu. There was no room left of the ability list, so it clamped to
## x=10 and came to rest on the enemy status panel; with a 0.55 fill its rows and the panel's ("ENEMIES", names, AP) drew
## through each other. It now stops at the panel's edge, and a list resting on its own parent gets a near-opaque fill.

const Win98MenuClass := preload("res://src/ui/Win98Menu.gd")

const TARGETS := [
	{"id": "t0", "label": "Slime (680 HP) ~550 dmg"},
	{"id": "t1", "label": "Bat (500 HP) ~574 dmg [KILL]"},
	{"id": "t2", "label": "Goblin (1000 HP) ~534 dmg"},
]

var _panel: Control = null


func _enemy_panel() -> Control:
	var p := Control.new()
	p.name = "EnemyStatusPanel"
	p.position = Vector2(5, 60)
	p.size = Vector2(200, 222)
	add_child_autofree(p)
	return p


func _chain(with_panel: bool) -> Array:
	if with_panel:
		_panel = _enemy_panel()
	var abilities: Array = []
	for i in 8:
		abilities.append({"id": "a%d" % i, "label": "Ability %d [AoE] ~807 total" % i, "submenu": TARGETS})
	var root = Win98MenuClass.new()
	add_child_autofree(root)
	root.setup("Fighter", [{"id": "attack", "label": "Attack"}, {"id": "ability_menu", "label": "Ability", "submenu": abilities}], Vector2(540, 120), "fighter")
	await get_tree().process_frame
	await get_tree().process_frame
	root._open_submenu(1, root.menu_items[1])
	await get_tree().create_timer(0.3).timeout
	var mid = root.submenu
	mid._open_submenu(0, mid.menu_items[0])
	await get_tree().create_timer(0.3).timeout
	return [root, mid, mid.submenu]


func after_each() -> void:
	_panel = null


func test_a_target_list_rests_clear_of_the_enemy_panel() -> void:
	var c: Array = await _chain(true)
	var leaf = c[2]
	assert_not_null(leaf, "CONTROL: the third-level list opened")
	if leaf == null:
		return
	var panel_rect := _panel.get_global_rect()
	var leaf_rect := Rect2(leaf.global_position, leaf.size)
	assert_lt(c[1].global_position.x - leaf.size.x - 6.0, panel_rect.end.x, "CONTROL: there really is no room left of the ability list")
	assert_false(leaf_rect.intersects(panel_rect), "the target list %s does not cover the enemy panel %s" % [str(leaf_rect), str(panel_rect)])
	assert_gte(leaf.global_position.x, panel_rect.end.x, "and it starts right of the panel's edge")


func test_a_list_resting_on_its_parent_reads_solid() -> void:
	var c: Array = await _chain(true)
	var leaf = c[2]
	assert_not_null(leaf, "CONTROL: the third-level list opened")
	if leaf == null:
		return
	assert_true(Rect2(leaf.global_position, leaf.size).intersects(Rect2(c[1].global_position, c[1].size)), "CONTROL: the list rests on its parent")
	assert_almost_eq(c[0]._panel_fill.color.a, c[0].style.bg.a * Win98MenuClass.PANEL_ALPHA, 0.001, "CONTROL: the root keeps the see-through fill")
	assert_almost_eq(c[1]._panel_fill.color.a, c[1].style.bg.a * Win98MenuClass.PANEL_ALPHA, 0.001, "a submenu beside its parent keeps it too")
	assert_gt(leaf._panel_fill.color.a, 0.85, "the overlapping list has a near-opaque fill, so the rows under it do not show through")


func test_without_an_enemy_panel_the_screen_margin_is_the_bound() -> void:
	var c: Array = await _chain(false)
	var leaf = c[2]
	assert_not_null(leaf, "CONTROL: the third-level list opened")
	if leaf == null:
		return
	assert_gte(leaf.global_position.x, 10.0, "the list stays on screen")
	assert_lt(leaf.global_position.x, 200.0, "and is free to use the left column when nothing is there")


func _turn_banner() -> Control:
	var p := Control.new()
	p.name = "TurnInfoPanel"
	p.position = Vector2(440, 10)
	p.size = Vector2(400, 40)
	add_child_autofree(p)
	return p


func test_a_list_that_would_cross_the_turn_banner_drops_below_it() -> void:
	var banner := _turn_banner()
	var c: Array = await _chain(true)
	var leaf = c[2]
	assert_not_null(leaf, "CONTROL: the third-level list opened")
	if leaf == null:
		return
	var leaf_rect := Rect2(leaf.global_position, leaf.size)
	var banner_rect := banner.get_global_rect()
	assert_gt(leaf_rect.end.x, banner_rect.position.x, "CONTROL: the list is wide enough to reach the banner's column")
	assert_false(leaf_rect.intersects(banner_rect), "the target list %s does not cover the turn banner %s" % [str(leaf_rect), str(banner_rect)])
	assert_false(leaf_rect.intersects(_panel.get_global_rect()), "and it still keeps off the enemy panel")


func test_a_list_clear_of_the_banner_is_not_moved() -> void:
	var with_banner_far := Control.new()
	with_banner_far.name = "TurnInfoPanel"
	with_banner_far.position = Vector2(900, 600)
	with_banner_far.size = Vector2(200, 40)
	add_child_autofree(with_banner_far)
	var c: Array = await _chain(true)
	var leaf = c[2]
	assert_not_null(leaf, "CONTROL: the third-level list opened")
	if leaf == null:
		return
	assert_almost_eq(leaf.global_position.y, 10.0, 12.0, "a banner nowhere near leaves the list where the tree put it")
