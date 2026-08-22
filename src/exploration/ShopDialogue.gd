class_name ShopDialogue
extends RefCounted

## Per-village shopkeeper lines from data/shopkeeper_dialogue.json; empty result = caller keeps its own text.

const DIALOGUE_PATH := "res://data/shopkeeper_dialogue.json"

## ShopType int -> the JSON's shop key. ShopInterior/ShopScene/VillageShop all declare the same ordering.
const SHOP_TYPE_KEYS := {0: "item", 1: "black_magic", 2: "white_magic", 3: "blacksmith"}

## The kinds a keeper NPC can speak standing in the shop; buy/sell belong to ShopScene's toast.
const AMBIENT_KINDS := ["greeting", "browse", "farewell"]

static var _villages: Dictionary = {}
static var _loaded: bool = false
static var _load_error: String = ""


## Loud on a malformed file, quiet on a village that simply has no entry -- absence is normal.
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DIALOGUE_PATH):
		_load_error = "no shopkeeper dialogue at %s" % DIALOGUE_PATH
		push_warning("[SHOPDLG] %s" % _load_error)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DIALOGUE_PATH))
	if not (parsed is Dictionary):
		_load_error = "%s is not a JSON object" % DIALOGUE_PATH
		push_warning("[SHOPDLG] %s" % _load_error)
		return
	var villages = parsed.get("villages")
	if not (villages is Dictionary):
		_load_error = "%s has no 'villages' object" % DIALOGUE_PATH
		push_warning("[SHOPDLG] %s" % _load_error)
		return
	_villages = villages


## "harmonia_village" -> "harmonia": the game keys maps, the JSON keys villages.
static func village_key(map_id: String) -> String:
	return map_id.trim_suffix("_village")


static func lines_for(map_id: String, shop_type: int) -> Dictionary:
	_ensure_loaded()
	var village = _villages.get(village_key(map_id), {})
	if not (village is Dictionary):
		return {}
	var shop_key: String = str(SHOP_TYPE_KEYS.get(shop_type, ""))
	if shop_key == "":
		return {}
	var entry = village.get(shop_key, {})
	return entry if entry is Dictionary else {}


## Speaker-prefixed ambient lines, in AMBIENT_KINDS order; empty when this village authored none.
static func ambient_lines(map_id: String, shop_type: int, speaker: String) -> Array:
	var entry: Dictionary = lines_for(map_id, shop_type)
	var out: Array = []
	for kind in AMBIENT_KINDS:
		var line: String = str(entry.get(kind, ""))
		if line != "":
			out.append(speaker + ": " + line)
	return out


static func village_keys() -> Array:
	_ensure_loaded()
	return _villages.keys()
