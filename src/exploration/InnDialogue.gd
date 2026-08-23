class_name InnDialogue
extends RefCounted

## Per-village innkeeper lines from data/inn_dialogue.json; empty result = caller keeps its own text.

const DIALOGUE_PATH := "res://data/inn_dialogue.json"

## Spoken standing at the desk; the rest transaction has its own kinds below.
const AMBIENT_KINDS := ["greeting", "farewell"]

## rest_prompt is the ONLY kind carrying a format specifier — one %d, the cost.
const COST_KIND := "rest_prompt"

static var _villages: Dictionary = {}
static var _loaded: bool = false
static var _load_error: String = ""


## Loud on a malformed file, quiet on a village that simply has no entry -- absence is normal.
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DIALOGUE_PATH):
		_load_error = "no inn dialogue at %s" % DIALOGUE_PATH
		push_warning("[INNDLG] %s" % _load_error)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DIALOGUE_PATH))
	if not (parsed is Dictionary):
		_load_error = "%s is not a JSON object" % DIALOGUE_PATH
		push_warning("[INNDLG] %s" % _load_error)
		return
	var villages = parsed.get("villages")
	if not (villages is Dictionary):
		_load_error = "%s has no 'villages' object" % DIALOGUE_PATH
		push_warning("[INNDLG] %s" % _load_error)
		return
	_villages = villages


## "harmonia_village" -> "harmonia": the game keys maps, the JSON keys villages.
static func village_key(map_id: String) -> String:
	return map_id.trim_suffix("_village")


static func lines_for(map_id: String) -> Dictionary:
	_ensure_loaded()
	var village = _villages.get(village_key(map_id), {})
	return village if village is Dictionary else {}


## "" when this village authored nothing, which is the caller's signal to keep its own text.
static func line(map_id: String, kind: String) -> String:
	return str(lines_for(map_id).get(kind, ""))


## Formatted with the live cost. Returns "" rather than a half-substituted string when the
## authored line lacks its %d, so a data typo degrades to the generic prompt instead of showing one.
static func cost_line(map_id: String, cost: int) -> String:
	var raw: String = line(map_id, COST_KIND)
	if raw == "" or raw.count("%d") != 1:
		return ""
	return raw % cost


## Speaker-prefixed ambient lines, in AMBIENT_KINDS order; empty when this village authored none.
static func ambient_lines(map_id: String, speaker: String) -> Array:
	var entry: Dictionary = lines_for(map_id)
	var out: Array = []
	for kind in AMBIENT_KINDS:
		var text: String = str(entry.get(kind, ""))
		if text != "":
			out.append(speaker + ": " + text)
	return out


static func village_keys() -> Array:
	_ensure_loaded()
	return _villages.keys()
