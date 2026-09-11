extends GutTest

## Intro-side counterpart to test_defeat_cutscene_names_the_boss_that_triggered_it_regression: the aftermath side was repaired, the intro side was never asked.

const DUNGEON_DIR := "res://src/maps/dungeons"
const CUTSCENE_DIR := "res://data/cutscenes"
const MONSTERS_PATH := "res://data/monsters.json"

## Card names that deliberately name the DUNGEON rather than the monsters.json boss. Pinned, not tolerated.
const DUNGEON_FRAMED_CARDS := {
	"world4_assembly_boss": "Warden of the Assembly Core",
	"world5_root_process_boss": "Arbiter of the Root Process",
	"world6_null_chamber_boss": "Curator of the Null Chamber",
}

## Scripts under the dungeon dir that declare a boss_id but are NOT a dungeon instance.
const NOT_A_DUNGEON_INSTANCE := {
	"DragonCave.gd": "base class — the four dragon caves extend it and set their own boss_id",
}

var _monsters: Dictionary


func before_all() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(MONSTERS_PATH))
	_monsters = raw if raw is Dictionary else {}


## boss_id + boss_cutscene_id scraped from each dungeon script, keyed by script name.
func _dungeons() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(DUNGEON_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string("%s/%s" % [DUNGEON_DIR, f])
		var bid := _quoted_after(src, "boss_id")
		var cid := _quoted_after(src, "boss_cutscene_id")
		if bid != "" and cid != "":
			out[f] = {"boss_id": bid, "cutscene": cid}
	return out


func _quoted_after(src: String, field: String) -> String:
	var needle := "%s = \"" % field
	var i := src.find(needle)
	if i < 0:
		return ""
	var start := i + needle.length()
	var end := src.find("\"", start)
	return src.substr(start, end - start) if end > start else ""


func _scene(cid: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [CUTSCENE_DIR, cid]))
	return raw if raw is Dictionary else {}


func _masterite_portraits(scene: Dictionary) -> Array:
	var out: Dictionary = {}
	for step in scene.get("steps", []):
		if not (step is Dictionary):
			continue
		for line in (step as Dictionary).get("lines", []):
			if line is Dictionary:
				var p: String = str((line as Dictionary).get("portrait", ""))
				if p.begins_with("masterite_"):
					out[p] = true
	var keys: Array = out.keys()
	keys.sort()
	return keys


func _card_names(scene: Dictionary) -> Array:
	var out: Array = []
	for step in scene.get("steps", []):
		if step is Dictionary and (step as Dictionary).get("type") == "boss_intro":
			var n: String = str((step as Dictionary).get("name", ""))
			if n != "":
				out.append(n)
	return out


func test_the_dungeon_scan_finds_real_dungeons() -> void:
	var d := _dungeons()
	assert_gt(d.size(), 8, "CONTROL: the dungeon scrape should find most of the dungeon scripts, found %d" % d.size())
	assert_true(d.has("RootProcess.gd"), "CONTROL: a known dungeon with both fields must be found")
	assert_false(d.has("ZzzNotADungeon.gd"), "CONTROL: a fabricated dungeon must not be found")
	for f in d:
		assert_true(_scene(d[f]["cutscene"]).has("steps"),
			"%s dispatches '%s' but that scene did not parse" % [f, d[f]["cutscene"]])


func test_the_scraper_covers_every_script_that_declares_a_boss() -> void:
	var scraped := _dungeons()
	var unscraped: Array = []
	var dir := DirAccess.open(DUNGEON_DIR)
	assert_not_null(dir, "the dungeon dir must open")
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".gd") or scraped.has(f):
			continue
		if FileAccess.get_file_as_string("%s/%s" % [DUNGEON_DIR, f]).contains("boss_id"):
			unscraped.append(f)
	unscraped.sort()
	var excused: Array = NOT_A_DUNGEON_INSTANCE.keys()
	excused.sort()
	assert_eq(unscraped, excused,
		("a script under %s declares a boss_id but the scrape below did not capture it, so it is "
		+ "SILENTLY OUTSIDE every other assert in this file. The scrape reads the literal form "
		+ "`boss_id = \"...\"`; it does not see `var boss_id: String = \"...\"`, a constant, or a "
		+ "computed id — and a miss drops coverage without failing anything. That is the shape that "
		+ "made cowir-battle's ninja guard score 5/5 green against the commit falsifying it. Either "
		+ "teach _quoted_after the new form or excuse the file here with a reason. Unscraped: %s") % [DUNGEON_DIR, str(unscraped)])


func test_every_masterite_dungeon_intro_shows_the_boss_it_spawns() -> void:
	var offenders: Array = []
	var checked := 0
	for f in _dungeons():
		var bid: String = _dungeons()[f]["boss_id"]
		if not bid.begins_with("masterite_"):
			continue
		checked += 1
		var ports := _masterite_portraits(_scene(_dungeons()[f]["cutscene"]))
		if ports.is_empty():
			continue
		if ports != [bid]:
			offenders.append("%s spawns %s but its intro shows %s" % [f, bid, str(ports)])
	assert_gt(checked, 3, "CONTROL: several dungeons must have a masterite boss, saw %d" % checked)
	assert_eq(offenders, [],
		("a dungeon's intro scene must show the masterite it actually spawns. A portrait id is not prose: "
		+ "masterite_arbiter_abstract is 'Arbiter of Function' (W6), a different character from "
		+ "masterite_arbiter_futuristic 'Arbiter of the Benchmark' (W5). RootProcess showed the wrong one "
		+ "while its own aftermath showed the right one. Offenders: %s") % str(offenders))


func test_dungeon_framed_card_names_are_deliberate() -> void:
	var actual: Dictionary = {}
	for f in _dungeons():
		var cid: String = _dungeons()[f]["cutscene"]
		if not DUNGEON_FRAMED_CARDS.has(cid):
			continue
		var names := _card_names(_scene(cid))
		actual[cid] = names[0] if not names.is_empty() else ""
	assert_eq(actual, DUNGEON_FRAMED_CARDS,
		("These three boss_intro cards name the DUNGEON, not the monsters.json boss, and that is a "
		+ "convention rather than drift — three of three masterite dungeons whose card differs do it the "
		+ "same way. DO NOT 'fix' one to match monsters.json: a majority across rows is not a convention, "
		+ "and here the minority IS the convention. The portrait ids are the part that must match the "
		+ "spawned boss, and that is pinned separately above. Found: %s") % str(actual))
