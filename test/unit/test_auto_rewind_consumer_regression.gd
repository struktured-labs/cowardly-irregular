extends GutTest

## tick 411: GameLoop._on_battle_ended consumes
## meta_auto_rewind_pending (set by tick 404's temporal_shield
## meta-ability). If the player armed the shield and a wipe hits,
## the rewind fires BEFORE the game-over flow — the wipe never
## reaches the screen.
##
## Pre-fix the flag was set but no consumer read it; wipes after
## the cast went through the normal game-over path. Players burned
## 25 MP arming a safety net that did nothing.

const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_consumer_block_exists() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _on_battle_ended")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("meta_auto_rewind_pending"),
		"_on_battle_ended must read meta_auto_rewind_pending flag")
	assert_true(body.contains("rewind_to_previous_save()"),
		"consumer must call GameState.rewind_to_previous_save()")


func test_flag_cleared_unconditionally() -> void:
	# Single-shot semantics: clear the flag whether the rewind
	# succeeded or not, so a stuck shield can't infinitely re-arm.
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _on_battle_ended")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The clear must happen BEFORE the rewind_to_previous_save call.
	var clear_idx: int = body.find("\"meta_auto_rewind_pending\"] = false")
	var rewind_idx: int = body.find("rewind_to_previous_save()")
	assert_gt(clear_idx, -1)
	assert_gt(rewind_idx, -1)
	assert_lt(clear_idx, rewind_idx,
		"flag clear must happen before rewind_to_previous_save call — otherwise a stuck save_history.size() < 2 could leave the flag set forever")


func test_consumer_returns_early_on_successful_rewind() -> void:
	# If rewind succeeds, the wipe handler must NOT continue into the
	# game-over screen. Pin the early return inside the rewind-success branch.
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _on_battle_ended")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The early return after successful rewind is what prevents the
	# game-over flow.
	var rewind_idx: int = body.find("if GameState.rewind_to_previous_save():")
	assert_gt(rewind_idx, -1, "consumer must check the bool return value")
	var window: String = body.substr(rewind_idx, 400)
	assert_true(window.contains("return"),
		"consumer must early-return after a successful rewind so the game-over flow is skipped")


func test_consumer_block_placed_before_game_over() -> void:
	# Pin ordering: consumer block must execute BEFORE
	# pending_boss_defeat = {} and _show_game_over_screen.
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _on_battle_ended")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var consumer_idx: int = body.find("meta_auto_rewind_pending")
	var game_over_idx: int = body.find("_show_game_over_screen")
	assert_gt(consumer_idx, -1)
	assert_gt(game_over_idx, -1)
	assert_lt(consumer_idx, game_over_idx,
		"consumer must run BEFORE _show_game_over_screen — otherwise the player sees the wipe before the rewind")
