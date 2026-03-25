extends Node

## InputLockManager — centralized movement lock system.
## Push named locks to freeze player, pop to unfreeze.
## Stale locks auto-expire after 10 seconds with a warning.
## Replaces scattered can_move boolean writes.

var _locks: Dictionary = {}  # { lock_id: timestamp_msec }
const STALE_TIMEOUT_MS: int = 10000  # 10 seconds


func push_lock(lock_id: String) -> void:
	_locks[lock_id] = Time.get_ticks_msec()


func pop_lock(lock_id: String) -> void:
	_locks.erase(lock_id)


func pop_all() -> void:
	_locks.clear()


func is_locked() -> bool:
	if _locks.is_empty():
		return false
	# Auto-expire stale locks
	var now = Time.get_ticks_msec()
	var stale: Array = []
	for id in _locks:
		if now - _locks[id] > STALE_TIMEOUT_MS:
			push_warning("[InputLockManager] Stale lock expired: '%s' (held %.1fs)" % [id, (now - _locks[id]) / 1000.0])
			stale.append(id)
	for id in stale:
		_locks.erase(id)
	return not _locks.is_empty()


func get_active_locks() -> Array:
	return _locks.keys()
