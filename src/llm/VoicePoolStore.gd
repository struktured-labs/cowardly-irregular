class_name VoicePoolStore
extends RefCounted

## One ready line per speaker + trigger. Text and voice here; audio lives in VoiceCache under the same voice/rev/text key.

const VERSION := 1
const DEFAULT_PATH := "user://voice_cache/pool.json"

var path: String
var slots: Dictionary = {}


func _init(p: String = DEFAULT_PATH) -> void:
	path = p


static func slot_key(speaker: String, trigger: String) -> String:
	return "%s|%s" % [speaker, trigger]


func has_line(speaker: String, trigger: String) -> bool:
	return slots.has(slot_key(speaker, trigger))


func peek(speaker: String, trigger: String) -> Dictionary:
	return (slots.get(slot_key(speaker, trigger), {}) as Dictionary).duplicate()


func put(speaker: String, trigger: String, line: String, voice: String, rev: int) -> void:
	slots[slot_key(speaker, trigger)] = {"line": line, "voice": voice, "rev": rev}


func take(speaker: String, trigger: String) -> Dictionary:
	var k := slot_key(speaker, trigger)
	var slot: Dictionary = (slots.get(k, {}) as Dictionary).duplicate()
	slots.erase(k)
	return slot


func lines_for(speaker: String) -> Array[String]:
	var out: Array[String] = []
	for k in slots.keys():
		if str(k).begins_with(speaker + "|"):
			out.append(str((slots[k] as Dictionary).get("line", "")))
	return out


## A slot whose voice was recast or uncast holds audio in a voice the speaker no longer has.
func drop_stale(cast: Dictionary) -> int:
	var dropped := 0
	for k in slots.keys():
		var speaker: String = str(k).split("|")[0]
		var v: Dictionary = cast.get(speaker, {})
		var slot: Dictionary = slots[k]
		if v.is_empty() or str(v.get("voice", "")) != str(slot.get("voice", "")) or int(v.get("rev", -1)) != int(slot.get("rev", -2)):
			slots.erase(k)
			dropped += 1
	return dropped


func save() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"version": VERSION, "slots": slots}))
	f.close()
	return true


func load_from_disk() -> void:
	slots = {}
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or int(d.get("version", 0)) != VERSION or not (d.get("slots") is Dictionary):
		return
	for k in d["slots"]:
		var slot = d["slots"][k]
		if slot is Dictionary and str(slot.get("line", "")) != "":
			slots[str(k)] = {"line": str(slot["line"]), "voice": str(slot.get("voice", "")), "rev": int(slot.get("rev", 0))}


## Whole-word, case-insensitive. A pooled line was written before its battle, so it may name no one in it.
static func names_anyone(line: String, names: Array) -> bool:
	var hay := " %s " % line.to_lower()
	for n in names:
		var who := str(n).strip_edges().to_lower()
		if who == "":
			continue
		var re := RegEx.new()
		re.compile("(^|[^a-z0-9])" + _escape(who) + "($|[^a-z0-9])")
		if re.search(hay) != null:
			return true
	return false


static func _escape(s: String) -> String:
	var out := ""
	for c in s:
		out += ("\\" + c) if ".^$*+?()[]{}|\\".contains(c) else c
	return out
