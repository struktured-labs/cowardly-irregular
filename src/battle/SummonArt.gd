class_name SummonArt
extends RefCounted

## sprite_manifest.json summon_art, read in its own file so BattleScene (whose intensity keys share manifest field names) never parses the manifest.

static var _cache: Dictionary = {}


## {"figure": path, "circle": path} for a summon ability with art, {} for anything else.
static func for_ability(ability_id: String) -> Dictionary:
	if _cache.is_empty():
		var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
		var section = raw.get("summon_art", {}) if raw is Dictionary else {}
		_cache = section if section is Dictionary and not (section as Dictionary).is_empty() else {"_none": true}
	var entry = _cache.get(ability_id, null)
	if ability_id == "" or ability_id == "circle" or not (entry is Dictionary) or str(entry.get("path", "")) == "":
		return {}
	var circle = _cache.get("circle", {})
	return {"figure": str(entry["path"]), "circle": str(circle.get("path", "")) if circle is Dictionary else ""}
