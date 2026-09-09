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
## 🔑 MEASURED 2026-09-09, and it is why the heuristic is not used here at all.
## The same sweep, varying only which DEFINER files sit in the consumer corpus:
##
##     both definers in corpus       ->  0 unreachable   <- what I published
##     music_manifest excluded       ->  8
##     BOTH manifests excluded       ->  9
##     direct consumer tracing       -> 11               <- the true answer
##
## Two lessons, and the second is the one that matters. (1) "Exclude the
## definer" is not a single step: audio keys have TWO definers, and removing
## one still inflated the answer. (2) Even with a PERFECT corpus the heuristic
## stops at 9, because ambient_cave and ambient_forest ARE named in
## OverworldScene — by play_ambient, which reads the SFX manifest and never
## looks here. A string search can only ever show a key is MENTIONED; it cannot
## show THIS entry is the one a consumer loads. No corpus fix reaches that.
##
## Bidirectional, like the loop-agreement ratchet: a NEW unreachable track
## fails, and a pinned one that becomes reachable ALSO fails, so the list
## cannot rot into a stale claim. When the story lane writes these scenes the
## entries drop off and this file eventually deletes itself.
##
## 🔑 AND THE SECOND DIRECTION MAKES THIS GUARD IMMUNE TO THE ERROR THAT
## CREATED IT, which is worth stating because it is not obvious. cowir-story
## proposed a fleet precondition: before a reachability sweep, name the
## DEFINER and the CONSUMER corpus and assert they are disjoint. This file
## satisfies it structurally (definer music_manifest.json, corpus
## data/cutscenes/) — but it also DETECTS a violation without needing the
## assertion, and that is proven rather than argued. Feed the manifest into
## the corpus, as my morning sweep did, and every pinned track reads as
## reachable, so the stale arm fires naming all four (mutation-verified).
## A one-directional "no orphans" assertion goes GREEN on exactly that
## contamination, which is why the sweep it replaced reported zero.

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


## The MUSIC manifest's ambient_* entries. play_ambient reads the SFX manifest,
## not this one, and play_music is never called with an ambient key — so every
## one of these is unreachable regardless of whether the key also exists in the
## SFX manifest.
##
## ⚠️ THREE OF THEM ARE SHADOWED, and reading the neighbours is the only reason
## I found it. cave/forest/village exist in BOTH manifests under the same key
## pointing at DIFFERENT FILES:
##     ambient_cave    music 187s/1.5MB    sfx 5s/0.0MB   <- the 5s one plays
##     ambient_forest  music 214s/2.0MB    sfx 5s/0.0MB
##     ambient_village music 145s/1.5MB    sfx 5s/0.0MB
## My first pass called those three REACHABLE because the literal "ambient_cave"
## appears in OverworldScene — conflating "this key appears in code" with "this
## manifest entry is reachable". The consumer of that literal is play_ambient,
## which never looks here.
##
## THEY HAVE NEVER PLAYED, and git settles it — this is measured, not inferred:
##   2026-03-23  the 7 beds land in music/ + music_manifest (13818c62).
##               play_ambient DOES NOT EXIST. There is no ambient playback
##               system at all, only procedural music generators.
##   2026-04-06  func play_ambient introduced (60ed1886) reading the SFX
##               manifest. `-S _music_manifest.has(sound_key)` over the whole
##               history of this file returns NOTHING: no version of
##               play_ambient ever consulted the music manifest.
##   2026-04-07  the 5s ambient SFX land in sfx/ + sfx_manifest (5ebe90e9).
##               Those work.
##
## So these are not superseded legacy — they are STILLBORN. Composed, committed,
## and the consumer that arrived two weeks later looked somewhere else. Nothing
## a player has ever heard is at stake either way, which makes the decision
## cheap: DELETE for 11.4 MB back, or WIRE them and cave/forest/village get a
## 2.5-3.5 minute composed bed instead of a 5-second loop. That is struktured's
## call; the guard only ensures the 17 MB is visible while he makes it.
const KNOWN_UNREACHABLE_AMBIENT_TRACKS: Array[String] = [
	"ambient_cave",
	"ambient_digital",
	"ambient_forest",
	"ambient_industrial",
	"ambient_ocean",
	"ambient_steampunk",
	"ambient_village",
]


func test_ambient_music_entries_are_all_unreachable_as_pinned() -> void:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	var found: Array[String] = []
	for key in tracks.keys():
		var k: String = str(key)
		if k.begins_with("ambient_") and str((tracks[k] as Dictionary).get("file", "")) != "":
			found.append(k)
	found.sort()
	var pinned: Array[String] = KNOWN_UNREACHABLE_AMBIENT_TRACKS.duplicate()
	pinned.sort()
	assert_gt(found.size(), 3,
		"SCOPE control: only %d ambient music entries walked — a green here would be vacuous" % found.size())
	assert_eq(found, pinned,
		"the ambient_* set in the music manifest changed (found %s, pinned %s) — every entry here is unreachable (play_ambient reads the SFX manifest), so adding one ships audio nothing can play. Remove it, or move it to the SFX manifest where the consumer looks." % [found, pinned])

	## 🛑 THE SET CHECK ABOVE IS HOLLOW ON ITS OWN, proven not argued: wire
	## play_music("ambient_cave") into SoundManager and it stays GREEN, because
	## it compares KEY SETS and never asks whether anything reaches them. That is
	## cowir-sfx's shape (a guard looping the same constant that drives its own
	## exclusion) one file over. The claim is UNREACHABLE, so verify THAT.
	## Walk ALL of src/ — a hand-listed set of files is the wrong corpus and the
	## control caught it: my first version scanned three files and the known
	## play_music("boss_mordaine") lives in a fourth (BattleScene.gd). Any file
	## could wire an ambient key, so any file must be scanned.
	var all_src: String = _walk_gd("res://src")
	assert_gt(all_src.length(), 100000,
		"SCOPE control: the src walk read back only %d chars — it is not reaching the code, and a zero-hit result below would be vacuous" % all_src.length())

	## Control: the scan must FIND a real play_music call, or its silence proves nothing.
	assert_true(all_src.contains("play_music(\"boss_mordaine\")"),
		"CONTROL FAILED: a play_music call we know exists was not found — the scan cannot detect a new one either")

	var wired: Array[String] = []
	for key in found:
		if all_src.contains("play_music(\"%s\")" % key):
			wired.append(str(key))
	assert_eq(wired.size(), 0,
		"an ambient music entry is now REACHED by play_music (%s) — it is no longer unreachable, so remove it from the pin and delete the claim that these never play" % wired)


func _walk_gd(dir_path: String) -> String:
	## Recursive .gd concatenation. Kept simple deliberately: the SCOPE control
	## on its output length is what proves it reached the code, not this code.
	var out: String = ""
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full: String = dir_path + "/" + name
		if d.current_is_dir():
			out += _walk_gd(full)
		elif name.ends_with(".gd"):
			out += FileAccess.get_file_as_string(full)
		name = d.get_next()
	d.list_dir_end()
	return out

