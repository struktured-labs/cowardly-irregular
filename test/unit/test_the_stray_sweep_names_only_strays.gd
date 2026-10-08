extends GutTest

## His sessions logged "[MENU-NULL] path=stray_sweep" 977 times: each turn the sweep reported the one or two menus
## close_win98_menu had JUST closed, which wait in the "win98_menus" group until their queue_free lands. force_close
## no-ops them, so play was fine, but the leak detector fired on every healthy turn and could not name a real leak.

const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")


func _host() -> Control:
	var host := Control.new()
	add_child_autofree(host)
	return host


func _menu(host: Control) -> Node:
	var m: Node = Win98MenuClass.new()
	host.add_child(m)
	return m


func test_a_menu_that_is_closing_is_not_a_stray() -> void:
	var host := _host()
	var closing := _menu(host)
	closing.force_close()
	var leaked := _menu(host)
	var cmd := BattleCommandMenu.new(host)
	var strays: Array = cmd._stray_menus()
	assert_true(leaked in strays, "CONTROL: a live menu nobody closed is a stray")
	assert_false(closing in strays, "a menu already closing is not reported as a leak")
	assert_eq(strays.size(), 1, "exactly the one real leak (%d)" % strays.size())


func test_the_sweep_still_closes_a_real_leak() -> void:
	var host := _host()
	var leaked := _menu(host)
	BattleCommandMenu.new(host)._sweep_stray_menus()
	assert_true(leaked.get("_is_closing") == true, "the sweep force-closes a live stray")
