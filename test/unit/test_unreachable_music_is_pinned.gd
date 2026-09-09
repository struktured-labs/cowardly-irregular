extends GutTest

## Music that ships but cannot play, pinned rather than asserted away (2026-09-09).
##
## 11.9 MB of composed audio is in every build with nothing able to reach it.
## That is not a bug to fix by deleting — four of the eight are finished pieces
## for scenes the story lane has not written yet ("Nobody Special", "The Loop
## Completed") — but it must not be invisible either, because the web pck is
## capped near 190 MB and an untracked 12 MB is a cost nobody is deciding to pay.
##
## ⚠️ I PUBLISHED "0 orphans, every track is referenced" EARLIER THE SAME DAY.
## That sweep searched a corpus that INCLUDED data/music_manifest.json — the
## file which, by definition, names every key. It was guaranteed to return zero
## whatever the truth. Two further corpus errors surfaced before this number
## held: test/ made a key look reachable because MY OWN test named it, and
## tools/music_prompts.json did the same. Each was caught by a control probe
## disagreeing with what I expected, never by the result looking wrong.
##
## So this guard checks the cutscene family the CHEAP AND EXACT way — scan
## data/cutscenes/ — instead of re-implementing a corpus heuristic that was
## wrong three times.
##
## Bidirectional, like the loop-agreement ratchet: a NEW unreachable track
## fails, and a pinned one that becomes reachable ALSO fails, so the list
## cannot rot into a stale claim. When the story lane writes these scenes the
## entries drop off and this file eventually deletes itself.

const MANIFEST := "res://data/music_manifest.json"
const CUTSCENE_DIR := "res://data/cutscenes/"

## Composed for scenes that do not exist. Verified 2026-09-09: no cutscene JSON
## names them, and no file matching their scene id exists on disk.
const KNOWN_UNREACHABLE_CUTSCENE_TRACKS: Array[String] = [
	"cutscene_alt_breaker_speed",
	"cutscene_alt_witness_lament",
	"cutscene_w1_conscription",
	"cutscene_w5_deprecated_goblin",
]


func _cutscene_corpus() -> String:
	var out: String = ""
	var d := DirAccess.open(CUTSCENE_DIR)
	assert_not_null(d, "SCOPE control: cannot open %s — the scan would read empty and every track would look unreachable" % CUTSCENE_DIR)
	if d == null:
		return ""
	var n: int = 0
	for f in d.get_files():
		if f.ends_with(".json"):
			out += FileAccess.get_file_as_string(CUTSCENE_DIR + f)
			n += 1
	assert_gt(n, 50, "SCOPE control: only %d cutscene files scanned — a green here would be vacuous" % n)
	return out


func test_cutscene_track_reachability_matches_the_pin() -> void:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	var corpus: String = _cutscene_corpus()

	## Control: a track we KNOW a scene plays must read as reachable, or the
	## scan is broken and every "unreachable" verdict below is meaningless.
	assert_true(corpus.contains("cutscene_w1_mordaine_dissolution"),
		"CONTROL FAILED: a known-played cutscene track is absent from the scan — the corpus is wrong, not the tracks")

	var unreachable: Array[String] = []
	for key in tracks.keys():
		var k: String = str(key)
		if not k.begins_with("cutscene_"):
			continue
		if str((tracks[k] as Dictionary).get("file", "")) == "":
			continue
		if not corpus.contains(k):
			unreachable.append(k)
	unreachable.sort()

	var pinned: Array[String] = KNOWN_UNREACHABLE_CUTSCENE_TRACKS.duplicate()
	pinned.sort()

	var appeared: Array[String] = []
	for k in unreachable:
		if not pinned.has(k):
			appeared.append(k)
	assert_eq(appeared.size(), 0,
		"NEW cutscene music that no scene plays (%d): %s — either wire it into its scene or add it here with the reason. A composed track nothing reaches is silent by construction." % [appeared.size(), appeared])

	var resolved: Array[String] = []
	for k in pinned:
		if not unreachable.has(k):
			resolved.append(k)
	assert_eq(resolved.size(), 0,
		"pinned tracks that a scene now PLAYS (%d): %s — remove them from KNOWN_UNREACHABLE_CUTSCENE_TRACKS so this list cannot rot into a stale claim" % [resolved.size(), resolved])
