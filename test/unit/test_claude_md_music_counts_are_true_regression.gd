extends GutTest

## CLAUDE.md's music count is a number other lanes quote, and nobody re-derives it.
##
## It read "153 music tracks" from 2026-07-30 until 2026-09-11 — written, note,
## in a commit whose own subject was "plus 10 stale counts". A doc number that
## was corrected once and drifted again will drift a third time; the only thing
## that stops it is a check that measures.
##
## 🔑 THERE ARE THREE TRUE NUMBERS AND THAT IS THE ACTUAL HAZARD, not the drift.
## Two lanes gave different right answers on 2026-09-11 and both were correct:
##
##     165  manifest ENTRIES with a file   battle_brute.ogg is named by five
##                                         keys under the monster-family ruling
##     161  DISTINCT files those name      the honest count of pieces of music
##     163  .ogg in assets/audio/music/    the directory
##
## So this pins all three and requires the doc to name which it means. A single
## unqualified number is what let two correct measurements read as a conflict.

const DOC := "res://CLAUDE.md"
const MANIFEST := "res://data/music_manifest.json"
const MUSIC_DIR := "res://assets/audio/music"


func _doc() -> String:
	var s: String = FileAccess.get_file_as_string(DOC)
	assert_gt(s.length(), 5000, "SCOPE control: CLAUDE.md read back %d chars" % s.length())
	return s


func _measured() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	var files: Dictionary = {}
	var entries: int = 0
	for k in tracks.keys():
		var e: Variant = tracks[k]
		if not (e is Dictionary):
			continue
		var f: String = str((e as Dictionary).get("file", ""))
		if f == "":
			continue
		entries += 1
		files[f] = true

	var on_disk: int = 0
	var d := DirAccess.open(MUSIC_DIR)
	if d != null:
		d.list_dir_begin()
		var n: String = d.get_next()
		while n != "":
			if n.ends_with(".ogg"):
				on_disk += 1
			n = d.get_next()
		d.list_dir_end()
	return {"entries": entries, "distinct": files.size(), "on_disk": on_disk}


func test_control_the_three_counts_are_really_different() -> void:
	## If they ever coincide, this file's whole premise — that an unqualified
	## number is ambiguous — is gone, and the doc can say one number again.
	var m: Dictionary = _measured()
	assert_gt(int(m["entries"]), 100, "SCOPE control: counted %d manifest entries" % m["entries"])
	assert_gt(int(m["on_disk"]), 100, "SCOPE control: counted %d files on disk" % m["on_disk"])
	assert_true(int(m["entries"]) != int(m["distinct"]) or int(m["distinct"]) != int(m["on_disk"]),
		"all three music counts now agree (%s) — the ambiguity this file guards against is gone; the doc may state one number and this test can be retired" % [m])


func test_claude_md_states_every_music_count_it_uses() -> void:
	var doc: String = _doc()
	var m: Dictionary = _measured()
	var missing: Array[String] = []
	for key in ["entries", "distinct", "on_disk"]:
		var n: int = int(m[key])
		if doc.find(str(n)) < 0:
			missing.append("%s=%d" % [key, n])
	assert_eq(missing.size(), 0,
		"CLAUDE.md does not state the measured music count(s) %s — measured now: %s. A stale number here is quoted by other lanes and re-derived by nobody; update the Data line rather than this test" % [missing, m])


func test_the_doc_disambiguates_rather_than_stating_a_bare_number() -> void:
	## ⚠️ THE DELIVERABLE, NOT PERMISSION TO SKIP. The failure mode this file
	## exists for is not "the number is wrong" — it is "the number is unqualified
	## and two correct readings disagree". So the doc must name what it counts;
	## a bare integer, even a true one, reproduces the defect.
	var doc: String = _doc()
	var idx: int = doc.find("music:")
	assert_gt(idx, 0,
		"the Data line no longer introduces its music counts with 'music:' — if it was reworded, keep a label that says WHICH count each number is")
	var window: String = doc.substr(idx, 400)
	for word in ["distinct", "manifest entries"]:
		assert_gt(window.find(word), 0,
			"the music count in CLAUDE.md does not say '%s' — an unqualified number is what made two correct measurements read as a conflict on 2026-09-11" % word)
