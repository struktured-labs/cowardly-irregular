extends GutTest

## tick 413: GameState.save_history is persisted across save+quit.
## Pre-fix it was in-memory only — Time Mage rewinds and tick 412's
## restore points evaporated whenever the player quit and reloaded.
##
## Round-trip:
##   1. record_history_checkpoint pushes a snapshot to save_history
##   2. _create_save_data embeds it via _serialize_save_history,
##      stripping nested save_history from each snapshot to prevent
##      recursive bloat
##   3. _apply_save_data restores it (typed-Array coercion to dodge
##      the silent-fail trap, capped at max_history_size on load)

const GAME_STATE_PATH := "res://src/meta/GameState.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_save_data_includes_save_history() -> void:
	var src := _read(GAME_STATE_PATH)
	var fn_idx: int = src.find("func _create_save_data")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"save_history\": _serialize_save_history()"),
		"_create_save_data must include save_history field via _serialize_save_history helper")


func test_serializer_strips_nested_history() -> void:
	var src := _read(GAME_STATE_PATH)
	assert_true(src.contains("func _serialize_save_history()"),
		"GameState must declare _serialize_save_history helper")
	var fn_idx: int = src.find("func _serialize_save_history")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Each snapshot must have its nested save_history erased.
	assert_true(body.contains("stripped.erase(\"save_history\")"),
		"_serialize_save_history must strip nested save_history from each snapshot")


func test_load_uses_typed_array_coercion() -> void:
	var src := _read(GAME_STATE_PATH)
	var fn_idx: int = src.find("func _apply_save_data")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("var typed_history: Array[Dictionary] = []"),
		"_apply_save_data save_history load must use Array[Dictionary] typed coercion")
	# Type guard so a malformed save doesn't crash.
	assert_true(body.contains("raw_history is Array"),
		"_apply_save_data must type-guard save_history before iteration")
	# max_history_size cap on load to defend against corrupted big saves.
	assert_true(body.contains("typed_history.size() > max_history_size"),
		"_apply_save_data must cap save_history to max_history_size on load")


func test_round_trip_preserves_history() -> void:
	# End-to-end: record, save, clear, load, verify.
	if not GameState:
		pending("GameState autoload required")
		return
	var prior_history := GameState.save_history.duplicate(true)
	GameState.save_history = []
	# Push two known snapshots.
	GameState.record_history_checkpoint(true)
	GameState.record_history_checkpoint(true)
	var pre_save_size: int = GameState.save_history.size()
	assert_gt(pre_save_size, 0)
	# Serialize + load.
	var save_data: Dictionary = GameState._create_save_data()
	GameState.save_history = []
	GameState._apply_save_data(save_data)
	assert_eq(GameState.save_history.size(), pre_save_size,
		"save_history must survive a serialize+load round-trip")
	# Restore.
	GameState.save_history = prior_history


func test_load_handles_malformed_save_history() -> void:
	# Defensive: a corrupted save with non-Array save_history must not crash.
	if not GameState:
		pending("GameState autoload required")
		return
	var prior := GameState.save_history.duplicate(true)
	GameState.save_history = []
	GameState._apply_save_data({"save_history": "not an array"})
	# Survived (no crash), and stayed at the prior in-memory state (empty here).
	assert_eq(typeof(GameState.save_history), TYPE_ARRAY,
		"save_history must remain a typed array after malformed-load")
	GameState.save_history = prior
