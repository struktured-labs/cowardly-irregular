extends GutTest

## struktured's log, 2026-10-30, the Fighter's spotlight duel against the Skeleton Knight: two Power
## Strikes took the boss under 25%, its low_hp line came up, and the next turn's menu was built HIDDEN
## under it on purpose (BattleCommandMenu: "a menu spawning under it starts hidden"). 2.5s later:
## "[MENU-WATCHDOG] Fighter PLAYER_SELECTING sat 2501ms without menu ... menu=valid_but_invisible" and an
## orange "⚠ Menu recovery" line in the battle log while the boss was still talking. Every respawn
## starts hidden for the same reason, so a player still reading at 3 retries x 2.5s had the turn
## autobattled away by the terminal fallback. A boss line owning the screen is not a wedge.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const BattleSceneScript := preload("res://src/battle/BattleScene.gd")
const BattleDialogueScript := preload("res://src/ui/BattleDialogue.gd")

var _bm: RefCounted = null
var _scene = null
var _pc: Combatant = null


func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()
	_scene = BattleSceneScript.new()
	add_child_autofree(_scene)
	if _scene._battle_dialogue == null:
		_scene._battle_dialogue = BattleDialogueScript.new()
		_scene.add_child(_scene._battle_dialogue)
	_pc = Combatant.new()
	_pc.initialize({"name": "Fighter", "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(_pc)
	var bm = BattleManager
	bm.player_party.assign([_pc] as Array[Combatant])
	bm.current_combatant = _pc
	bm.current_state = bm.BattleState.PLAYER_SELECTING
	_scene.active_win98_menu = null


func after_each() -> void:
	if _bm != null:
		_bm.restore()


## The watchdog's clock already well past its threshold, as it is 2.5s into a boss line.
func _overdue(retries: int) -> void:
	_scene._menu_wd_started_ms = Time.get_ticks_msec() - _scene.MENU_WATCHDOG_MS * 4
	_scene._menu_wd_retries = retries


func test_floor_the_symbols_this_file_reaches() -> void:
	for m in ["_tick_menu_watchdog", "_a_boss_line_owns_the_screen", "_reset_menu_watchdog"]:
		assert_true(_scene.has_method(m), "FLOOR: BattleScene.%s must exist" % m)
	for p in ["_menu_wd_started_ms", "_menu_wd_retries", "_battle_dialogue", "active_win98_menu"]:
		assert_true(p in _scene, "FLOOR: BattleScene.%s must exist" % p)


func test_control_with_no_boss_line_the_watchdog_still_fires() -> void:
	_scene._battle_dialogue.visible = false
	_overdue(0)
	_scene._tick_menu_watchdog()
	assert_eq(_scene._menu_wd_retries, 1,
		"CONTROL: overdue with no menu and nothing on screen is a real wedge; the force-spawn must count, or the arm below proves nothing")


func test_a_boss_line_on_screen_is_not_counted_as_a_wedge() -> void:
	_scene._battle_dialogue.visible = true
	_overdue(0)
	_scene._tick_menu_watchdog()
	assert_eq(_scene._menu_wd_retries, 0,
		"a menu hidden under a boss line is hidden ON PURPOSE; counting it puts a '⚠ Menu recovery' line in the log while the boss talks")
	assert_eq(_scene._menu_wd_started_ms, 0,
		"the clock must restart, so the 2.5s grace begins when the line is dismissed, not when it appeared")


func test_a_slow_reader_does_not_lose_the_turn() -> void:
	_scene._battle_dialogue.visible = true
	_overdue(_scene.MENU_WATCHDOG_MAX_RETRIES)
	_scene._tick_menu_watchdog()
	assert_eq(BattleManager.current_state, BattleManager.BattleState.PLAYER_SELECTING,
		"at the retry cap with the boss still talking, the terminal fallback must NOT autobattle the player's turn away")
	assert_eq(BattleManager.current_combatant, _pc, "and the turn stays the duelist's")
