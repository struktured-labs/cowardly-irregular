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
## Wave F B13 fix — non-JSON-safe values (Object refs, NodePath, RIDs) are
## stripped at record() time with a push_warning so they don't silently
## vanish when GameState.to_dict() / JSON.stringify serialises the log.
func record(type: String, summary: String, data: Dictionary = {}) -> void:
	# Engine.has_singleton("GameState") is ALWAYS FALSE for autoloads in Godot 4.
	# Resolve via the main-loop root so playtime stamping actually works.
	var pt: int = 0
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var gs: Node = tree.root.get_node_or_null("GameState")
		if gs != null and "playtime_seconds" in gs:
			pt = int(gs.playtime_seconds)
	var safe_data: Dictionary = _coerce_json_safe(data, type)
	var entry: Dictionary = {
		"t":       int(Time.get_unix_time_from_system()),
		"pt":      pt,
		"type":    type,
		"summary": summary,
		"data":    safe_data,
	}
	_entries.append(entry)
	if _entries.size() > RING_CAP:
		_entries.pop_front()


## Coerce a Dictionary to JSON-safe primitives. Object refs / RIDs / NodePaths
## are dropped with a push_warning; nested dicts/arrays recursively scrubbed.
## This is intentionally permissive — we want to keep as much useful context
## as possible while guaranteeing the result will round-trip through
## JSON.stringify cleanly.
func _coerce_json_safe(data: Dictionary, type: String) -> Dictionary:
	var out: Dictionary = {}
	for key in data.keys():
		var v: Variant = data[key]
		var scrubbed: Variant = _scrub_value(v, str(key), type)
		if scrubbed != null or v == null:
			out[key] = scrubbed
	return out


func _scrub_value(v: Variant, key: String, type: String) -> Variant:
	# Null and primitives pass straight through.
	var t: int = typeof(v)
	if t == TYPE_NIL or t == TYPE_BOOL or t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_STRING or t == TYPE_STRING_NAME:
		# StringName needs explicit conversion for JSON.stringify cleanliness.
		if t == TYPE_STRING_NAME:
			return str(v)
		return v
	if t == TYPE_DICTIONARY:
		return _coerce_json_safe(v as Dictionary, type)
	if t == TYPE_ARRAY:
		var arr: Array = []
		for item in (v as Array):
			var s: Variant = _scrub_value(item, key, type)
			if s != null or item == null:
				arr.append(s)
		return arr
	# Anything else (Object, RID, NodePath, Callable, Signal, etc) is dropped.
	push_warning("[EventLog] dropping non-JSON-safe value at key '%s' (type=%s, event_type=%s)" % [key, t, type])
	return null


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
## Tick 164: also enforces RING_CAP on load (matches record()'s
## cap at line 63-64), int() coerces timestamps (JSON.parse returns
## numerics as float), and floors negative timestamps at 0
## (corrupted save defense — negative timestamps would propagate
## into UI rendering as "X seconds ago" arithmetic).
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
			var copied: Dictionary = item.duplicate(true)
			# Coerce timestamps to int — JSON returns float for numerics.
			# Floor at 0 so a corrupted negative doesn't poison
			# downstream "now - entry.t" arithmetic.
			if copied.has("t"):
				copied["t"] = max(0, int(copied["t"]))
			if copied.has("pt"):
				copied["pt"] = max(0, int(copied["pt"]))
			typed.append(copied)
		else:
			push_warning("[EventLog] restore: skipping non-Dictionary entry: %s" % str(item))
	# Enforce RING_CAP — a save from an older build with looser cap
	# (or a corrupted save with bogus padding) would otherwise leak
	# unbounded into runtime. Drop OLDEST first (pop_front) matching
	# record()'s ring semantics.
	while typed.size() > RING_CAP:
		typed.pop_front()
	_entries = typed
