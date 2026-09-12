extends GutTest

## InputLockManager has a 10-second stale-lock backstop and it protected ONE of its two readers.
##
##   is_locked()   23 callers   expired stale entries   ✅
##   has_lock(id)   1 caller    read the dict directly  ⛔
##
## Measured: age a lock past STALE_TIMEOUT_MS and `has_lock` answered TRUE while `is_locked`
## answered FALSE. The only thing that ever cleared it for `has_lock` was an unrelated caller
## happening to run `is_locked()` and reaping as a side effect.
##
## ⛔ THE CONSEQUENCE IS SPECIFIC, which is why this is not tidying. `_start_battle_async`
## (GameLoop:~4345) DROPS EVERY ENCOUNTER while `has_lock("world_transition")` is true:
##     if InputLockManager.has_lock("world_transition"):
##         push_warning("[BATTLE] entry suppressed — world transition mid-dissolve")
##         return
## and its own comment says it exists for the 2026-08-08 stuck class — a mid-dissolve battle
## killing the transition tween so the pop never runs. **That is the leak it could not recover
## from**, because the backstop written for exactly this hazard did not reach this reader.
##
## ⚠️ HONEST EXPOSURE, because the fix is smaller than the story: `is_locked` is called from 23
## sites including player movement, so in practice something reaps within a frame or two of the
## player doing anything. This closes a dependency on an unrelated caller running, not an
## observed freeze. I did not reproduce a stuck encounter on a live build and am not claiming one.

const LOCK := "zzz_probe_lock"


func _ilm():
	return InputLockManager


func before_each() -> void:
	_ilm().pop_all()


func after_each() -> void:
	_ilm().pop_all()


## Push a lock and backdate it past the timeout — how a leaked lock ages on the player's couch.
func _push_aged(lock_id: String, extra_ms: int = 5000) -> void:
	_ilm().push_lock(lock_id)
	_ilm()._locks[lock_id] = Time.get_ticks_msec() - (_ilm().STALE_TIMEOUT_MS + extra_ms)


## ⛔ THE DEFECT. has_lock must honour the backstop on its own, with no other reader involved.
func test_has_lock_expires_a_stale_lock_without_help() -> void:
	_push_aged(LOCK)
	# NOTE: is_locked() is deliberately NOT called first — that is the whole point. Calling it
	# would reap as a side effect and this arm would pass on the broken code.
	assert_false(_ilm().has_lock(LOCK),
		"has_lock must reap stale entries itself. Before 2026-09-12 it read the dict directly, so " +
		"a leaked lock answered TRUE forever unless something unrelated called is_locked()")


func test_is_locked_still_expires_too() -> void:
	_push_aged(LOCK)
	assert_false(_ilm().is_locked(),
		"the reader that always had the backstop must keep it — one reaper, both callers")


## ⛔ THE OTHER DIRECTION. A reaper that expires everything would pass both arms above and break
## every lock in the game.
func test_a_fresh_lock_is_still_held_by_both_readers() -> void:
	_ilm().push_lock(LOCK)
	assert_true(_ilm().has_lock(LOCK), "a lock pushed just now must be HELD, not reaped")
	assert_true(_ilm().is_locked(), "…and must register as locked")
	_ilm().pop_lock(LOCK)
	assert_false(_ilm().has_lock(LOCK), "and popping it must release it")


## CONTROL for the ageing helper: without this, "stale locks expire" could pass because the lock
## was never actually pushed, or because the backdating did nothing.
func test_the_ageing_helper_really_ages_the_lock() -> void:
	_ilm().push_lock(LOCK)
	assert_true(_ilm().has_lock(LOCK), "CONTROL: the lock must exist before we age it")
	var fresh_ts: int = int(_ilm()._locks[LOCK])
	_ilm()._locks[LOCK] = Time.get_ticks_msec() - (_ilm().STALE_TIMEOUT_MS + 5000)
	assert_lt(int(_ilm()._locks[LOCK]), fresh_ts,
		"CONTROL: backdating must move the timestamp EARLIER, or the arms above age nothing")
	assert_gt(_ilm().STALE_TIMEOUT_MS, 0, "CONTROL: the timeout must be a real duration")


## The consequence this guard exists for must still be the live shape — if the battle funnel stops
## gating on has_lock, this file is defending a path nobody walks and should be re-read.
func test_the_battle_funnel_still_gates_on_has_lock() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_gt(src.length(), 1000, "CONTROL: GameLoop must be readable")
	assert_true(src.find('has_lock("world_transition")') > -1,
		"_start_battle_async must still suppress entry on has_lock(\"world_transition\") — that " +
		"caller is why has_lock needed the backstop. If this gate is gone, re-read this file " +
		"rather than deleting the reap: the reap is correct regardless, but its urgency came here")
