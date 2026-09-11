extends GutTest

## A track in the manifest that nothing asks for is money spent on silence.
##
## 165 authored beds; 8 of them are reached by no path in the game. Finding that
## needed a reachability MODEL, because a literal-only scan reports 51 orphans
## and 43 of those are false: the runtime composes most ids rather than naming
## them. `boss_arbiter_digital` appears nowhere in the repo and is played every
## time you fight that masterite, via BattleScene's "boss_%s_%s".
##
## 🔑 SO EACH COMPOSED FAMILY CITES THE EXPRESSION THAT BUILDS IT, AND THIS TEST
## ASSERTS THE EXPRESSION IS STILL THERE. A hardcoded list of "these are fine"
## would rot the moment a composition site was deleted — the ids would still be
## excused and would now be genuinely unreachable. Citing the source makes the
## excuse expire with the code that earned it.
##
## ⚠️ THE VOCABULARY TRAP IS WHY THE MODEL CANNOT BE GUESSED FROM THE WORLD LIST.
## CLAUDE.md names six worlds, and "digital" is not among them — but
## SoundManager:1699 maps the futuristic world's areas to the suffix "digital",
## so `*_digital` is the live family and `*_futuristic` would be the dead one.
## Checked: zero futuristic-keyed tracks exist, so the corpus is already named
## for the runtime rather than for the design doc. Do not "fix" that.

const MANIFEST := "res://data/music_manifest.json"

## Each entry: id prefix -> the source file and exact expression that composes it.
## If the expression is gone, the family is no longer composed and its members
## must be re-justified rather than silently excused.
const COMPOSED_FAMILIES := {
	"boss_": ["res://src/audio/SoundManager.gd", "\"boss_\" + _current_world_suffix"],
	"danger_": ["res://src/audio/SoundManager.gd", "\"danger_\" + _current_world_suffix"],
	"battle_": ["res://src/audio/SoundManager.gd", "\"battle_\" + _current_world_suffix"],
	"victory_": ["res://src/audio/SoundManager.gd", "\"victory_\" + _current_world_suffix"],
	"village_": ["res://src/audio/SoundManager.gd", "\"village_\" + location_id"],
	"dungeon_": ["res://src/audio/SoundManager.gd", "\"dungeon_\" + world_id"],
}
const MASTERITE_EXPR := ["res://src/battle/BattleScene.gd", "\"boss_%s_%s\" % [masterite_type, world_suffix]"]
const JOB_SPECIAL_EXPR := ["res://src/battle/BattleScene.gd", "\"job_%s_special\" % job_id"]

## The 8, each with WHY it has no consumer and what would retire it.
## This is not permission to stay: the test fails if the set grows OR shrinks.
const KNOWN_UNREACHED := {
	"ambient_digital": "one of the never-played ambient beds — @struktured to delete or wire to cave/forest/village",
	"ambient_industrial": "same decision",
	"ambient_ocean": "same decision",
	"ambient_steampunk": "same decision",
	"cutscene_alt_breaker_speed": "briefed in tools/music_prompts.json shared_tracks (\"Whoever Moves First\"); its scene is the alt_the_breaker novella, which has no cutscene JSON",
	"cutscene_alt_witness_lament": "briefed (\"For the Guardian Who Did Not Choose the Gate\"); same novella, no scene authored",
	"cutscene_w5_deprecated_goblin": "briefed (\"The Loop Completed\"); no W5 scene cues it",
}


func _manifest_ids() -> Array[String]:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	var out: Array[String] = []
	for k in tracks.keys():
		if tracks[k] is Dictionary:
			out.append(str(k))
	out.sort()
	return out


func _files(root: String, ext: String, out: Array[String]) -> void:
	var d := DirAccess.open(root)
	if d == null:
		return
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		var p: String = root + "/" + n
		if d.current_is_dir():
			_files(p, ext, out)
		elif n.ends_with(ext):
			out.append(p)
		n = d.get_next()
	d.list_dir_end()


## Everything that could NAME a track, minus the manifest itself — which would
## match every id and make the whole sweep vacuous.
func _consumer_text() -> String:
	var paths: Array[String] = []
	_files("res://src", ".gd", paths)
	_files("res://data", ".json", paths)
	var parts: PackedStringArray = []
	for p in paths:
		if p.ends_with("music_manifest.json"):
			continue
		parts.append(FileAccess.get_file_as_string(p))
	return "\n".join(parts)


func test_control_the_consumer_corpus_is_real_and_excludes_the_manifest() -> void:
	var text: String = _consumer_text()
	assert_gt(text.length(), 1000000,
		"SCOPE control: consumer corpus is %d chars — too small; every id would look unreached" % text.length())
	## Positive: an id we know is named literally.
	assert_gt(text.find("overworld_medieval"), 0,
		"CONTROL FAILED: overworld_medieval is not in the corpus, so the walk is broken")
	## Negative: the manifest must be EXCLUDED, or every id matches itself.
	assert_eq(text.find("\"tracks\": {"), -1,
		"CONTROL FAILED: music_manifest.json is inside the corpus — every id would match its own manifest entry and the sweep would report zero orphans forever")


func test_every_cited_composition_expression_still_exists() -> void:
	## The excuses must expire with the code that earned them.
	var missing: Array[String] = []
	var checked: int = 0
	var all: Array = COMPOSED_FAMILIES.values().duplicate()
	all.append(MASTERITE_EXPR)
	all.append(JOB_SPECIAL_EXPR)
	for entry in all:
		var src: String = FileAccess.get_file_as_string(str(entry[0]))
		checked += 1
		if src.find(str(entry[1])) < 0:
			missing.append("%s no longer contains %s" % [entry[0], entry[1]])
	assert_gt(checked, 6, "SCOPE control: checked only %d composition sites" % checked)
	assert_eq(missing.size(), 0,
		"a composition site this test relies on is gone (%d): %s — the family it excused is now unreachable and its members are orphans, not exceptions" % [missing.size(), missing])


func _is_reached(id: String, text: String, monsters: Dictionary) -> bool:
	## Literal mention anywhere a consumer could name it.
	if text.find(id) >= 0:
		return true
	for prefix in COMPOSED_FAMILIES.keys():
		if id.begins_with(str(prefix)):
			return true
	if id.begins_with("job_") and id.ends_with("_special"):
		return true
	if id.begins_with("battle_") and monsters.has(id.substr(7)):
		return true
	return false


func test_the_set_of_unreached_beds_has_not_changed() -> void:
	var text: String = _consumer_text()
	var mraw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var mdoc: Dictionary = JSON.parse_string(mraw) as Dictionary
	var monsters: Dictionary = mdoc.get("monsters", mdoc)
	assert_gt(monsters.size(), 50, "SCOPE control: parsed %d monsters" % monsters.size())

	var unreached: Array[String] = []
	for id in _manifest_ids():
		if not _is_reached(id, text, monsters):
			unreached.append(id)
	unreached.sort()

	var added: Array[String] = []
	for id in unreached:
		if not KNOWN_UNREACHED.has(id):
			added.append(id)
	var gone: Array[String] = []
	for id in KNOWN_UNREACHED.keys():
		if not unreached.has(str(id)):
			gone.append(str(id))

	assert_eq(added.size(), 0,
		"authored beds that NOTHING reaches and that are not pinned (%d): %s — a track was added to the manifest with no consumer, which is silence nobody will notice" % [added.size(), added])
	assert_eq(gone.size(), 0,
		"pinned beds that ARE now reached (%s) — they were wired; delete the entries so they are covered like the rest" % [gone])
