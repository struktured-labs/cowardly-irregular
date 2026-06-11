## LLMContext — compact game-state metadata builder for LLM prompts.
##
## Static helpers only — no node state, no signals.  Call build() or build_json()
## from any script to get a ready-to-inject context snapshot.
##
## Output shape (~0.5–1.5 KB):
##   {
##     party: [ { name, job, lv, hp_pct } × ≤4 ],
##     progress: { world, worlds_unlocked, bosses:[ids], corruption, volatility },
##     recent_events: [ last ~8 EventLog summaries ]
##   }
##
## A budget guard truncates events → party detail if the JSON exceeds ~2 KB,
## keeping prompt injection predictable regardless of log size.
##
## Safety notes:
##   - Fields are deliberately cosmetic-safe: nothing that would tempt a caller
##     to treat LLM output as authoritative game state.
##   - All numeric fields are clamped/rounded to avoid floating-point noise.
##   - Missing or malformed GameState fields are handled gracefully (defaults).

class_name LLMContext
extends RefCounted

# ── Budget constants ───────────────────────────────────────────────────────────
const MAX_EVENTS_FULL:    int = 8    # Events included before budget check.
const MAX_EVENTS_TRIMMED: int = 4    # Events retained after budget trim.
const MAX_PARTY_FULL:     int = 4    # Max party members in full detail.
const MAX_JSON_BYTES:     int = 2048 # ~2 KB JSON budget guard.


# ── Public API ────────────────────────────────────────────────────────────────

## Build a context Dictionary from the current GameState (must be an autoload).
## Returns an empty Dictionary if GameState is unavailable.
static func build() -> Dictionary:
	if not Engine.has_singleton("GameState"):
		push_warning("[LLMContext] GameState singleton not found — returning empty context.")
		return {}

	var gs: Object = Engine.get_singleton("GameState")
	var ctx: Dictionary = {}

	# Party
	ctx["party"] = _build_party(gs)

	# Progress
	ctx["progress"] = _build_progress(gs)

	# Recent events (from EventLog on GameState, if present)
	ctx["recent_events"] = _build_events(gs)

	# Apply budget guard — trim events first, then party detail if still over.
	var json_str: String = JSON.stringify(ctx)
	if json_str.length() > MAX_JSON_BYTES:
		ctx["recent_events"] = _trim_events(ctx["recent_events"])
		json_str = JSON.stringify(ctx)

	if json_str.length() > MAX_JSON_BYTES:
		# Last resort: strip party jobs and trim to 2 members.
		ctx["party"] = _trim_party(ctx["party"])

	return ctx


## Build a compact JSON string suitable for direct prompt injection.
## Returns "{}" if GameState is unavailable.
static func build_json() -> String:
	var ctx: Dictionary = build()
	if ctx.is_empty():
		return "{}"
	return JSON.stringify(ctx)


# ── Internal builders ─────────────────────────────────────────────────────────

## Helper: read a property from an Object, returning `default_val` if null/absent.
## Object.get() in GDScript 4 accepts only one argument, so we check for null.
static func _obj_get(obj: Object, prop: String, default_val: Variant) -> Variant:
	var val: Variant = obj.get(prop)
	if val == null:
		return default_val
	return val


static func _build_party(gs: Object) -> Array:
	var raw_party: Variant = gs.get("player_party")
	var party_list: Array = []
	if not (raw_party is Array):
		return party_list
	var count: int = mini((raw_party as Array).size(), MAX_PARTY_FULL)
	for i in range(count):
		var member: Variant = (raw_party as Array)[i]
		if not (member is Dictionary):
			continue
		var d: Dictionary = member as Dictionary
		var max_hp: float = float(d.get("max_hp", 1))
		if max_hp <= 0.0:
			max_hp = 1.0
		var hp_pct: int = int(round(float(d.get("current_hp", max_hp)) / max_hp * 100.0))
		hp_pct = clampi(hp_pct, 0, 100)
		party_list.append({
			"name": str(d.get("name", "?")),
			"job":  str(d.get("job",  "?")),
			"lv":   int(d.get("level", 1)),
			"hp_pct": hp_pct,
		})
	return party_list


static func _build_progress(gs: Object) -> Dictionary:
	# Collect defeated boss ids from story_flags (keys matching "*_boss_defeated").
	var raw_flags: Variant = gs.get("story_flags")
	var story_flags: Dictionary = raw_flags as Dictionary if raw_flags is Dictionary else {}
	var bosses: Array[String] = []
	for key in story_flags.keys():
		if str(key).ends_with("_boss_defeated") and story_flags[key] == true:
			bosses.append(str(key))

	var raw_world: Variant    = gs.get("current_world")
	var raw_unlocked: Variant = gs.get("worlds_unlocked")
	var raw_corrupt: Variant  = gs.get("corruption_level")
	var raw_volatil: Variant  = gs.get("macro_volatility")

	return {
		"world":           int(raw_world)    if raw_world    != null else 1,
		"worlds_unlocked": int(raw_unlocked) if raw_unlocked != null else 1,
		"bosses":          bosses,
		"corruption":      snappedf(float(raw_corrupt) if raw_corrupt != null else 0.0, 0.01),
		"volatility":      snappedf(float(raw_volatil) if raw_volatil != null else 0.0, 0.01),
	}


static func _build_events(gs: Object) -> Array:
	# EventLog is a RefCounted stored directly on gs.
	var log: Variant = gs.get("event_log")
	if log == null:
		return []
	var log_obj: Object = log as Object
	if log_obj == null or not log_obj.has_method("recent"):
		return []
	var entries: Variant = log_obj.call("recent", MAX_EVENTS_FULL)
	if not (entries is Array):
		return []
	var summaries: Array = []
	for entry in (entries as Array):
		if entry is Dictionary:
			summaries.append(str((entry as Dictionary).get("summary", "")))
	return summaries


static func _trim_events(events: Array) -> Array:
	if events.size() <= MAX_EVENTS_TRIMMED:
		return events
	return events.slice(events.size() - MAX_EVENTS_TRIMMED, events.size())


static func _trim_party(party: Array) -> Array:
	# Minimal fallback: keep first 2 members, drop job field.
	var trimmed: Array = []
	var count: int = mini(party.size(), 2)
	for i in range(count):
		var m: Variant = party[i]
		if m is Dictionary:
			var d: Dictionary = m as Dictionary
			trimmed.append({"name": d.get("name", "?"), "lv": d.get("lv", 1), "hp_pct": d.get("hp_pct", 100)})
	return trimmed
