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


## A trigger's entries with their ORIGINAL list index: variant n speaks clip voice_<job>_<trigger>_<n>.
func get_trigger_entries(job_id: String, event_kind: String) -> Array:
	if not _data.has(job_id):
		return []
	var voices: Variant = _data[job_id].get("trigger_voices", {})
	if not (voices is Dictionary):
		return []
	return VoiceLines.entries_of((voices as Dictionary).get(event_kind, null))


## A trigger's line texts, in list order.
func get_trigger_lines(job_id: String, event_kind: String) -> Array:
	var out: Array = []
	for e in get_trigger_entries(job_id, event_kind):
		out.append(str(e["line"]))
	return out


## Variant 0's line: what every caller read before lists existed.
func get_trigger_voice(job_id: String, event_kind: String) -> String:
	var lines: Array = get_trigger_lines(job_id, event_kind)
	return "" if lines.is_empty() else str(lines[0])


var _last_variant: Dictionary = {}

## The entries to pick among: eligible tagged lines if any hold, else untagged ones; no context means untagged only.
func eligible_trigger_entries(job_id: String, event_kind: String, ctx: PartyCombatLineContext) -> Array:
	var entries: Array = get_trigger_entries(job_id, event_kind)
	var untagged: Array = entries.filter(func(e): return (e["tags"] as Array).is_empty())
	if ctx == null:
		return untagged
	var tagged: Array = entries.filter(func(e): return not (e["tags"] as Array).is_empty() and VoiceLineTags.is_eligible(e["tags"], ctx))
	return tagged if not tagged.is_empty() else untagged


## {"line", "voice_key"}: a random eligible entry, never the same one twice running.
func pick_trigger_voice(job_id: String, event_kind: String, ctx: PartyCombatLineContext = null) -> Dictionary:
	var entries: Array = eligible_trigger_entries(job_id, event_kind, ctx)
	if entries.is_empty():
		return {"line": "", "voice_key": ""}
	var e: Dictionary = _pick_no_repeat(job_id + "|" + event_kind, entries)
	return {"line": str(e["line"]), "voice_key": VoiceLines.variant_key(event_kind, int(e["index"]))}


## One entry at random, avoiding the ORIGINAL index spoken last time for this key.
func _pick_no_repeat(key: String, entries: Array) -> Dictionary:
	if entries.size() == 1:
		_last_variant[key] = int(entries[0]["index"])
		return entries[0]
	var last: int = int(_last_variant.get(key, -1))
	var pool: Array = entries.filter(func(x): return int(x["index"]) != last)
	if pool.is_empty():
		pool = entries
	var e: Dictionary = pool[randi() % pool.size()]
	_last_variant[key] = int(e["index"])
	return e
