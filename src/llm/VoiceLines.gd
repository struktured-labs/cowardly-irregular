class_name VoiceLines
extends RefCounted

## A trigger_voices element is a line or {"line": str, "when": tag|[tags]}; its index n is clip _n either way.


## The spoken text of one element, whichever shape it is.
static func text_of(entry: Variant) -> String:
	if entry is Dictionary:
		return str((entry as Dictionary).get("line", ""))
	return "" if entry == null else str(entry)


## The element's tags; a bare string has none.
static func tags_of(entry: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (entry is Dictionary):
		return out
	var w: Variant = (entry as Dictionary).get("when", null)
	if w is Array:
		for t in w:
			out.append(str(t))
	elif w != null and str(w) != "":
		out.append(str(w))
	return out


## Non-empty entries with their ORIGINAL index, so a filtered pick still names its own clip.
static func entries_of(raw: Variant) -> Array:
	var lines: Array = raw if raw is Array else [raw]
	var out: Array = []
	for n in lines.size():
		var text: String = text_of(lines[n])
		if text == "":
			continue
		out.append({"index": n, "line": text, "tags": tags_of(lines[n])})
	return out


## Clip key suffix for variant n: voice_<job>_<this>.
static func variant_key(event_kind: String, n: int) -> String:
	return event_kind if n == 0 else "%s_%d" % [event_kind, n]


## "1".."n": a small model can answer a number exactly, where it would paraphrase a line.
static func choice_labels(n: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(1, n + 1):
		out.append(str(i))
	return out


## The entry a label names, or {} when the label is not one of them.
static func entry_for_choice(entries: Array, label: String) -> Dictionary:
	if not label.is_valid_int():
		return {}
	var i: int = int(label) - 1
	return entries[i] if i >= 0 and i < entries.size() else {}


## Offered to the LLM: shuffled, minus the last half-pool of lines spoken (`recent` oldest first), so a model's favourite cannot return every other turn.
static func choice_pool(entries: Array, recent: Array) -> Array:
	var window: int = mini(floori(entries.size() / 2.0), recent.size())
	var excluded: Array = recent.slice(recent.size() - window)
	var pool: Array = entries.filter(func(e): return not (int(e["index"]) in excluded))
	if pool.is_empty():
		pool = entries.duplicate()
	pool.shuffle()
	return pool
