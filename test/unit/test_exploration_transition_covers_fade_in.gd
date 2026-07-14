extends GutTest

## tick 79 regression: _in_exploration_transition() must return true
## during area-transition fade-IN (when _transition_in_progress is
## set but InputLockManager has no lock yet). Pre-fix, the helper
## only checked InputLockManager.is_locked() — so F5 (autobattle
## editor), F6 (toggle all autobattle), and gamepad Select inputs
## fired DURING the fade-in, opening UI on the about-to-be-freed
## scene. Same race class as tick 78 (overworld menu), but for the
## autobattle-input handlers which use this helper instead of an
## inline guard.

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _helper_body() -> String:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _in_exploration_transition")
	assert_gt(idx, -1, "_in_exploration_transition helper must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_helper_checks_transition_in_progress() -> void:
	var body := _helper_body()
	assert_true(body.contains("_transition_in_progress"),
		"_in_exploration_transition must check _transition_in_progress — covers fade-IN window where no InputLockManager lock is held yet")


func test_helper_still_checks_input_lock_manager() -> void:
	# Don't regress the existing encounter-transition / fade-out coverage.
	var body := _helper_body()
	assert_true(body.contains("InputLockManager.is_locked()"),
		"_in_exploration_transition must STILL check InputLockManager.is_locked — covers encounter-transition and fade-out locks (the original case)")


func test_helper_still_gated_to_exploration_state() -> void:
	# Critical: helper must NOT return true during BATTLE state, even
	# when a dialogue lock is held. Otherwise BattleScene-level
	# hotkey handling (which uses this helper transitively) breaks.
	var body := _helper_body()
	assert_true(body.contains("current_state != LoopState.EXPLORATION"),
		"_in_exploration_transition must short-circuit return false when not in EXPLORATION — protects BATTLE-state input from being silenced by exploration locks")


func test_transition_in_progress_path_returns_early_before_lock_check() -> void:
	# Pin the ordering: short-circuit on _transition_in_progress so
	# we don't need a non-null InputLockManager during fade-IN. A
	# fresh save load can hit this helper before InputLockManager
	# autoloads finish (rare but real).
	var body := _helper_body()
	var trans_idx: int = body.find("if _transition_in_progress:")
	var lock_idx: int = body.find("InputLockManager.is_locked()")
	assert_gt(trans_idx, -1, "must have transition-in-progress check")
	assert_gt(lock_idx, -1, "must have InputLockManager.is_locked check")
	assert_lt(trans_idx, lock_idx,
		"_transition_in_progress check must precede InputLockManager.is_locked — fade-IN path is independent of the lock manager")


func test_autobattle_handlers_still_call_helper() -> void:
	# Don't regress the call sites — F5, F6, and gamepad Select all
	# call this helper. If a future refactor inlines the check,
	# the tick-79 fix evaporates.
	var src := _read(GAME_LOOP)
	# Scope to the _input function range to avoid matching unrelated
	# helper usage elsewhere.
	var input_idx: int = src.find("func _input(event: InputEvent)")
	assert_gt(input_idx, -1, "_input must exist")
	# Look forward through the F5/F6/Select region (~6000 chars from
	# func _input to past the JOY_BUTTON_BACK handler).
	var window: String = src.substr(input_idx, 7000)
	# F5 block
	assert_true(window.contains("KEY_F5") and window.find("_in_exploration_transition()") > window.find("KEY_F5"),
		"F5 autobattle-editor handler must guard with _in_exploration_transition()")
	# F6 block
	assert_true(window.contains("KEY_F6") and window.find("_in_exploration_transition()", window.find("KEY_F6")) > 0,
		"F6 toggle-all-autobattle handler must guard with _in_exploration_transition()")
	# Gamepad Select (JOY_BUTTON_BACK)
	assert_true(window.contains("JOY_BUTTON_BACK"),
		"gamepad Select handler must exist")
	assert_gt(window.find("_in_exploration_transition()", window.find("JOY_BUTTON_BACK")), -1,
		"gamepad Select handler must guard with _in_exploration_transition()")
