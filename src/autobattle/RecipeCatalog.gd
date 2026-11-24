extends RefCounted
class_name RecipeCatalog

## The autobattle recipes a player can earn by playing manually: data/autobattle_recipes.json.
## Unwired until the autobattle spec is approved. RecipeLedger counts toward these; RecipeMatcher
## (battle lane) decides which recipes a choice counts toward.

const CATALOG_PATH: String = "res://data/autobattle_recipes.json"
const DEFAULT_RARITY: String = "common"

static var _cached: Array = []


static func catalog() -> Array:
	if _cached.is_empty():
		_cached = _load(CATALOG_PATH)
	return _cached


## Entries missing an id, a positive threshold or a rule are dropped with a warning, never half-loaded.
static func _load(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("[RecipeCatalog] Catalog missing: %s" % path)
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("[RecipeCatalog] Catalog root is not a dict: %s" % path)
		return []
	var out: Array = []
	for entry in parsed.get("recipes", []):
		if not (entry is Dictionary) or str(entry.get("id", "")) == "" \
				or int(entry.get("threshold", 0)) <= 0 or not (entry.get("rule") is Dictionary):
			push_warning("[RecipeCatalog] Dropped malformed recipe: %s" % [entry])
			continue
		out.append(entry.duplicate(true))
	return out


static func ids() -> Array[String]:
	var out: Array[String] = []
	for r in catalog():
		out.append(str(r["id"]))
	return out


static func find(id: String) -> Dictionary:
	for r in catalog():
		if str(r["id"]) == id:
			return r.duplicate(true)
	return {}


static func threshold(id: String) -> int:
	return int(find(id).get("threshold", 0))


static func _reset_cache_for_test() -> void:
	_cached = []
