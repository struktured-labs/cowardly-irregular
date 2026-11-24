extends GutTest
## 2026-11-24 (cowir-story, found by cowir-sfx 27209): Castle Harmonia's boss signed its lines "Warden: '...'" while five Masterites
## are named "Warden of ...", so two different characters shared one speaker label (and, voiced, would be two voices under one name).
## A boss's speaker label may not be another boss's name, or the leading words of one.

const PARTY_LABELS := ["Hero"]


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _collect(x: Variant, boss: String, re: RegEx, out: Dictionary) -> void:
	if x is String:
		var m := re.search(x)
		if m != null:
			var label := m.get_string(1)
			if not out.has(label):
				out[label] = {}
			out[label][boss] = true
	elif x is Array:
		for i in x:
			_collect(i, boss, re, out)
	elif x is Dictionary:
		for k in x:
			if not str(k).begins_with("_") and not (str(k) in ["persona", "display_name"]):
				_collect(x[k], boss, re, out)


func _labels() -> Dictionary:
	var re := RegEx.new()
	re.compile("^([A-Z][A-Za-z' ,]{1,48}): ")
	var out := {}
	var monsters := _json("res://data/monsters.json")
	for id in monsters:
		var row: Variant = monsters[id]
		if row is Dictionary and row.get("dialogue") is Dictionary:
			var persona := str(row.get("boss_llm_persona_id", ""))
			_collect(row["dialogue"], persona if persona != "" else str(id), re, out)
	var dialogue := _json("res://data/boss_dialogue.json")
	for id in dialogue:
		if dialogue[id] is Dictionary:
			_collect(dialogue[id], str(id), re, out)
	return out


func _boss_names() -> Dictionary:
	var out := {}
	var monsters := _json("res://data/monsters.json")
	for id in monsters:
		var row: Variant = monsters[id]
		if row is Dictionary and (bool(row.get("boss", false)) or bool(row.get("miniboss", false))):
			var persona := str(row.get("boss_llm_persona_id", ""))
			out[persona if persona != "" else str(id)] = str(row.get("name", ""))
	return out


static func _names_it(label: String, name: String) -> bool:
	return name == label or name.begins_with(label + " ") or name.begins_with("The " + label + " ")


func test_no_boss_speaks_under_another_bosss_name() -> void:
	var labels := _labels()
	var names := _boss_names()
	assert_gt(labels.size(), 30, "CONTROL: the speaker labels were read from both sources")
	assert_gt(names.size(), 30, "CONTROL: the bosses' names were read")
	assert_true(_names_it("Warden", "Warden of the Old Guard"), "CONTROL: a bare label names a boss whose name it begins")
	var borrowed: Array = []
	for label in labels:
		if label in PARTY_LABELS:
			continue
		for speaker in labels[label]:
			for other in names:
				if other != speaker and not labels[label].has(other) and _names_it(label, names[other]):
					borrowed.append("%s speaks as '%s', which names %s (%s)" % [speaker, label, other, names[other]])
	assert_eq(borrowed, [], "two characters under one speaker label")
