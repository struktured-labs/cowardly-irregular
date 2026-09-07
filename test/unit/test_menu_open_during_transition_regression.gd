extends GutTest

## tick 15 fixed the Start → settings race during an encounter
## transition. The exact same race applies to X → overworld menu and
## L → party chat: both gated only on `current_state == EXPLORATION`
## but the state flip happens AFTER the ~0.5s transition await, so
## the menu opens under the loading battle scene.
##
## tick 16 sweeps the matching paths so all three exploration-mode
## menu openers consult InputLockManager.is_locked() and bail.

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


func test_x_to_overworld_menu_checks_lock() -> void:
	var src := _read(GAME_LOOP_PATH)
	# Scope to the x_pressed branch, not the original menu code or
	# the unrelated x key handler somewhere else in the file.
	var block := _body_after(src, "if x_pressed:", 800)
	assert_ne(block, "", "x_pressed branch must exist")
	assert_true(block.contains("InputLockManager.is_locked()"),
		"X → overworld menu must consult InputLockManager.is_locked() before opening")


func test_party_chat_open_checks_lock() -> void:
	var src := _read(GAME_LOOP_PATH)
	var block := _body_after(src, "if event.is_action_pressed(\"party_chat\"):", 800)
	assert_ne(block, "", "party_chat branch must exist")
	assert_true(block.contains("InputLockManager.is_locked()"),
		"L → party chat must consult InputLockManager.is_locked() before opening")


func test_settings_open_still_checks_lock() -> void:
	# Tick 15's fix must still be in place — this regression test was the
	# first member of the family. If a future cleanup removes it, the
	# whole sweep regresses.
	var src := _read(GAME_LOOP_PATH)
	var block := _body_after(src, "elif current_state == LoopState.EXPLORATION:\n\t\t\t# Escape belongs to the overworld menu", 800)
	assert_ne(block, "", "Start → settings transition guard from tick 15 must still be in place")
	assert_true(block.contains("InputLockManager.is_locked()"),
		"Start → settings must still consult InputLockManager.is_locked()")
