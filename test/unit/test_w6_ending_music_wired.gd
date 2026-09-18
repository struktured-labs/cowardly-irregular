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
##
## ⛔ THIS BLOCK USED TO SAY THE FOUR OGGs WERE EXCLUDED FROM THE WEB EXPORT AND ASK FOR A RULING
## ON UN-EXCLUDING THEM. THAT WAS TRUE WHEN WRITTEN AND IS NOW FALSE. `fa64fe39a fix(music): the
## campaign ending has music on web` removed the `cutscene_w6*` pattern that `badc1718c` added
## during the pck size diet; `export_presets.cfg` now carries `cutscene_w4*` and `cutscene_w5*`
## only. The endings ship on web.
##
## ⚠️ THE NOTE COST MORE THAN THE BUG WOULD HAVE, WHICH IS WHY THE REPAIR IS AN ARM RATHER THAN A
## REWORDING. On 2026-09-18 I read it, believed it, and registered "the endings are silent on web"
## as a question for struktured — asking him to authorise 6.3 MB that had already been spent. A
## wrong "this is broken" makes someone act, and the more senior the reader the more it costs.
## The commit that falsified the note did not know the note existed, so no amount of care by its
## author would have kept it true: the repair has to make the claim CHEAP TO CHECK, never
## "remember to revisit". `test_the_endings_are_not_excluded_from_the_web_build` is that check,
## and it also protects fa64fe39a — re-adding the pattern now reds here instead of silently
## un-scoring the ending again.

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
			"the '%s' ending must play \"%s\" — composed, in the manifest, on disk. Without this step the ending plays on whatever bed happened to be running. NOTE before you 'fix' this: these four OGGs are excluded from the WEB export (cutscene_w6* in export_presets.cfg), so restoring the step scores the ending on DESKTOP only" % [key, EXPECTED[key]])


func test_every_wired_theme_exists_in_the_manifest() -> void:
	## A step naming a track the manifest lacks is a silent no-op, so wiring
	## alone is not enough.
	var man := _json(MANIFEST)
	var tracks = man.get("tracks", man)
	for key in EXPECTED:
		assert_true(tracks.has(EXPECTED[key]),
			"music_manifest must carry \"%s\"" % EXPECTED[key])


## Parses the preset by NAME, not by position or length — the sibling file records a lane scoring
## six tracks against the FIRST preset (Linux, zero audio patterns) and getting the only answer
## that list could produce.
func _web_exclude_patterns() -> PackedStringArray:
	var cfg: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	assert_gt(cfg.length(), 500, "SCOPE control: export_presets.cfg read back %d chars" % cfg.length())
	var in_web: bool = false
	var raw: String = ""
	var found: bool = false
	for line in cfg.split("\n"):
		var l: String = str(line).strip_edges()
		if l.begins_with("name="):
			in_web = (l == "name=\"Web\"")
		elif in_web and l.begins_with("exclude_filter="):
			raw = l.substr(l.find("\"") + 1)
			raw = raw.substr(0, raw.rfind("\""))
			found = true
			break
	assert_true(found,
		"SCOPE control: no preset named \"Web\" carries an exclude_filter — the config shape changed and this arm would describe the wrong build")
	var out: PackedStringArray = []
	for pat in raw.split(","):
		var t: String = str(pat).strip_edges()
		if t != "":
			out.append(t)
	return out


## Every `track` this cutscene declares, DERIVED — not EXPECTED. The two corpora differ on purpose:
## EXPECTED is the authored branch->theme MAPPING and is hand-written for the reason its own comment
## gives. This arm's subject is "which of this scene's music reaches the web build", which is every
## track it plays, so deriving it is what makes the claim match the header.
func _declared_tracks() -> Array:
	var raw: String = FileAccess.get_file_as_string(CUTSCENE)
	assert_gt(raw.length(), 200, "SCOPE control: %s read back %d chars" % [CUTSCENE, raw.length()])
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "SCOPE control: %s did not parse as a Dictionary" % CUTSCENE)
	if not (parsed is Dictionary):
		return []
	var found: Array = []
	var stack: Array = [parsed]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is Dictionary:
			for k in node.keys():
				if k == "track" and node[k] is String and str(node[k]) != "":
					if not found.has(str(node[k])):
						found.append(str(node[k]))
				else:
					stack.append(node[k])
		elif node is Array:
			for v in node:
				stack.append(v)
	found.sort()
	return found


func test_the_endings_are_not_excluded_from_the_web_build() -> void:
	var pats := _web_exclude_patterns()
	assert_gt(pats.size(), 0, "CONTROL: the Web preset must carry patterns, or nothing below can fail")

	## ⛔ THE CORPUS IS DERIVED, AND THIS ARM USED TO USE `EXPECTED` — four answer themes. The scene
	## also plays `cutscene_w6_calibrant_question` at step 4, which the stale note this file was
	## repaired from had named explicitly. The header said "the endings ship on web" and the arm
	## bought four fifths of it: @cowir-battle's universal-promised / existential-bought shape, in
	## the guard I wrote to replace a note that decayed.
	var tracks := _declared_tracks()
	assert_gt(tracks.size(), EXPECTED.size(),
		"CONTROL: the derived corpus (%d) must be WIDER than the authored mapping (%d) — if it is not, the derivation has stopped reaching the non-branch steps and this arm is back to four fifths" % [tracks.size(), EXPECTED.size()])
	for key in EXPECTED:
		assert_true(tracks.has(EXPECTED[key]),
			"CONTROL: the derived corpus must contain the authored theme %s, or the two corpora have drifted apart" % EXPECTED[key])

	## POSITIVE CONTROL on the matcher itself, using a pattern read from the real file: W4 IS still
	## excluded, so a synthetic W4 path must match. Without this a broken glob reports every theme
	## as shipping — the zero that looks like health.
	var w4_hit := false
	for pat in pats:
		if "assets/audio/music/cutscene_w4_probe.ogg".match(pat):
			w4_hit = true
			break
	assert_true(w4_hit,
		"CONTROL: no Web pattern matches a cutscene_w4 path — either W4 is no longer excluded (then this arm's premise changed) or the glob match is broken and every result below is a false clean")

	var excluded: Array = []
	for track in tracks:
		var path: String = "assets/audio/music/%s.ogg" % track
		for pat in pats:
			if path.match(pat):
				excluded.append("%s (by %s)" % [track, pat])
				break
	assert_eq(excluded, [],
		"a theme this scene PLAYS is dropped from the web build, so that beat is silent where most people play: %s" % str(excluded))
