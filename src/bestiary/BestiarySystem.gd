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

static var _bestiary_cache: Dictionary = {}
static var _monsters_cache: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_monsters_cache = _load_json(MONSTERS_JSON)
	_bestiary_cache = _load_json(BESTIARY_JSON)


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
	_ensure_loaded()


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


static func mark_seen(monster_id: String) -> void:
	if not GameState.game_constants.has("seen_monsters"):
		GameState.game_constants["seen_monsters"] = {}
	GameState.game_constants["seen_monsters"][monster_id] = true


static func get_seen_ids() -> Array:
	var seen: Dictionary = GameState.game_constants.get("seen_monsters", {})
	return seen.keys()


static func discovery_counts() -> Vector2i:
	"""Returns (seen, total_monsters)."""
	_ensure_loaded()
	var seen_count: int = get_seen_ids().size()
	return Vector2i(seen_count, _monsters_cache.size())


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
		})
	out.sort_custom(func(a, b):
		if a.level != b.level:
			return a.level < b.level
		return a.name < b.name
	)
	return out
