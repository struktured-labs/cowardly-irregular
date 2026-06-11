## EventLog — append-only ring buffer of deterministic game facts.
##
## Lives on GameState as `var event_log: EventLog` (set in GameState._ready).
## Rides the existing save path via GameState.to_dict() / from_dict().
##
## Invariants:
##   - Never stores LLM output (ephemeral/cosmetic only).
##   - serialize() / restore() use the typed-array-safe coercion pattern
##     to survive JSON round-trips without silent failures.
##   - Cap enforced on every record() call; oldest entries are dropped first.
##
## Entry schema:
##   { t: int,        # Unix timestamp (seconds)
##     pt: int,       # playtime_seconds cast to int
##     type: String,  # one of TYPE_* constants
##     summary: String,
##     data: Dictionary }

class_name EventLog
extends RefCounted

# ── Public type constants ────────────────────────────────────────────────────
const TYPE_BOSS_DEFEAT    := "boss_defeat"
const TYPE_PARTY_WIPE     := "party_wipe"
const TYPE_AREA_ENTERED   := "area_entered"
const TYPE_ITEM_OBTAINED  := "item_obtained"
const TYPE_LEVEL_UP       := "level_up"
const TYPE_STORY_FLAG     := "story_flag"
const TYPE_CUSTOM         := "custom"

# ── Configuration ─────────────────────────────────────────────────────────────
const RING_CAP: int = 50  # Maximum number of entries retained.

# ── Internal storage ─────────────────────────────────────────────────────────
var _entries: Array[Dictionary] = []


# ── Core API ─────────────────────────────────────────────────────────────────

## Append a new event.  Oldest entry is dropped when the cap is exceeded.
## `data` is shallow-duplicated to prevent external mutation.
func record(type: String, summary: String, data: Dictionary = {}) -> void:
	var pt: int = 0
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		pt = int(gs.playtime_seconds)
	var entry: Dictionary = {
		"t":       int(Time.get_unix_time_from_system()),
		"pt":      pt,
		"type":    type,
		"summary": summary,
		"data":    data.duplicate(),
	}
	_entries.append(entry)
	if _entries.size() > RING_CAP:
		_entries.pop_front()


## Return the `n` most-recent entries (newest last, same order as stored).
## If n <= 0 or n >= size, the full array is returned.
func recent(n: int = RING_CAP) -> Array[Dictionary]:
	if n <= 0 or n >= _entries.size():
		return _entries.duplicate()
	var out: Array[Dictionary] = []
	var start: int = _entries.size() - n
	for i in range(start, _entries.size()):
		out.append(_entries[i])
	return out


## Convenience alias — identical to recent(); kept for semantic clarity at call
## sites that emphasise the "last N entries" concept.
func recent_entries(n: int = RING_CAP) -> Array[Dictionary]:
	return recent(n)


## Return all entries matching `type` (oldest first).
func by_type(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _entries:
		if entry.get("type", "") == type:
			out.append(entry)
	return out


## Return the total number of entries currently held.
func size() -> int:
	return _entries.size()


## Remove all entries (called by GameState.reset_game_state).
func clear() -> void:
	_entries.clear()


# ── Save / Restore ────────────────────────────────────────────────────────────

## Produce a JSON-safe Array for inclusion in GameState.to_dict().
func serialize() -> Array:
	return _entries.duplicate(true)


## Restore from a raw value loaded by JSON.parse (generic Array or null).
## Uses the typed-array-safe coercion pattern to avoid silent SCRIPT ERRORs
## when JSON returns untyped Arrays instead of Array[Dictionary].
func restore(raw: Variant) -> void:
	_entries.clear()
	if raw == null:
		return
	if not (raw is Array):
		push_warning("[EventLog] restore: expected Array, got %s — skipping." % typeof(raw))
		return
	var typed: Array[Dictionary] = []
	for item in (raw as Array):
		if item is Dictionary:
			typed.append(item.duplicate(true))
		else:
			push_warning("[EventLog] restore: skipping non-Dictionary entry: %s" % str(item))
	_entries = typed
