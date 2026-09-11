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

	## CORPUS FROM THE CONSUMER, NOT FROM A NAME (2026-09-11). This was `begins_with("ambient_")`,
	## and it missed all six weather beds — they reach play_ambient but are named weather_*, so the
	## guard that exists to defend the loop contract could not see the keys that were breaking it.
	## Measured when found: loop=false in manifest AND .import on all six, wrap steps to +53 dB.
	## A name prefix is a guess about the corpus; the call site IS the corpus.
	var ambient: Array[String] = []
	for k in sounds.keys():
		if str(k).begins_with("ambient_"):
			ambient.append(str(k))
	for k in _keys_passed_to_play_ambient():
		if sounds.has(k) and not ambient.has(k):
			ambient.append(k)
	ambient.sort()
	assert_gt(ambient.size(), 5,
		"SCOPE control: found only %d ambient cues — a green here would be vacuous" % ambient.size())
	## Control on the NEW half specifically: the prefix scan alone would still satisfy the count above,
	## so assert the consumer scan found something a name never would.
	assert_true(ambient.has("weather_rain"),
		"SCOPE control: weather_rain reaches play_ambient and must be in the corpus — if this fails the src scan is dead and the prefix is silently back in charge")

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


## Every literal handed to play_ambient anywhere in src/. WeatherSystem spells each one out
## (its own comment says "literal keys per branch so the sfx-orphan audit can see every ambient").
func _keys_passed_to_play_ambient() -> Array[String]:
	var found: Array[String] = []
	var re := RegEx.new()
	re.compile("play_ambient\\(\\s*\"([^\"]+)\"")
	var stack: Array[String] = ["res://src"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			var full: String = dir_path + "/" + name
			if d.current_is_dir():
				if not name.begins_with("."):
					stack.append(full)
			elif name.ends_with(".gd"):
				for m in re.search_all(FileAccess.get_file_as_string(full)):
					var k: String = m.get_string(1)
					if not found.has(k):
						found.append(k)
			name = d.get_next()
		d.list_dir_end()
	return found
