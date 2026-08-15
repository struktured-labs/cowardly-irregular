extends GutTest

## Regression for struktured's 2026-08-14 cap: bouncing between players during selection
## stacked THREE menus (command + ability submenu + target picker) plus an orphaned tooltip.
## Roots: (1) force_close never cleaned the tooltip, (2) close_all/_close_submenu_to_root
## bare-queue_free'd the submenu — but submenus/highlights/tooltips are SCENE-PARENTED
## SIBLINGS, so grandchildren and their overlays survived, (3) nothing enforced the
## one-chain invariant on turn switch. Fix: cascade closes + a group-based stray sweep.

const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")


func _make_menu(host: Control) -> Node:
	var menu: Node = Win98MenuClass.new()
	host.add_child(menu)
	return menu


func test_menus_join_the_sweep_group() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var menu := _make_menu(host)
	assert_true(menu.is_in_group("win98_menus"), "every Win98Menu registers for the stray sweep")


func test_force_close_cleans_scene_parented_tooltip() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var menu := _make_menu(host)
	# Simulate the tooltip exactly as Win98Menu creates it: a sibling on the menu's parent
	var tip := Label.new()
	host.add_child(tip)
	menu._tooltip_label = tip
	menu.force_close()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(tip), "force_close must free the scene-parented tooltip — the orphaned 'Pray' text in the cap")


func test_close_all_cascades_to_grandchild_submenu() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var root := _make_menu(host)
	var child := _make_menu(host)
	var grandchild := _make_menu(host)
	root.submenu = child
	child.parent_menu = root
	child.submenu = grandchild
	grandchild.parent_menu = child
	# Give the grandchild a scene-parented highlight to prove the cascade cleans overlays too
	var hl := Control.new()
	host.add_child(hl)
	grandchild._target_highlight = hl
	root.close_all()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(grandchild), "grandchild menu freed — bare queue_free of the direct child orphaned it (submenus are siblings)")
	assert_false(is_instance_valid(hl), "grandchild's scene-parented highlight freed with it")


func test_stray_sweep_exists_and_is_scoped() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	var i := src.find("func _sweep_stray_menus")
	assert_gt(i, -1, "sweep helper exists")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_true('get_nodes_in_group("win98_menus")' in body, "sweep is group-driven — reaches menus no reference tracks")
	assert_true("_scene.is_ancestor_of(stray)" in body, "sweep scoped to the battle scene — Win98Menu is used outside battle too")
	assert_true("force_close()" in body, "sweep uses the cascading close, not bare free")
	var show_i := src.find("func show_win98_command_menu")
	var show_body := src.substr(show_i, 400)
	assert_true("_sweep_stray_menus()" in show_body, "sweep runs at every menu spawn — each turn switch self-heals leaks")
