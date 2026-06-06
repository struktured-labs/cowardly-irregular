extends GutTest

## Regression test for the "stuck after B at first PC" bug (2026-06-04).
##
## Repro: pressing B during the lead PC's selection
##   1. BattleCommandMenu._on_win98_go_back_requested force-closes the menu
##   2. BattleManager.go_back_to_previous_player walks back, finds no
##      previous player (lead is first), and originally returned silently
##   3. Engine stays in PLAYER_SELECTING — no menu, no signal, no input
##      surface. Player can only escape by toggling autobattle.
##
## Fix: when no previous player exists, BattleManager must re-emit
## selection_turn_started so the menu re-opens at the current PC. The
## "back" becomes a no-op-with-feedback instead of a deadlock.


const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_go_back_no_previous_player_reopens_menu() -> void:
	# Source pin: the early-return branch of go_back_to_previous_player
	# must re-emit selection_turn_started so the closed command menu
	# re-opens.
	var text = _read(BATTLE_MANAGER_PATH)
	var fn_idx = text.find("func go_back_to_previous_player")
	assert_gt(fn_idx, -1, "go_back_to_previous_player must exist")
	# Slice the function body (until next `\nfunc `).
	var fn_end = text.find("\nfunc ", fn_idx + 1)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx)
	# The no-previous-player branch.
	var no_prev_idx = body.find("if not found_player:")
	assert_gt(no_prev_idx, -1, "no-previous-player branch must exist")
	# Slice from `if not found_player:` until the next non-indented `\n\t...`
	# or end of function. Cheaper: just look up to the `return`.
	var branch = body.substr(no_prev_idx)
	# This is the branch that historically returned silently. It MUST
	# re-emit selection_turn_started before the return — otherwise the
	# force-closed menu never re-opens and the player is stuck.
	var ret_idx = branch.find("return")
	assert_gt(ret_idx, -1, "branch must have a return")
	var pre_return = branch.substr(0, ret_idx)
	assert_true(pre_return.find("selection_turn_started.emit") > -1,
		"no-previous-player branch must re-emit selection_turn_started before return so the menu re-opens. " +
		"Without this, force-closing the menu leaves the game in PLAYER_SELECTING with no input surface.")
