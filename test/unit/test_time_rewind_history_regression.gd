extends GutTest

## Regression test for the Time Mage 'time_rewind' dead-feature bug (2026-06-14).
##
## Bug: rewind_to_previous_save() requires save_history.size() >= 2, but the
## only function that appended to save_history (_add_to_history) had ZERO
## callers anywhere in src/. So save_history was always empty and the Time Mage
## 'time_rewind' ability (abilities.json 'rewind' → meta_effect 'time_rewind' →
## BattleManager → GameState.rewind_to_previous_save) was permanently a no-op,
## tripping the "No previous save state to rewind to" guard every time.
##
## Fix: added public record_history_checkpoint() that snapshots current state
## into the ring buffer so callers (SaveSystem on save, BattleManager at battle
## start) can feed history. Gated on meta_features.rewind_enabled (set by
## unlock_time_mage_features) so we don't pay the duplicate cost pre-unlock.
##
## These tests exercise the save_history push + rewind path and the fail-safe
## locked path.

const GameStateScript = preload("res://src/meta/GameState.gd")

var _game_state: Node


func before_each() -> void:
	_game_state = GameStateScript.new()
	_game_state.name = "TestGameStateRewind"
	add_child_autofree(_game_state)
	_game_state.reset_game_state()


func test_checkpoint_noop_when_rewind_locked() -> void:
	# Pre-unlock, record_history_checkpoint should NOT populate history
	# (avoids deep-duplicate overhead before the Time Mage unlock).
	assert_false(_game_state.meta_features.get("rewind_enabled", false),
		"rewind should default to locked")
	var recorded = _game_state.record_history_checkpoint()
	assert_false(recorded, "checkpoint should be skipped while rewind is locked")
	assert_eq(_game_state.save_history.size(), 0,
		"save_history must stay empty before unlock")


func test_checkpoint_force_records_even_when_locked() -> void:
	# Explicit force=true snapshots regardless of unlock state (tests/quicksave).
	var recorded = _game_state.record_history_checkpoint(true)
	assert_true(recorded, "forced checkpoint should record")
	assert_eq(_game_state.save_history.size(), 1,
		"forced checkpoint should push one history entry")


func test_checkpoint_populates_history_after_unlock() -> void:
	# The core regression: after unlock, checkpoints must actually feed history.
	_game_state.unlock_time_mage_features()
	assert_true(_game_state.meta_features["rewind_enabled"],
		"unlock_time_mage_features should enable rewind")

	assert_eq(_game_state.save_history.size(), 0, "history starts empty")
	_game_state.record_history_checkpoint()
	_game_state.record_history_checkpoint()
	assert_eq(_game_state.save_history.size(), 2,
		"two checkpoints should yield two history entries (was the dead path)")


func test_rewind_succeeds_after_unlock_and_checkpoints() -> void:
	# End-to-end: unlock, snapshot distinct states, rewind restores the prior one.
	_game_state.unlock_time_mage_features()

	# Checkpoint state A (gold = 500 default), then mutate and checkpoint B.
	_game_state.party_gold = 500
	_game_state.record_history_checkpoint()

	_game_state.party_gold = 1234
	_game_state.record_history_checkpoint()

	assert_eq(_game_state.save_history.size(), 2, "two checkpoints recorded")

	var ok = _game_state.rewind_to_previous_save()
	assert_true(ok, "rewind should succeed with >=2 history entries after unlock")
	assert_eq(_game_state.party_gold, 500,
		"rewind should restore the earlier checkpoint's gold")


func test_rewind_fails_safe_when_locked() -> void:
	# Even if history somehow has entries, a locked rewind fails safe (no crash,
	# returns false). Force-feed two checkpoints, leave rewind locked.
	_game_state.record_history_checkpoint(true)
	_game_state.record_history_checkpoint(true)
	assert_eq(_game_state.save_history.size(), 2, "forced checkpoints recorded")

	assert_false(_game_state.meta_features.get("rewind_enabled", false),
		"rewind still locked")
	var ok = _game_state.rewind_to_previous_save()
	assert_false(ok, "rewind must fail safe (return false) while locked")


func test_rewind_fails_safe_with_insufficient_history() -> void:
	# Unlocked but fewer than 2 checkpoints — graceful no-op, returns false.
	_game_state.unlock_time_mage_features()
	var ok_empty = _game_state.rewind_to_previous_save()
	assert_false(ok_empty, "rewind with empty history should fail safe")

	_game_state.record_history_checkpoint()
	var ok_one = _game_state.rewind_to_previous_save()
	assert_false(ok_one, "rewind with a single checkpoint should fail safe")


func test_history_respects_max_size_cap() -> void:
	# Ring buffer must not grow without bound — older entries drop off the front.
	_game_state.unlock_time_mage_features()
	var cap = _game_state.max_history_size
	for i in range(cap + 5):
		_game_state.record_history_checkpoint()
	assert_eq(_game_state.save_history.size(), cap,
		"save_history should be capped at max_history_size")
