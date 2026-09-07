extends GutTest

## Ticks 15 and 16 caught the EXPLORATION→BATTLE transition race for
## Start/X/L. The same race applies to F5 (open autobattle editor),
## F6 (toggle all autobattle), and Select (toggle all autobattle).
## Pressing any of them during the ~0.5s transition window opens the
## editor / toggles autobattle UNDER the loading battle scene.
##
## Fix: extracted _in_exploration_transition() helper and applied it
## to all three remaining sites.

const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body_after(text: String, anchor: String, span: int) -> String:
	var idx := text.find(anchor)
	if idx < 0:
		return ""
	return text.substr(idx, span)


func test_helper_exists_with_correct_shape() -> void:
	# Helper must check current_state == EXPLORATION AND InputLockManager
	# is_locked. Anything looser blocks dialogue locks in BATTLE; anything
	# stricter misses the race window.
	var src := _read(GAME_LOOP_PATH)
	var idx := src.find("func _in_exploration_transition")
	assert_gt(idx, -1, "_in_exploration_transition helper must exist")
	var body := _body_after(src, "func _in_exploration_transition", 400)
	assert_true(body.contains("LoopState.EXPLORATION"),
		"helper must check LoopState.EXPLORATION (precise scope, not 'any locked state')")
	assert_true(body.contains("InputLockManager.is_locked()"),
		"helper must check InputLockManager.is_locked()")
	assert_true(body.contains("InputLockManager != null"),
		"helper must guard against missing InputLockManager autoload")


func test_f5_uses_transition_guard() -> void:
	var src := _read(GAME_LOOP_PATH)
	var block := _body_after(src, "# F5 = Open autobattle editor", 400)
	assert_ne(block, "", "F5 handler must exist")
	assert_true(block.contains("_in_exploration_transition()"),
		"F5 → autobattle editor must consult _in_exploration_transition() before opening")


func test_f6_uses_transition_guard() -> void:
	var src := _read(GAME_LOOP_PATH)
	var block := _body_after(src, "# F6 or Select button = Toggle autobattle", 400)
	assert_ne(block, "", "F6 handler must exist")
	assert_true(block.contains("_in_exploration_transition()"),
		"F6 → toggle-all must consult _in_exploration_transition() before firing")


func test_select_button_uses_transition_guard() -> void:
	var src := _read(GAME_LOOP_PATH)
	var block := _body_after(src, "Gamepad Select button (button 4 on most controllers)", 1200)
	assert_ne(block, "", "Select-button handler must exist")
	assert_true(block.contains("_in_exploration_transition()"),
		"Select button → toggle-all must consult _in_exploration_transition() too")
