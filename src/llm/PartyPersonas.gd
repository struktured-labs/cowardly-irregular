## Autoload singleton — loads data/job_personas.json on _ready; serves persona, signature_phrases, and per-event scripted fallback lines for the party LLM dialogue hook.
extends Node

const DATA_PATH: String = "res://data/job_personas.json"

var _data: Dictionary = {}
var _loaded: bool = false


func _ready() -> void:
	_load_data()


func _load_data() -> void:
	if _loaded:
		return
	var raw: String = FileAccess.get_file_as_string(DATA_PATH)
	if raw.is_empty():
		push_warning("[PartyPersonas] %s missing — LLM party dialogue will use empty personas" % DATA_PATH)
		_loaded = true
		return
	var parsed: Variant = JSON.parse_string(raw)
	# Tick 345: distinguish parse-error from non-Dict root. Pre-fix both
	# arms fell into one push_warning ("did not parse as a Dictionary"),
	# misreporting a JSON syntax error as a root-type error. Mirrors
	# the precision fix in BossDialogue._load_data.
	if parsed == null:
		push_warning("[PartyPersonas] %s parse error — file is not valid JSON (hand-edit broke syntax? truncated write?)" % DATA_PATH)
		_loaded = true
		return
	if not (parsed is Dictionary):
		push_warning("[PartyPersonas] %s parsed but root is not a Dictionary (got %s) — file shape changed; personas will be empty" % [DATA_PATH, typeof(parsed)])
		_loaded = true
		return
	var jobs: Variant = (parsed as Dictionary).get("jobs", {})
	if jobs is Dictionary:
		_data = jobs as Dictionary
	_loaded = true


func has_persona(job_id: String) -> bool:
	return _data.has(job_id)


func get_persona(job_id: String) -> String:
	if not _data.has(job_id):
		return ""
	return str(_data[job_id].get("persona", ""))


func get_signature_phrases(job_id: String) -> Array:
	if not _data.has(job_id):
		return []
	var arr: Variant = _data[job_id].get("signature_phrases", [])
	return arr as Array if arr is Array else []


## Returns a single fallback line for the (job_id, event_kind) pair, "" if missing.
func get_trigger_voice(job_id: String, event_kind: String) -> String:
	if not _data.has(job_id):
		return ""
	var voices: Variant = _data[job_id].get("trigger_voices", {})
	if not (voices is Dictionary):
		return ""
	return str((voices as Dictionary).get(event_kind, ""))
