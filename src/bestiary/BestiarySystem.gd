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
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return {}
	if not (json.data is Dictionary):
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
	"""All seen monsters as [{id, name, level, stats, flavor, epithet}] sorted
	by level ascending then name."""
	_ensure_loaded()
	var out: Array = []
	for id in get_seen_ids():
		var data: Dictionary = _monsters_cache.get(id, {})
		if data.is_empty():
			continue
		out.append({
			"id": id,
			"name": data.get("name", id),
			"level": data.get("level", 1),
			"stats": data.get("stats", {}),
			"weaknesses": data.get("weaknesses", []),
			"resistances": data.get("resistances", []),
			"flavor": get_flavor(id),
			"epithet": get_epithet(id),
		})
	out.sort_custom(func(a, b):
		if a.level != b.level:
			return a.level < b.level
		return a.name < b.name
	)
	return out
