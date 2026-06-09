extends GutTest

## Regression: Trust toggle in BattleCommandMenu lets the player flip
## the per-PC autobattle_locked field directly during their turn.
##
## User vocabulary (playtest 2026-06-04): "I thought 'Trust' was the
## menu option to make the character act autonomously." The toggle
## sits next to Auto / Auto Rules in the top of the command menu;
## label reads "Trust: ON" or "Trust: OFF" tracking current state.
##
## Source-pin tests (cheap). End-to-end behavioural would need the full
## battle autoload + Win98Menu graph; we pin the surface instead.


const BATTLE_COMMAND_MENU_PATH := "res://src/battle/BattleCommandMenu.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_trust_menu_item_appended_after_autobattle_rules() -> void:
	var text = _read(BATTLE_COMMAND_MENU_PATH)
	# Verify the item appears in build_command_menu_items_with_targets and
	# uses the trust_toggle id + dynamic ON/OFF label.
	var fn_idx = text.find("func build_command_menu_items_with_targets")
	assert_gt(fn_idx, -1, "build_command_menu_items_with_targets must exist")
	# Find the trust_toggle id within the function body.
	var body = text.substr(fn_idx)
	var trust_idx = body.find("\"trust_toggle\"")
	assert_gt(trust_idx, -1,
		"build_command_menu_items_with_targets must append a 'trust_toggle' menu item")
	# Label must be dynamic — ON when autobattle_locked, OFF otherwise.
	assert_true(body.find("\"Trust: ON\" if combatant.autobattle_locked else \"Trust: OFF\"") > -1,
		"trust_toggle label must read state from combatant.autobattle_locked")


func test_trust_toggle_action_handler_flips_field() -> void:
	var text = _read(BATTLE_COMMAND_MENU_PATH)
	# The action handler must check item_id == "trust_toggle" and flip
	# combatant.autobattle_locked.
	var idx = text.find("if item_id == \"trust_toggle\"")
	assert_gt(idx, -1, "Trust action handler must dispatch on item_id 'trust_toggle'")
	var slice = text.substr(idx, 800)
	assert_true(slice.find("autobattle_locked = not") > -1
		or slice.find("autobattle_locked = !") > -1,
		"Trust handler must flip combatant.autobattle_locked")
	assert_true(slice.find("close_win98_menu()") > -1,
		"Trust handler must close the menu after flipping so next-turn routing picks up the new state")


func test_trust_handler_kicks_off_autobattle_when_trust_on() -> void:
	# When the user flips Trust ON during their selection turn, the AI
	# should immediately handle the in-flight selection instead of leaving
	# them stuck waiting for input (which is what happened pre-Trust if
	# the player closed the menu without picking).
	var text = _read(BATTLE_COMMAND_MENU_PATH)
	var idx = text.find("if item_id == \"trust_toggle\"")
	assert_gt(idx, -1, "Trust handler must exist")
	# Window large enough to absorb the comment block + close_win98_menu()
	# + the conditional autobattle call. Trust-handler block is < 1500 chars.
	var slice = text.substr(idx, 1500)
	assert_true(slice.find("execute_autobattle_for_current()") > -1,
		"Trust ON must call BattleManager.execute_autobattle_for_current so the in-flight selection proceeds via AI")
