extends GutTest

## The Rogue is never gendered (struktured: "unknown for whole game"), yet the Lockward's bestiary entry said "The Rogue watches. She has always watched."

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const DATA_DIR := "res://data"
const SRC_DIR := "res://src"
const PRONOUN := "\\b(he|she|him|her|his|hers|himself|herself)\\b"


## A sentence whose SUBJECT is the Rogue and that names nobody else, so a pronoun near it can only mean the Rogue.
func _rogue_is_sole_subject(sentence: String) -> bool:
	var s: String = sentence.strip_edges().trim_prefix("*").trim_prefix("\"").strip_edges()
	if not (s.begins_with("The Rogue") or s.begins_with("Rogue")):
		return false
	var rest: String = s.trim_prefix("The Rogue").trim_prefix("Rogue")
	var caps := RegEx.new()
	caps.compile("(?<![.!?]\\s)(?<!^)\\b[A-Z][a-z]+")
	for m in caps.search_all(rest):
		if m.get_start() > 1:
			return false
	return true


## Every gendered reference to the Rogue in one piece of text: in the Rogue's own sentence, or opening the next one.
func _offences(text: String) -> Array:
	var out: Array = []
	var split := RegEx.new()
	split.compile("[^.!?\\n]+[.!?]*")
	var sents: Array = []
	for m in split.search_all(text):
		if m.get_string().strip_edges() != "":
			sents.append(m.get_string().strip_edges())
	var pro := RegEx.new()
	pro.compile("(?i)" + PRONOUN)
	var opens := RegEx.new()
	opens.compile("(?i)^\\W*" + PRONOUN)
	for i in sents.size():
		if not _rogue_is_sole_subject(str(sents[i])):
			continue
		if pro.search(str(sents[i])) != null:
			out.append(str(sents[i]))
		elif i + 1 < sents.size() and opens.search(str(sents[i + 1])) != null:
			out.append("%s %s" % [sents[i], sents[i + 1]])
	return out


func _strings(v: Variant, out: Array) -> void:
	if v is String:
		out.append(v)
	elif v is Array:
		for x in v:
			_strings(x, out)
	elif v is Dictionary:
		for k in v:
			_strings(v[k], out)


func _files(dir: String, ext: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(ext):
			out.append("%s/%s" % [dir, f])
	for sub in d.get_directories():
		_files("%s/%s" % [dir, sub], ext, out)


func test_the_matcher_catches_the_shipped_line_and_spares_other_people() -> void:
	assert_eq(_offences("The Rogue watches. She has always watched.").size(), 1, "CONTROL: the shipped offence must be caught")
	assert_eq(_offences("The Rogue's line is the counter-read — she is the one who sees it.").size(), 1, "CONTROL: same-sentence form")
	assert_eq(_offences("The Rogue handed Mordaine the letter. She read it twice.").size(), 0, "another person named: the pronoun may be theirs")
	assert_eq(_offences("The Rogue watches, and always has.").size(), 0, "CONTROL: the rewrite passes")
	assert_eq(_offences("The Cleric stepped forward. She didn't speak.").size(), 0, "the Cleric is she by canon")


func test_no_data_file_genders_the_rogue() -> void:
	var paths: Array = []
	_files(DATA_DIR, ".json", paths)
	assert_gt(paths.size(), 200, "CONTROL: the data corpus must be scanned, saw %d" % paths.size())
	var bad: Array = []
	for p in paths:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		var texts: Array = []
		_strings(parsed, texts)
		for t in texts:
			for hit in _offences(str(t)):
				bad.append("%s: %s" % [str(p).get_file(), hit])
	assert_eq(bad, [], "the Rogue is never he or she; name them or rephrase: %s" % [bad])


func test_no_script_string_genders_the_rogue() -> void:
	var paths: Array = []
	_files(SRC_DIR, ".gd", paths)
	assert_gt(paths.size(), 200, "CONTROL: the script corpus must be scanned, saw %d" % paths.size())
	var lit := RegEx.new()
	lit.compile("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var bad: Array = []
	for p in paths:
		for m in lit.search_all(GdSource.code_of(p)):
			for hit in _offences(m.get_string(1)):
				bad.append("%s: %s" % [str(p).get_file(), hit])
	assert_eq(bad, [], "the Rogue is never he or she in a scripted line: %s" % [bad])
