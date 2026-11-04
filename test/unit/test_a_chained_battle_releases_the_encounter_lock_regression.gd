extends GutTest

## His logs, 2026-11-01..02: "[InputLockManager] Stale lock expired: 'encounter_transition' (held 15-69s)", every time
## at "[CHAIN] next battle". An encounter pushes that lock to dead-stop the player through the transition, and only
## _start_exploration's pop_all released it, so through a chain (battle -> battle, no exploration) it outlived the
## whole first battle until the reaper expired it, and every is_locked() reader saw a lock nobody held. It is released
## now where BATTLE takes over movement: GameLoop._enter_battle_state, called by _start_battle_async.

const LOCK := "encounter_transition"


func before_each() -> void:
	InputLockManager.pop_all()


func after_each() -> void:
	InputLockManager.pop_all()


func _game_loop() -> Node:
	var gl: Node = load("res://src/GameLoop.gd").new()
	autofree(gl)
	return gl


func test_entering_battle_releases_the_encounter_lock() -> void:
	InputLockManager.push_lock(LOCK)
	assert_true(InputLockManager.has_lock(LOCK), "CONTROL: the encounter dead-stop is held")
	var gl := _game_loop()
	gl._battle_transition_starting = true
	gl._enter_battle_state()
	assert_false(InputLockManager.has_lock(LOCK), "BATTLE owns movement now; the encounter's lock is released, not left to the reaper")
	assert_eq(gl.current_state, gl.LoopState.BATTLE, "and the loop is in BATTLE")
	assert_false(gl._battle_transition_starting, "and the transition mutex is handed to the BATTLE state")


## Only the encounter's own lock: a dialogue or cutscene lock held across the start is not ours to drop.
func test_entering_battle_leaves_other_locks_alone() -> void:
	InputLockManager.push_lock(LOCK)
	InputLockManager.push_lock("zzz_someone_elses_lock")
	_game_loop()._enter_battle_state()
	assert_true(InputLockManager.has_lock("zzz_someone_elses_lock"), "a lock the encounter did not push survives")


## The real entry must go through it before its first await, or a chain link starts with the lock still held.
func test_battle_start_enters_the_state_before_it_awaits() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i := src.find("func _start_battle_async")
	assert_gt(i, -1, "CONTROL: the battle entry exists")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	var enter := body.find("_enter_battle_state()")
	assert_gt(enter, -1, "_start_battle_async enters the battle state through the one helper")
	var first_await := body.find("await ")
	assert_true(first_await == -1 or enter < first_await, "and does so before its first await")
