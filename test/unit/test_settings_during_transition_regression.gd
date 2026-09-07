extends GutTest

## User playtest report: 'somehow entered a battle while in settings menu
## or entered settings menu simul now its stuck'. Root cause:
##
## When an overworld encounter fires, _on_exploration_battle_triggered
## pushes InputLockManager.push_lock("encounter_transition") and awaits
## BattleTransition.play_battle_transition (~0.5s). State stays
## LoopState.EXPLORATION until _start_battle_async sets it to BATTLE
## AFTER the transition completes. During that ~0.5s window, pressing
## Start would still satisfy the `current_state == EXPLORATION` check
## and open the settings menu — landing under the loading battle scene.
##
## Fix: also gate the Start → settings path on InputLockManager.is_locked
## so transitions (encounter, area, scene) all block the menu open.

const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _block_around(text: String, anchor: String, span: int) -> String:
	var idx := text.find(anchor)
	if idx < 0:
		return ""
	return text.substr(idx, span)


func test_start_handler_checks_input_lock_before_opening_settings() -> void:
	var src := _read(GAME_LOOP_PATH)
	# Anchor on the EXPLORATION branch of the Start-key dispatcher.
	var block := _block_around(src, "elif current_state == LoopState.EXPLORATION:\n\t\t\t# Escape belongs to the overworld menu", 800)
	assert_ne(block, "", "EXPLORATION branch must have the transition-block guard")
	assert_true(block.contains("InputLockManager.is_locked()"),
		"Start→settings must consult InputLockManager.is_locked() before opening")
	# Must also guard the manager reference — InputLockManager autoload
	# could be absent on a boot-edge path.
	assert_true(block.contains("InputLockManager and"),
		"the is_locked() check must be guarded against missing InputLockManager")


func test_encounter_transition_lock_is_actually_pushed() -> void:
	# Pin the other half: the encounter-trigger path must push the lock
	# the Start guard now reads. Otherwise the guard is reading a flag
	# nobody sets.
	var src := _read(GAME_LOOP_PATH)
	# Anchor on the function definition (not the .connect that uses the
	# same name — find() returns the first hit, which is the connect call).
	var block := _block_around(src, "func _on_exploration_battle_triggered", 2500)
	assert_ne(block, "", "_on_exploration_battle_triggered must be reachable")
	assert_true(block.contains("InputLockManager.push_lock(\"encounter_transition\")"),
		"encounter-trigger path must push the 'encounter_transition' lock — the Start guard depends on it")
