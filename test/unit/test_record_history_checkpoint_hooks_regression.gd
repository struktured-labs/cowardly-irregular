extends GutTest

## tick 414: SaveSystem.save_game success and BattleManager.start_battle
## both call GameState.record_history_checkpoint(false).
##
## Pre-fix only the meta-ability create_restore_point (tick 412) and
## time_rewind paths fed the rewind ring buffer. Players who built up
## the Time Mage unlock had ZERO history snapshots from normal play —
## rewind_to_previous_save always tripped the "no previous save state"
## guard. The helper's docstring claimed these hooks existed but no
## production caller wired them.
##
## Soft call (force=false) respects rewind_enabled so pre-Time-Mage
## flows pay no deep-duplicate cost.

const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"
const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_save_system_calls_helper_on_success() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func save_game")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("record_history_checkpoint(false)"),
		"save_game success path must call GameState.record_history_checkpoint(false)")
	# Pin ordering: call must happen BEFORE save_completed.emit so the
	# checkpoint reflects the just-saved state.
	var call_idx: int = body.find("record_history_checkpoint(false)")
	var emit_idx: int = body.find("save_completed.emit")
	assert_gt(call_idx, -1)
	assert_gt(emit_idx, -1)
	assert_lt(call_idx, emit_idx,
		"checkpoint call must happen before save_completed.emit so the snapshot reflects the persisted state")


func test_battle_manager_calls_helper_at_start() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func start_battle(")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("record_history_checkpoint(false)"),
		"start_battle must call GameState.record_history_checkpoint(false) so rewinds can undo this battle")


func test_soft_call_respects_rewind_enabled() -> void:
	# Sanity: force=false skips the snapshot when rewind isn't unlocked.
	# This is the gate that makes the new hooks cheap pre-Time-Mage.
	if not GameState:
		pending("GameState autoload required")
		return
	var prior_enabled: bool = bool(GameState.meta_features.get("rewind_enabled", false))
	var prior_history := GameState.save_history.duplicate(true)
	GameState.meta_features["rewind_enabled"] = false
	GameState.save_history = []
	var ok: bool = GameState.record_history_checkpoint(false)
	assert_false(ok,
		"soft call must return false when rewind_enabled=false")
	assert_eq(GameState.save_history.size(), 0,
		"soft call must NOT push to save_history when rewind isn't unlocked")
	# Restore.
	GameState.meta_features["rewind_enabled"] = prior_enabled
	GameState.save_history = prior_history
