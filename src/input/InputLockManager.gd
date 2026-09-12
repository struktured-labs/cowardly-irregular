extends Node

## InputLockManager — centralized movement lock system.
## Push named locks to freeze player, pop to unfreeze.
## Stale locks auto-expire after 10 seconds with a warning.
## Replaces scattered can_move boolean writes.

var _locks: Dictionary = {}  # { lock_id: timestamp_msec }
const STALE_TIMEOUT_MS: int = 10000  # 10 seconds


func push_lock(lock_id: String) -> void:
	_locks[lock_id] = Time.get_ticks_msec()


## Name-specific check for callers gating on ONE lock (battle-entry funnel, 2026-08-08).
## ⛔ REAPS FIRST. This read the dict directly until 2026-09-12, so the 10-second backstop that
## exists for exactly this hazard protected is_locked()'s 23 callers and not this one. Measured:
## age a lock past STALE_TIMEOUT_MS and has_lock still answered TRUE while is_locked answered
## FALSE — and the only thing that ever cleared it for this reader was an unrelated caller
## happening to run is_locked() and reaping as a side effect.
##
## The consequence is specific: _start_battle_async (GameLoop:4345) DROPS EVERY ENCOUNTER while
## has_lock("world_transition") is true, and that guard was added for the mid-dissolve tween death
## that skips the pop — i.e. the one leak it could not recover from on its own.
func has_lock(lock_id: String) -> bool:
	_reap_stale()
	return _locks.has(lock_id)


## One reaper, so a new reader cannot be added without the backstop. Returns the ids it expired.
func _reap_stale() -> Array:
	if _locks.is_empty():
		return []
	var now := Time.get_ticks_msec()
	var stale: Array = []
	for id in _locks:
		if now - _locks[id] > STALE_TIMEOUT_MS:
			push_warning("[InputLockManager] Stale lock expired: '%s' (held %.1fs)"
				% [id, (now - _locks[id]) / 1000.0])
			stale.append(id)
	for id in stale:
		_locks.erase(id)
	return stale


func pop_lock(lock_id: String) -> void:
	_locks.erase(lock_id)


func pop_all() -> void:
	_locks.clear()


func is_locked() -> bool:
	_reap_stale()
	return not _locks.is_empty()


func get_active_locks() -> Array:
	return _locks.keys()
