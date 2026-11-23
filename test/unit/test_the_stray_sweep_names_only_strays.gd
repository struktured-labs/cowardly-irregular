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


## Scene stand-in: the handler reads these two members off its scene.
class SceneStub extends Control:
	var active_win98_menu: Node = null
	var command_memory_enabled: bool = false


## His .808 session: 86 stray_sweep lines, 33 of 33 right after "chooses to advance". The Advance handler dropped its
## reference without closing, so the next PC's menu spawned over the old chain and the sweep reported 2-3 "leaks".
func test_an_advance_leaves_no_stray_for_the_next_menu() -> void:
	var saved_current = BattleManager.current_combatant
	BattleManager.current_combatant = null  # the handler stops after the close: no turn is dispatched here
	var host := SceneStub.new()
	add_child_autofree(host)
	var root := _menu(host)
	var sub := _menu(host)
	sub.parent_menu = root
	root.submenu = sub
	host.active_win98_menu = root
	var cmd := BattleCommandMenu.new(host)
	assert_eq(cmd._stray_menus().size(), 2, "CONTROL: an open root and its submenu are what the sweep would see")
	cmd._on_win98_actions_submitted([])
	BattleManager.current_combatant = saved_current
	assert_null(host.active_win98_menu, "the Advance lets go of its menu")
	assert_eq(cmd._stray_menus(), [], "an Advance closes its own chain, so the next menu's sweep finds nothing")
	assert_true(root.get("_is_closing") == true and sub.get("_is_closing") == true, "root and submenu are both closing")
