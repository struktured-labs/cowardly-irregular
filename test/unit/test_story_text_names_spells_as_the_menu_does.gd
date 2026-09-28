extends GutTest

## Villagers said "Raise" and "Fire" after those spells were renamed Anima Reddita and Ignis, so the joke named a spell the player never sees.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const ABILITIES := "res://data/abilities.json"
const SCRIPT_DIRS := ["res://src/maps/villages", "res://src/maps/interiors", "res://src/maps/dungeons"]
const DATA_DIRS := ["res://data/cutscenes", "res://data/quests"]


## Old title -> current display name, for every ability whose name no longer matches its id.
func _renamed() -> Dictionary:
	var ab: Variant = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	var current: Dictionary = {}
	for id in (ab as Dictionary):
		if ab[id] is Dictionary and (ab[id] as Dictionary).has("name"):
			current[str(ab[id]["name"]).to_lower()] = true
	var out: Dictionary = {}
	for id in (ab as Dictionary):
		if not (ab[id] is Dictionary and (ab[id] as Dictionary).has("name")):
			continue
		var old: String = str(id).replace("_", " ").capitalize()
		if old.to_lower() != str(ab[id]["name"]).to_lower() and not current.has(old.to_lower()):
			out[old] = str(ab[id]["name"])
	return out


## A spell named as a spell: "cast/use/learn Raise", or "Fire spell". Case-sensitive, so "use fire" (the element) passes.
func _offences(text: String, renamed: Dictionary) -> Array:
	var out: Array = []
	for old in renamed:
		var re := RegEx.new()
		re.compile("(\\b(cast|casts|casting|use|uses|used|learn|learns|learned)\\s+(a |the |your )?%s\\b)|(\\b%s (spell|magic)\\b)" % [old, old])
		if re.search(text) != null:
			out.append("%s (now %s)" % [old, renamed[old]])
	return out


func _files(dir: String, ext: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(ext):
			out.append("%s/%s" % [dir, f])
	return out


func test_the_renamed_set_is_derived_and_real() -> void:
	var r: Dictionary = _renamed()
	assert_gt(r.size(), 15, "CONTROL: abilities.json should yield the Latin renames, found %d" % r.size())
	assert_eq(str(r.get("Raise", "")), "Anima Reddita", "CONTROL: a known rename must be derived")
	assert_eq(str(r.get("Fire", "")), "Ignis", "CONTROL: a known rename must be derived")


func test_the_matcher_catches_a_spell_and_spares_an_element() -> void:
	var r: Dictionary = _renamed()
	assert_eq(_offences("Please don't use Raise on the graves.", r).size(), 1, "CONTROL: the shipped offence must be caught")
	assert_eq(_offences("Don't hit it with the sword again. Use fire.", r).size(), 0, "CONTROL: an element in lower case is not a spell name")
	assert_eq(_offences("Please don't cast Anima Reddita on the graves.", r).size(), 0, "CONTROL: the current name passes")


func test_no_map_script_names_a_spell_by_its_old_name() -> void:
	var r: Dictionary = _renamed()
	var bad: Array = []
	var scanned := 0
	for dir in SCRIPT_DIRS:
		for path in _files(dir, ".gd"):
			var code: String = GdSource.code_of(path)
			scanned += 1
			for hit in _offences(code, r):
				bad.append("%s: %s" % [str(path).get_file(), hit])
	assert_gt(scanned, 30, "CONTROL: the map scripts must be scanned, saw %d" % scanned)
	assert_true(GdSource.code_of("res://src/maps/villages/GrimhollowVillage.gd").contains("Gravedigger Earl"),
		"CONTROL: village code must survive comment-stripping")
	assert_eq(bad, [], "a villager names a spell the player only knows by its new name — use the menu name: %s" % [bad])


func test_no_story_data_names_a_spell_by_its_old_name() -> void:
	var r: Dictionary = _renamed()
	var bad: Array = []
	var scanned := 0
	for dir in DATA_DIRS:
		for path in _files(dir, ".json"):
			scanned += 1
			for hit in _offences(FileAccess.get_file_as_string(path), r):
				bad.append("%s: %s" % [str(path).get_file(), hit])
	assert_gt(scanned, 100, "CONTROL: cutscenes and quests must be scanned, saw %d" % scanned)
	assert_eq(bad, [], "story text names a spell by a name the menu no longer shows: %s" % [bad])
