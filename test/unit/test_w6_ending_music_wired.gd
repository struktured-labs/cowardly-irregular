extends GutTest

## Each reachable W6 ending branch must declare its own theme (2026-07-29).
##
## The four ending themes were composed, added to the manifest, encoded to OGG
## and shipped in the pck — and nothing played them. world6_chapter3.json
## branched on all four playstyle keys and declared no music in any of them,
## so every ending played on whatever bed happened to be running.
##
## They were unreachable in a second way too: two of the four branches
## (`manual`, `exploiter`) could never fire, because _detect_playstyle tested
## volume before ratio. cowir-ai's PR #187 fixed the classifier, which is what
## made wiring the music worth doing — before that, two of these tracks had no
## reachable consumer even in principle.
##
## That defect ended up with four faces: authored JSON branches that never ran,
## classifier arms that could not return, art, and music nobody could hear.
## This pins the music face.

const CUTSCENE := "res://data/cutscenes/world6_chapter3.json"
const MANIFEST := "res://data/music_manifest.json"

## case key -> the theme composed for it. Not derived: the mapping IS the
## authored intent, and deriving it from a naming convention would let a
## renamed track quietly point an ending at the wrong piece of music.
const EXPECTED := {
	"automator": "cutscene_w6_answer_automation",
	"grinder": "cutscene_w6_answer_grind",
	"exploiter": "cutscene_w6_answer_exploit",
	"manual": "cutscene_w6_answer_manual",
}


func _json(path: String) -> Dictionary:
	var t: String = FileAccess.get_file_as_string(path)
	assert_ne(t, "", "Expected %s to be readable" % path)
	var parsed = JSON.parse_string(t)
	assert_true(parsed is Dictionary, "%s must parse as a Dictionary" % path)
	return parsed if parsed is Dictionary else {}


## Depth-first hunt for the playstyle switch, so this survives the scene being
## restructured around it.
func _find_cases(node) -> Dictionary:
	if node is Dictionary:
		if node.has("cases") and node["cases"] is Dictionary:
			return node["cases"]
		for k in node:
			var found := _find_cases(node[k])
			if not found.is_empty():
				return found
	elif node is Array:
		for v in node:
			var found := _find_cases(v)
			if not found.is_empty():
				return found
	return {}


func test_positive_control_switch_is_found() -> void:
	## An empty cases dict would make every assertion below vacuously true.
	var cases := _find_cases(_json(CUTSCENE))
	assert_false(cases.is_empty(), "the playstyle switch must be locatable in world6_chapter3")
	assert_true(cases.has("default"), "positive control: the switch must carry a default arm")
	assert_gt(cases.size(), 4, "expected all four playstyle arms plus default")


func test_every_ending_branch_declares_its_theme() -> void:
	var cases := _find_cases(_json(CUTSCENE))
	for key in EXPECTED:
		assert_true(cases.has(key), "world6_chapter3 must author a '%s' branch" % key)
		var steps = cases.get(key, [])
		assert_true(steps is Array, "'%s' branch must hold a step array" % key)
		var tracks: Array = []
		for s in steps:
			if s is Dictionary and s.get("type", "") == "play_music":
				tracks.append(str(s.get("track", "")))
		assert_true(tracks.has(EXPECTED[key]),
			"the '%s' ending must play \"%s\" — it is composed, in the manifest and on disk, and without this step the ending plays on whatever bed happened to be running" % [key, EXPECTED[key]])


func test_every_wired_theme_exists_in_the_manifest() -> void:
	## A step naming a track the manifest lacks is a silent no-op, so wiring
	## alone is not enough.
	var man := _json(MANIFEST)
	var tracks = man.get("tracks", man)
	for key in EXPECTED:
		assert_true(tracks.has(EXPECTED[key]),
			"music_manifest must carry \"%s\"" % EXPECTED[key])
