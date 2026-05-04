extends GutTest

## Regression test for the autobattle Minus-button double-toggle bug.
##
## Bug (2026-05-04, fixed in 525dfe1):
## When the user pressed Minus (button 4 / JOY_BUTTON_BACK) during a battle,
## BOTH input handlers fired:
##   1. GameLoop._input — hardcoded `event.button_index == JOY_BUTTON_BACK`
##      check that called _toggle_all_autobattle.
##   2. BattleScene._input — `event.is_action_pressed("battle_toggle_auto")`
##      which also matched (button 4 is bound to that action).
## GameLoop fired first (parent → child input order). It toggled the state.
## Then BattleScene saw the now-toggled state and toggled it AGAIN. Net
## effect: zero. The user pressed Minus, saw nothing change.
##
## Fix: GameLoop's hardcoded JOY_BUTTON_BACK handler now skips during
## LoopState.BATTLE, letting BattleScene._input handle Minus exclusively.
##
## Tested structurally because end-to-end input simulation is fragile
## under GUT.


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_gameloop_skips_minus_in_battle() -> void:
	"""GameLoop._input must NOT call _toggle_all_autobattle on JOY_BUTTON_BACK
	when current_state == LoopState.BATTLE — that path belongs exclusively
	to BattleScene._input now. Both firing canceled each other out."""
	var text = _read("res://src/GameLoop.gd")
	var idx = text.find("event.button_index == JOY_BUTTON_BACK")
	assert_gt(idx, -1, "GameLoop must still have a JOY_BUTTON_BACK handler")
	# Find the surrounding if-block (~600 chars after the match should
	# include the BATTLE-state guard the fix introduced).
	var body = text.substr(idx, 600)
	assert_true(body.find("LoopState.BATTLE") != -1,
		"JOY_BUTTON_BACK handler must reference LoopState.BATTLE for the "
		+ "skip-in-battle gate (regression: pre-525dfe1 the gate was missing "
		+ "and Minus toggled twice, canceling itself out)")


func test_battlescene_owns_battle_toggle_auto_during_battle() -> void:
	"""BattleScene._input must remain the single in-battle handler for
	the battle_toggle_auto action. If GameLoop adds a back-handler that
	doesn't gate on !BATTLE, the double-toggle bug returns."""
	var text = _read("res://src/battle/BattleScene.gd")
	var idx = text.find('is_action_pressed("battle_toggle_auto")')
	assert_gt(idx, -1, "BattleScene must handle battle_toggle_auto action")


func test_clear_pending_player_actions_strips_full_queue() -> void:
	"""Pre-2026-05-04 clear_pending_player_actions tried to "skip the head
	of execution_order if PROCESSING_ACTION" assuming the running action
	was at index 0. But execution_order is consumed via pop_front, so the
	running action has already been popped — index 0 is the NEXT pending
	action and should also be cleared. The skip-logic was a stealth bug
	that let one extra auto-action play after the user disabled."""
	var text = _read("res://src/battle/BattleManager.gd")
	var idx = text.find("func clear_pending_player_actions")
	assert_gt(idx, -1, "clear_pending_player_actions must exist")
	var next_func = text.find("\nfunc ", idx + 1)
	if next_func == -1:
		next_func = text.length()
	var body = text.substr(idx, next_func - idx)
	# Must NOT have a "skip head if PROCESSING_ACTION" branch — that was
	# the buggy behavior. The fix strips ALL player entries unconditionally.
	assert_eq(body.find("if i == 0 and current_state == BattleState.PROCESSING_ACTION"), -1,
		"clear_pending_player_actions must NOT skip the head — "
		+ "execution_order pops the head BEFORE PROCESSING starts, so index 0 "
		+ "is a future action that must be cleared too")


func test_overworld_menu_has_autobattle_toggle_label() -> void:
	"""OverworldMenu must have an "autobattle_toggle" entry separate from
	"autobattle" (which opens the rule editor) — provides the mouse path
	to the global sticky toggle without forcing users to learn the
	gamepad/keyboard binding."""
	var text = _read("res://src/ui/OverworldMenu.gd")
	assert_true(text.find('"autobattle_toggle"') != -1,
		'OverworldMenu must declare an "autobattle_toggle" menu entry')
	assert_true(text.find('"autobattle"') != -1,
		'OverworldMenu must keep the "autobattle" entry (rule editor path)')
	# Verify the live label refresh helper is present (without it the
	# label goes stale when autobattle is toggled via gamepad).
	assert_true(text.find("refresh_autobattle_label") != -1,
		"OverworldMenu must expose refresh_autobattle_label() for "
		+ "GameLoop._toggle_all_autobattle to call")


func test_gameloop_calls_overworld_menu_refresh_on_toggle() -> void:
	"""GameLoop._toggle_all_autobattle must call refresh_autobattle_label
	on _overworld_menu when the menu is open, so the menu label doesn't
	go stale after a Minus/F6 toggle."""
	var text = _read("res://src/GameLoop.gd")
	var idx = text.find("func _toggle_all_autobattle")
	assert_gt(idx, -1, "_toggle_all_autobattle must exist")
	var next_func = text.find("\nfunc ", idx + 1)
	if next_func == -1:
		next_func = text.length()
	var body = text.substr(idx, next_func - idx)
	assert_true(body.find("refresh_autobattle_label") != -1,
		"_toggle_all_autobattle must refresh the OverworldMenu label "
		+ "(regression: pre-fix the label went stale on external toggles)")


func test_battle_command_menu_auto_pick_is_one_shot() -> void:
	"""User clarified the model 2026-05-03:
	  - Menu "Auto" pick = enable for THIS turn only
	  - Minus button    = sticky global toggle
	BattleCommandMenu's autobattle item must save+restore the sticky state
	around execute_autobattle_for_current so the [A] indicator doesn't
	stick after a one-shot Auto pick."""
	var text = _read("res://src/battle/BattleCommandMenu.gd")
	var idx = text.find('item_id == "autobattle"')
	assert_gt(idx, -1, "BattleCommandMenu must handle item_id == 'autobattle'")
	var body = text.substr(idx, 1500)
	assert_true(body.find("was_enabled") != -1,
		"BattleCommandMenu autobattle pick must save the previous sticky "
		+ "state in `was_enabled` (regression: pre-9b261ee the menu pick "
		+ "permanently enabled, conflating one-shot with sticky toggle)")
	assert_true(body.find("set_autobattle_enabled(char_id, was_enabled)") != -1,
		"BattleCommandMenu autobattle pick must restore the saved state "
		+ "after execute_autobattle_for_current returns")
