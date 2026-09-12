extends GutTest

## A masterite scene's `world` field must name the world of the boss its TRIGGER names — the filename is one world below and is not the authority.

const CUTSCENE_DIR := "res://data/cutscenes"

## monsters.json's world vocabulary, which is what a trigger spells. Differs from
## HybridSpriteLoader.WORLD_SUFFIXES at W1 and W5 — do not substitute that one.
const TRIGGER_WORLD := {
	"medieval": 1, "suburban": 2, "steampunk": 3,
	"industrial": 4, "futuristic": 5, "abstract": 6,
}


## scene id -> {world, trigger, want} for every scene whose trigger names a masterite world.
func _masterite_scenes() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(CUTSCENE_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENE_DIR, f]))
		if not (parsed is Dictionary):
			continue
		var trigger: String = str((parsed as Dictionary).get("trigger", ""))
		if not trigger.begins_with("boss_"):
			continue
		var body := trigger.trim_prefix("boss_").trim_suffix("_defeated")
		var parts := body.split("_")
		if parts.size() < 2:
			continue
		var word: String = parts[parts.size() - 1]
		if not TRIGGER_WORLD.has(word):
			continue
		out[f.replace(".json", "")] = {
			"world": int((parsed as Dictionary).get("world", 0)),
			"trigger": trigger,
			"want": int(TRIGGER_WORLD[word]),
		}
	return out


func test_the_trigger_vocabulary_is_complete() -> void:
	assert_eq(TRIGGER_WORLD.size(), 6, "one entry per world")
	var seen: Dictionary = {}
	for v in TRIGGER_WORLD.values():
		seen[v] = true
	assert_eq(seen.size(), 6, "the six worlds must be distinct")
	assert_false(TRIGGER_WORLD.has("digital"),
		"the trigger vocabulary says 'futuristic' for W5; 'digital' is the AUDIO vocabulary and mixing them is how the world lists drifted")


func test_the_scan_finds_the_masterite_family() -> void:
	var s := _masterite_scenes()
	assert_gt(s.size(), 30, "CONTROL: the masterite intro/defeat family is large; found %d" % s.size())
	assert_true(s.has("world3_warden_defeat"), "CONTROL: a known member must be found")
	assert_false(s.has("world1_prologue"), "CONTROL: a non-boss scene must not be swept in")


func test_every_masterite_scene_declares_its_bosss_world() -> void:
	var offenders: Array = []
	for id in _masterite_scenes():
		var e: Dictionary = _masterite_scenes()[id]
		if int(e["world"]) != int(e["want"]):
			offenders.append("%s world:%d but trigger %s is world %d" % [id, int(e["world"]), str(e["trigger"]), int(e["want"])])
	offenders.sort()
	assert_eq(offenders, [],
		("a masterite scene's `world` must be its BOSS's world. The FILENAME is one world below by an old "
		+ "convention and that is fine — the field is not a filename. CutsceneGallery files each entry into "
		+ "_items_by_world by this value, so a wrong one puts the scene under a world the player has not "
		+ "reached. 22 scenes were filed one world low (10 defeat, 12 intro). Offenders: %s") % str(offenders))


## The generic backdrop each world uses when a scene has no specific location of its own.
const WORLD_GENERIC_BACKDROP := {
	1: "cave_entrance", 2: "suburban_neighborhood", 3: "steampunk_workshop",
	4: "industrial_factory", 5: "node_prime", 6: "vertex_village",
}


func test_no_masterite_scene_shows_the_world_below_its_boss() -> void:
	var offenders: Array = []
	var specific := 0
	for id in _masterite_scenes():
		var e: Dictionary = _masterite_scenes()[id]
		var want := int(e["want"])
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s.json" % [CUTSCENE_DIR, id]))
		var bg: String = str((parsed as Dictionary).get("background", "")) if parsed is Dictionary else ""
		if want > 1 and bg == str(WORLD_GENERIC_BACKDROP.get(want - 1, "")):
			offenders.append("%s (boss world %d) shows %s, the world-%d backdrop; set it to %s" % [id, want, bg, want - 1, str(WORLD_GENERIC_BACKDROP.get(want, ""))])
		elif bg != str(WORLD_GENERIC_BACKDROP.get(want, "")):
			specific += 1
	offenders.sort()
	assert_gt(specific, 10,
		"CONTROL: many masterite scenes use a SPECIFIC location (throne_room, suburban_park) rather than their world's generic backdrop — this rule must not be mistaken for 'every scene uses the generic one'")
	assert_eq(offenders, [],
		("a masterite scene must not render the generic backdrop of the world BELOW its boss. The world "
		+ "field and the backdrop slid together on the same 22 scenes, one world low, matching the filename "
		+ "rather than the boss. cowir-adhoc's .296 fix to world3_warden_defeat moved both fields together "
		+ "and is the precedent. This forbids the slid value only — a scene with its own specific location "
		+ "is untouched. Offenders: %s") % str(offenders))


func test_the_gallery_still_reads_this_field() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/CutsceneGallery.gd")
	assert_gt(src.length(), 0, "CONTROL: the gallery source must load")
	assert_true(src.contains("data.get(\"world\", 0)"),
		"CutsceneGallery must still read `world` from the scene JSON — if it stopped, this whole file is pinning a field nothing consumes and should be re-justified or deleted")
	assert_true(src.contains("_items_by_world"),
		"the gallery must still bucket entries by world, which is what makes a wrong value player-visible")
