extends GutTest

## struktured's logs (2026-09-24, 2026-09-26): the Fighter's and the Bard's command menus were
## replaced mid-navigation by "[MENU-WATCHDOG] ... sat 2503ms without menu ... menu=invalid", and
## both times the PREVIOUS character had just Deferred. _on_win98_defer_requested called
## BattleManager.player_defer(), which ends the turn synchronously; the next character's
## selection_turn_started makes BattleScene spawn and store THEIR menu; control then returned and
## `_scene.active_win98_menu = null` dropped the NEW menu's reference. The menu stayed on screen and
## answered the cursor, the scene no longer knew it existed, and 2.5s later the watchdog swept it
## and spawned another. Same class as the menu_closed identity guard (msg 2529), on the defer path.

class FakeScene extends Node:
	var active_win98_menu = null
	var party_members: Array = []
	var party_sprite_nodes: Array = []
	func _update_ui() -> void:
		pass

var _saved: Dictionary = {}
var _scene: FakeScene
var _next_menu: Control
var _cmd


func before_each() -> void:
	var bm = BattleManager
	_saved = {
		"player_party": bm.player_party.duplicate(), "enemies": bm.enemy_party.duplicate(),
		"selection_order": bm.selection_order.duplicate(), "selection_index": bm.selection_index,
		"current_combatant": bm.current_combatant, "current_state": bm.current_state,
		"pending_actions": bm.pending_actions.duplicate(),
	}


func after_each() -> void:
	var bm = BattleManager
	if bm.selection_turn_started.is_connected(_install_next_menu):
		bm.selection_turn_started.disconnect(_install_next_menu)
	bm.player_party.assign(_valid(_saved["player_party"]))
	bm.enemy_party.assign(_valid(_saved["enemies"]))
	bm.selection_order.assign(_valid(_saved["selection_order"]))
	bm.selection_index = _saved["selection_index"]
	bm.current_combatant = _saved["current_combatant"] if is_instance_valid(_saved["current_combatant"]) else null
	bm.current_state = _saved["current_state"]
	bm.pending_actions.assign(_saved["pending_actions"])


func _valid(a: Array) -> Array:
	return a.filter(func(x): return is_instance_valid(x))


func _c(n: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


## What BattleScene._on_selection_turn_started does: spawn the next character's menu and store it.
func _install_next_menu(_who) -> void:
	_next_menu = Win98Menu.new()
	add_child_autofree(_next_menu)
	_scene.active_win98_menu = _next_menu


func test_deferring_keeps_the_next_characters_menu() -> void:
	var bm = BattleManager
	var cleric := _c("Cleric")
	var fighter := _c("Fighter")
	var foe := _c("Foe")
	bm.player_party.assign([cleric, fighter] as Array[Combatant])
	bm.enemy_party.assign([foe] as Array[Combatant])
	bm.selection_order.assign([cleric, fighter] as Array[Combatant])
	bm.selection_index = 0
	bm.current_combatant = cleric
	bm.current_state = bm.BattleState.PLAYER_SELECTING
	_scene = FakeScene.new()
	add_child_autofree(_scene)
	var cleric_menu := Control.new()
	add_child_autofree(cleric_menu)
	_scene.active_win98_menu = cleric_menu
	bm.selection_turn_started.connect(_install_next_menu)
	_cmd = BattleCommandMenu.new(_scene)
	_cmd._on_win98_defer_requested()
	assert_not_null(_next_menu,
		"CONTROL: the Cleric's defer must hand the turn to the Fighter, or no next menu was ever spawned")
	assert_eq(_scene.active_win98_menu, _next_menu,
		"the Fighter's menu, spawned during the Cleric's defer, must still be the active menu; nulled, it stays on screen unknown to the scene and the watchdog replaces it mid-navigation")


func test_a_defer_press_through_the_scene_closes_the_next_menu() -> void:
	## cowir-controller, the 8 dropped presses in the 09-24 log: the next press landed inside the new
	## menu's input delay, so BattleScene's direct battle_defer took it and called _close_win98_menu,
	## which is BattleCommandMenu.close_win98_menu. With the ref nulled that close was a no-op, the
	## orphan stayed live, and the press after hit it outside PLAYER_SELECTING ("input dropped").
	test_deferring_keeps_the_next_characters_menu()
	assert_not_null(_next_menu, "CONTROL: the first defer must have spawned the next menu")
	_cmd.close_win98_menu()
	assert_true(_next_menu._is_closing,
		"the scene's close must reach the menu on screen; a nulled ref made it a no-op and left the menu live to eat the next press")
