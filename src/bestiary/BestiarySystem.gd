extends Node
class_name BestiarySystem

## BestiarySystem — bestiary data + discovery state helpers.
##
## Discovery is authoritative in GameState.game_constants["seen_monsters"]
## (BattleScene writes here via _mark_monster_seen). We do NOT duplicate
## that state — this class just reads it.
##
## Flavor text priority:
##   1. data/bestiary.json -> <id>.flavor  (cowir-story authored)
##   2. data/monsters.json -> <id>.description  (fallback, already shipped)
##
## All APIs are static so callers don't need to instantiate.

const BESTIARY_JSON := "res://data/bestiary.json"
const MONSTERS_JSON := "res://data/monsters.json"
const ENEMY_POOLS_JSON := "res://data/enemy_pools.json"

static var _bestiary_cache: Dictionary = {}
static var _monsters_cache: Dictionary = {}
static var _pools_cache: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_monsters_cache = _load_json(MONSTERS_JSON)
	_bestiary_cache = _load_json(BESTIARY_JSON)
	# Tick 193: pools cache feeds get_pools_for_monster for the bestiary location hint.
	_pools_cache = _load_json(ENEMY_POOLS_JSON)


static func _load_json(path: String) -> Dictionary:
	# Loud-fail shared helper (ticks 28-31 pattern). Each failure mode
	# pushes a distinct warning so a malformed monsters.json /
	# bestiary.json doesn't silently break get_monster_data and
	# get_flavor — bestiary entries vanish, monster sprites fall to
	# generic fallbacks, and the only sign is "?" entries on the
	# bestiary screen.
	if not FileAccess.file_exists(path):
		push_warning("[BestiarySystem] %s not found — entries from this file will return empty" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		push_warning("[BestiarySystem] %s exists but FileAccess.open failed — entries empty" % path)
		return {}
	var raw := f.get_as_text()
	f.close()
	var json := JSON.new()
	var parse_result := json.parse(raw)
	if parse_result != OK:
		push_warning("[BestiarySystem] %s parse error: %s — entries empty" % [path, json.get_error_message()])
		return {}
	if not (json.data is Dictionary):
		push_warning("[BestiarySystem] %s parsed but root is not a Dictionary — entries empty" % path)
		return {}
	return json.data


static func reload() -> void:
	"""Force-reload JSON files (useful after story agent updates bestiary.json)."""
	_loaded = false
	_bestiary_cache.clear()
	_monsters_cache.clear()
	_pools_cache.clear()
	_ensure_loaded()


# Tick 193: title-case a snake_case id so "cave_floor_1" → "Cave Floor 1" (String.capitalize() only does first letter).
static func _titlecase(s: String) -> String:
	if s == "":
		return ""
	var parts: PackedStringArray = s.split("_")
	for i in parts.size():
		if parts[i].length() == 0:
			continue
		parts[i] = parts[i][0].to_upper() + parts[i].substr(1).to_lower()
	return " ".join(parts)


static func get_pools_for_monster(monster_id: String) -> Array:
	"""Return prettified pool keys that contain monster_id (e.g. 'cave_floor_1' → 'Cave Floor 1'). Empty array if not in any pool (Scriptweaver-spawned, boss-only, etc.)."""
	_ensure_loaded()
	if monster_id == "":
		return []
	var out: Array = []
	for pool_id in _pools_cache.keys():
		var monsters: Array = _pools_cache.get(pool_id, [])
		if monsters is Array and monster_id in monsters:
			out.append(_titlecase(str(pool_id)))
	out.sort()
	return out


static func get_monster_data(monster_id: String) -> Dictionary:
	_ensure_loaded()
	return _monsters_cache.get(monster_id, {})


static func get_flavor(monster_id: String) -> String:
	"""Story-authored flavor text, falling back to the base description."""
	_ensure_loaded()
	var entry: Dictionary = _bestiary_cache.get(monster_id, {})
	var flavor: String = entry.get("flavor", "")
	if flavor != "":
		return flavor
	return _monsters_cache.get(monster_id, {}).get("description", "")


static func get_epithet(monster_id: String) -> String:
	"""Optional subtitle from story flavor (e.g. "The Wandering Pulse").
	Returns empty string when not authored."""
	_ensure_loaded()
	return _bestiary_cache.get(monster_id, {}).get("epithet", "")


static func is_seen(monster_id: String) -> bool:
	var seen: Dictionary = GameState.game_constants.get("seen_monsters", {})
	return seen.has(monster_id)


static func mark_seen(monster_id: String, location_id: String = "") -> void:
	# Tick 245: loud-fail on empty / unknown ids so a Combatant with a
	# missing monster_id (Summoner internal, save-side drift, typo'd
	# Scriptweaver spawn) doesn't silently pollute the seen dict.
	# Empty -> reject outright (no valid use case for "" in the bestiary).
	# Unknown id -> WARN but still write, so a story-agent reload that
	# adds the id later still grants the player credit (the tick 244
	# count-filter swallows the noise meanwhile).
	#
	# Tick 260: optional location_id records where the player most
	# recently encountered this monster — fed to BestiaryMenu as the
	# "Last seen: <location>" autobattle-planning hint. Empty string
	# leaves the prior location intact (caller has no map context).
	if monster_id == "":
		push_warning("[BestiarySystem] mark_seen called with empty monster_id — likely a Combatant missing monster_type; skipped")
		return
	_ensure_loaded()
	if not _monsters_cache.has(monster_id):
		push_warning("[BestiarySystem] mark_seen('%s') — id not in monsters.json (typo? renamed? data drift?). Writing anyway in case the id arrives via reload; count filter will exclude it." % monster_id)
	if not GameState.game_constants.has("seen_monsters"):
		GameState.game_constants["seen_monsters"] = {}
	GameState.game_constants["seen_monsters"][monster_id] = true
	if location_id != "":
		if not GameState.game_constants.has("seen_monsters_last_location"):
			GameState.game_constants["seen_monsters_last_location"] = {}
		GameState.game_constants["seen_monsters_last_location"][monster_id] = location_id


static func get_seen_ids() -> Array:
	var seen: Dictionary = GameState.game_constants.get("seen_monsters", {})
	return seen.keys()


# Tick 260: last-known encounter location, prettified for display.
# "" when never recorded (legacy save, Scriptweaver spawn without map
# context, headless test). UI should gate the "Last seen:" line on
# non-empty return.
static func get_last_seen_location(monster_id: String) -> String:
	var locations: Dictionary = GameState.game_constants.get("seen_monsters_last_location", {})
	var raw: String = str(locations.get(monster_id, ""))
	if raw == "":
		return ""
	return _titlecase(raw)


## Tick 146: defeated tracking distinct from seen. Encounter ≠ kill.
## Pre-fix the bestiary showed an entry the moment a monster spawned,
## even if the party fled or wiped. Now defeated is a strict subset
## of seen (you can't kill something you didn't encounter), and the
## bestiary UI can show "?" or grayed entries for seen-but-not-killed.
static func is_defeated(monster_id: String) -> bool:
	var defeated: Dictionary = GameState.game_constants.get("defeated_monsters", {})
	return defeated.has(monster_id)


## Tick 264: per-monster kill milestones. Crossing one fires a Toast
## via GameState.bestiary_kill_milestone signal so grinding gets
## visible reward feedback. Chosen as 10/50/100/500 because:
##   10  — first sense of "I've actually been farming this"
##   50  — established autobattle target
##   100 — round-number trophy
##   500 — extreme grind achievement
## Kept fixed (not data-driven) so the suite can pin the exact list.
const KILL_MILESTONES: Array[int] = [10, 50, 100, 500]


static func mark_defeated(monster_id: String, location_id: String = "") -> void:
	# Tick 245: empty-id guard mirrors mark_seen. mark_seen itself
	# warns for unknown ids — no need to double-warn here.
	# Tick 260: forward location_id through the seen-invariant
	# auto-mark so kill site updates the "last seen here" hint too.
	# Tick 262: increment per-monster kill counter for the bestiary
	# UI ("you've killed X slimes") — autobattle-planning hint that
	# complements the boolean defeated flag.
	if monster_id == "":
		push_warning("[BestiarySystem] mark_defeated called with empty monster_id — skipped")
		return
	# Defeat implies seen — auto-mark to maintain invariant. A monster
	# can only be killed if it was encountered.
	mark_seen(monster_id, location_id)
	if not GameState.game_constants.has("defeated_monsters"):
		GameState.game_constants["defeated_monsters"] = {}
	GameState.game_constants["defeated_monsters"][monster_id] = true
	if not GameState.game_constants.has("defeated_counts"):
		GameState.game_constants["defeated_counts"] = {}
	var counts: Dictionary = GameState.game_constants["defeated_counts"]
	var new_count: int = int(counts.get(monster_id, 0)) + 1
	counts[monster_id] = new_count
	# Tick 264: emit if this kill crossed a milestone exactly. Strict
	# equality so 11/12/etc. don't re-fire (idempotent: each milestone
	# announces exactly once across the entire save).
	if new_count in KILL_MILESTONES:
		_ensure_loaded()
		var data: Dictionary = _monsters_cache.get(monster_id, {})
		var display_name: String = str(data.get("name", monster_id.replace("_", " ").capitalize()))
		GameState.bestiary_kill_milestone.emit(monster_id, display_name, new_count)


static func get_defeated_ids() -> Array:
	var defeated: Dictionary = GameState.game_constants.get("defeated_monsters", {})
	return defeated.keys()


# Tick 262: per-monster kill count for the bestiary UI. Returns 0 for
# never-killed or legacy saves predating the defeated_counts dict
# (mark_defeated initializes the dict lazily). Caller should gate UI
# rendering on > 0 since "Killed: 0" reads worse than absence.
static func get_defeat_count(monster_id: String) -> int:
	var counts: Dictionary = GameState.game_constants.get("defeated_counts", {})
	return int(counts.get(monster_id, 0))


# Tick 263: aggregate kill total across all monsters. Reads from the
# same defeated_counts dict as get_defeat_count so the sum reflects
# whatever credit the player has accrued (including stale ids for
# renamed monsters — they still count as kills the player earned).
# Returns 0 for legacy saves with no defeated_counts dict.
static func total_kills() -> int:
	var counts: Dictionary = GameState.game_constants.get("defeated_counts", {})
	var total: int = 0
	for v in counts.values():
		total += int(v)
	return total


static func defeat_counts() -> Vector2i:
	"""Returns (defeated, total_monsters) — UI display."""
	_ensure_loaded()
	var d: int = _count_known_ids(get_defeated_ids())
	return Vector2i(d, _monsters_cache.size())


static func discovery_counts() -> Vector2i:
	"""Returns (seen, total_monsters)."""
	_ensure_loaded()
	var seen_count: int = _count_known_ids(get_seen_ids())
	return Vector2i(seen_count, _monsters_cache.size())


# Tick 244: filter seen/defeated ids against the live monsters cache
# so a stale id (renamed/removed from monsters.json after save, typo'd
# by Scriptweaver, leftover from a prior schema) doesn't inflate the
# numerator. Pre-fix the bestiary header could show "90/88 seen" if
# 2 ids in the seen dict had been removed from monsters.json — and
# get_seen_entries_sorted silently skipped those rows, so the count
# was inconsistent with what the UI actually rendered.
static func _count_known_ids(ids: Array) -> int:
	var n: int = 0
	for id in ids:
		if _monsters_cache.has(id):
			n += 1
	return n


static func get_seen_entries_sorted() -> Array:
	"""All seen monsters as [{id, name, level, stats, flavor, epithet,
	exp_reward, gold_reward, drops, one_shot_reward}] sorted by level
	ascending then name. Drops + reward fields feed the BestiaryMenu's
	autobattle-loop intel: players need drop rates to design rules like
	'farm slime until 5 bone'."""
	_ensure_loaded()
	var out: Array = []
	for id in get_seen_ids():
		var data: Dictionary = _monsters_cache.get(id, {})
		if data.is_empty():
			continue
		out.append({
			"id": id,
			## Tick 145: prettify id fallback so a monsters.json entry
			## that's missing a "name" field (data drift, custom
			## Scriptweaver enemy, save built against older monsters
			## list) shows as "Cave Rat King" instead of raw
			## "cave_rat_king" in the bestiary list.
			"name": data.get("name", id.replace("_", " ").capitalize()),
			"level": data.get("level", 1),
			"stats": data.get("stats", {}),
			"weaknesses": data.get("weaknesses", []),
			"resistances": data.get("resistances", []),
			"flavor": get_flavor(id),
			"epithet": get_epithet(id),
			"exp_reward": int(data.get("exp_reward", 0)),
			"gold_reward": int(data.get("gold_reward", 0)),
			"drops": data.get("drop_table", []),
			"one_shot_reward": data.get("one_shot_reward", null),
			## Tick 146: defeated flag distinct from seen. UI can show
			## "?" stats for seen-but-not-killed entries.
			"defeated": is_defeated(id),
			# Tick 193: where this monster can be encountered (completionist hint).
			"pools": get_pools_for_monster(id),
			# Tick 260: last-known encounter location ("" if not recorded).
			"last_location": get_last_seen_location(id),
			# Tick 262: how many times the player has killed this enemy.
			"defeat_count": get_defeat_count(id),
		})
	out.sort_custom(func(a, b):
		if a.level != b.level:
			return a.level < b.level
		return a.name < b.name
	)
	return out
