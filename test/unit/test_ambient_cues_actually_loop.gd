extends GutTest

## play_ambient promises a LOOP — assert the cues can deliver one (2026-09-09).
##
## SoundManager.play_ambient's docstring: "Start a looping ambient sound
## (weather, environment)." The function sets no loop flag. It assigns the
## stream and plays; whether it loops is decided entirely by the imported
## file. So the promise is kept by DATA, not by code.
##
## 🔑 cowir-main's inverted comment rule, same day: a comment asserting a
## CONSUMER is a query to go check, but a comment describing INTENT is evidence
## of what was wanted. "Looping" is intent — an ambient bed that plays once and
## stops leaves a cave silent for the rest of the visit, which nothing reports.
##
## ⚠️ THE EXISTING GUARD CANNOT SEE THIS. test_all_sfx_import_loop_matches_manifest
## asserts manifest and .import AGREE. A cue with loop=false in BOTH agrees
## perfectly. Measured: set ambient_forest to false in both and that suite stays
## GREEN (Passing 2). Agreement is not truth, and for this contract truth is
## what play_ambient needs.
##
## All 11 comply today. This holds it.
##
## ⚠️ AN AUTOMATED PROSE-VS-CODE SWEEP WAS TRIED AND DISCARDED — recording the
## numbers so nobody rebuilds it. Over 180 SoundManager functions, filtering on
## "docstring mentions loop" and checking the body for a loop mechanism:
##   14 hits, essentially all noise. stop_ambient's doc says "stop the ambient
##   LOOP" — a mention, not a promise. _generate_victory_rock_loop has it in the
##   NAME.
##   AND A FALSE NEGATIVE ON THE MOST LOOP-SETTING FUNCTION IN THE FILE:
##   _create_and_play_looping_wav sets wav.loop_mode / loop_begin / loop_end,
##   and my `\.loop\b` pattern could not match `loop_mode` because `_` is a
##   word character.
## Wrong in both directions at once, which is cowir-sfx's ~1-in-9 word-list rate
## in a new domain. The doc/body split itself was FINE (controlled against
## cowir-autogrind's blindness: play_ambient's body does not contain "looping"),
## so the corpus was right and the PREDICATE was wrong — the two failure modes
## are independent and fixing one says nothing about the other.
##
## The finding this file defends came from READING play_ambient, not from the
## sweep. Recorded because "I automated it and got 14 results" is exactly the
## shape that gets published.

const SFX_MANIFEST := "res://data/sfx_manifest.json"


func test_every_ambient_cue_loops() -> void:
	var raw: String = FileAccess.get_file_as_string(SFX_MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: sfx_manifest read back %d chars" % raw.length())
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "sfx_manifest did not parse")
	var sounds: Dictionary = (parsed as Dictionary).get("sfx", {})
	assert_gt(sounds.size(), 100,
		"SCOPE control: walked %d sfx entries — wrong root key? It is 'sfx', not 'sounds'." % sounds.size())

	var ambient: Array[String] = []
	for k in sounds.keys():
		if str(k).begins_with("ambient_"):
			ambient.append(str(k))
	ambient.sort()
	assert_gt(ambient.size(), 5,
		"SCOPE control: found only %d ambient cues — a green here would be vacuous" % ambient.size())

	var broken: Array[String] = []
	for key in ambient:
		var entry: Dictionary = sounds[key]
		if not bool(entry.get("loop", false)):
			broken.append("%s (manifest loop is not true)" % key)
			continue
		var f: String = str(entry.get("file", ""))
		if f == "":
			broken.append("%s (no file)" % key)
			continue
		var imp: String = (f if f.begins_with("res://") else "res://" + f) + ".import"
		var text: String = FileAccess.get_file_as_string(imp)
		if text == "":
			broken.append("%s (no .import — run --import)" % key)
			continue
		var found_flag: bool = false
		for line in text.split("\n"):
			var t: String = line.strip_edges()
			if t.begins_with("loop="):
				found_flag = true
				if t.substr(5).strip_edges().to_lower() != "true":
					broken.append("%s (.import says %s)" % [key, t])
				break
		if not found_flag:
			broken.append("%s (.import has no loop= line)" % key)

	assert_eq(broken.size(), 0,
		"ambient cues that will NOT loop (%d): %s — play_ambient's contract is a LOOP, and a one-shot leaves the area silent for the rest of the visit. The manifest/import AGREEMENT guard cannot see this: false in both AGREES." % [broken.size(), broken])
