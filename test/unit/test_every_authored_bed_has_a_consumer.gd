extends GutTest

## A track in the manifest that nothing asks for is money spent on silence.
##
## 165 authored beds; 10 of them are reached by no path in the game. Finding that
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

## The 10, each with WHY it has no consumer and what would retire it.
## This is not permission to stay: the test fails if the set grows OR shrinks.
const KNOWN_UNREACHED := {
	"ambient_digital": "one of the never-played ambient beds — @struktured to delete or wire to cave/forest/village",
	"ambient_industrial": "same decision",
	"ambient_ocean": "same decision",
	"ambient_steampunk": "same decision",
	## Concealed until 2026-09-11 by this file's own corpus bug: ambient_village
	## is in BOTH manifests, so it matched its SFX twin and read as reached. The
	## SFX bed IS played (play_ambient reads sfx_manifest); the MUSIC entry of
	## the same name is what nothing asks for.
	"ambient_village": "never-played MUSIC bed; the identically-named SFX bed is live, which is what hid it",
	## The last two, concealed one layer deeper: OverworldScene assigns these as
	## plain literals and feeds them to play_ambient(), which reads sfx_manifest.
	## The SFX twins are 5s; these music beds are 187s and 214s and have never
	## played. Banked 2026-09-09 as project_music_ambient_two_stores; this file
	## rediscovered it the hard way twice.
	"ambient_cave": "music bed 187s, unplayed — OverworldScene's \"ice\" zone plays the 5s SFX bed of the same name",
	"ambient_forest": "music bed 214s, unplayed — OverworldScene's \"forest\"/\"swamp\" zones play the 5s SFX bed of the same name",
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


## ⛔ STRIP COMMENTS, NEVER STRINGS. A track id named only in a comment would
## otherwise read as reached — this file's own SoundManager comments discuss
## battle_goblin being recast, and CLAUDE.md-style prose names beds constantly.
## That failure is QUIET: it removes an orphan from the report, so nobody
## investigates. (Measured 2026-09-11: exactly one id, boss_tempo_steampunk, is
## mentioned only in a comment, and it is composed-reachable anyway — so no
## verdict moves today. The guard is hardened for the next one.)
##
## ⚠️ AND NOT STRINGS, which is where the sibling rule inverts for this lane.
## cowir-autogrind's sweep strips string literals because a method name inside
## a push_warning is not a call. Here a string literal IS the consumer:
## play_music("boss_mordaine") is the reference. Stripping strings would report
## every literally-named bed as an orphan.
## ⛔ AND ESCAPE-AWARE, which it was not until 2026-09-11. The first version
## tracked quote parity with no escape handling, so `"x \" #y"` closed the
## string at the ESCAPED quote, left the scanner outside a string, and let the
## following `#` truncate the line. Measured: a real track reference after such
## a `#` silently vanished from the corpus and the guard stayed green. Three
## files in src/ already carry an escaped quote, so the shape is present.
##
## Consuming `\X` as a unit covers both costumes at once: `\"` does not close
## the string, and `\\` does not escape the quote that follows it.
func _strip_comments(src: String) -> String:
	var out: PackedStringArray = []
	for line in src.split("\n"):
		var l: String = str(line)
		var quote: String = ""
		var kept: String = ""
		var i: int = 0
		while i < l.length():
			var ch: String = l[i]
			if quote != "":
				kept += ch
				if ch == "\\" and i + 1 < l.length():
					kept += l[i + 1]
					i += 2
					continue
				if ch == quote:
					quote = ""
			elif ch == "\"" or ch == "'":
				quote = ch
				kept += ch
			elif ch == "#":
				break
			else:
				kept += ch
			i += 1
		out.append(kept)
	return "\n".join(out)


## Everything that could NAME a track, minus the manifest itself — which would
## match every id and make the whole sweep vacuous.
func _consumer_text() -> String:
	var paths: Array[String] = []
	_files("res://src", ".gd", paths)
	_files("res://data", ".json", paths)
	var parts: PackedStringArray = []
	for p in paths:
		## ⛔ BOTH MANIFESTS, NOT JUST OURS. Excluding only music_manifest.json
		## left sfx_manifest.json in the corpus — and `ambient_*` lives in BOTH
		## stores under the same keys. So ambient_village matched its own SFX
		## entry and reported a consumer it does not have; the vacuity this
		## exclusion exists to prevent, one store over. Necessary and NOT
		## sufficient: see _is_reached, where a dual-store id needs a music-side
		## CALL, because a bare literal is consumed by whichever store its
		## function reads.
		if p.ends_with("music_manifest.json") or p.ends_with("sfx_manifest.json"):
			continue
		var body: String = FileAccess.get_file_as_string(p)
		## JSON carries no comments; only .gd needs stripping.
		parts.append(_strip_comments(body) if p.ends_with(".gd") else body)
	return "\n".join(parts)


## ⛔ PIN THE HELPER, NOT THE CORPUS. Six variants of this stripper broke across
## four lanes in one afternoon — bare find() · whole-line comments · trailing
## comments · a quoted `#` · an escaped quote · an escaped backslash — and every
## one was found by planting a mutation in src/ and watching the verdict move.
## That route costs a full run per costume and each fix was blind to the next.
## A case table on the function answers all six in milliseconds and reds on the
## seventh. cowir-sfx and cowir-overworld arrived here first; this is their
## structure applied to this lane's polarity.
func test_the_comment_stripper_itself() -> void:
	var cases: Array = [
		## [input, expected, why]
		["play_music(\"a\")  # note", "play_music(\"a\")  ",
			"a trailing comment is cut AT the #, not trimmed"],
		["# whole line", "", "a full-line comment blanks"],
		["var c = \"[color=#44ff44]\"", "var c = \"[color=#44ff44]\"",
			"a # inside DOUBLE quotes is not a comment"],
		["var c = '#tag'", "var c = '#tag'",
			"a # inside SINGLE quotes is not a comment"],
		["var s = \"x \\\" #y\" + \"keep\"", "var s = \"x \\\" #y\" + \"keep\"",
			"an ESCAPED QUOTE does not close the string, so the # stays inside it"],
		["var s = \"a\\\\\"  # gone", "var s = \"a\\\\\"  ",
			"an escaped BACKSLASH ends the string, so the comment after it IS cut"],
		["play_music(\"a\")", "play_music(\"a\")", "no # at all is untouched"],
	]
	var bad: Array[String] = []
	for c in cases:
		var got: String = _strip_comments(str(c[0]))
		if got != str(c[1]):
			bad.append("%s\n      in:  %s\n      got: %s\n      want:%s" % [c[2], c[0], got, c[1]])
	assert_gt(cases.size(), 5, "SCOPE control: only %d stripper cases" % cases.size())
	assert_eq(bad.size(), 0,
		"the comment stripper is wrong on %d case(s):\n   %s" % [bad.size(), "\n   ".join(bad)])


## ⛔ A SIZE FLOOR IS BLIND TO PARTIAL LOSS, and this file had only a floor plus
## one named member. `_files()` returns silently when a directory will not open,
## so a subtree can vanish from the walk with no quantity moving. Measured by
## dropping each top-level src/ directory in turn:
##
##     battle · exploration · maps · quests   CAUGHT (a uniquely-named bed orphans)
##     ui · cutscene                          SILENT — they name no bed uniquely
##
## Those two fail toward ALARM rather than false-clean (a bed consumed only from
## a dropped subtree reads as an orphan), which is the safe direction — but the
## guard's claim is "nothing in src/ reaches this", and a claim should cover what
## it says. cowir-sprites' register point applies: check membership against
## something that CANNOT shrink with the corpus it audits, so the filesystem's
## own directory list is the register here rather than a list in this file.
func test_the_consumer_walk_reaches_every_source_subtree() -> void:
	var paths: Array[String] = []
	_files("res://src", ".gd", paths)
	assert_gt(paths.size(), 200,
		"SCOPE control: the walk collected %d .gd files — too few for any membership claim below to mean anything" % paths.size())

	## The register: every immediate subdirectory of res://src, read from disk.
	var expected: Array[String] = []
	var d := DirAccess.open("res://src")
	assert_true(d != null, "SCOPE control: res://src will not open")
	if d == null:
		return
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		if d.current_is_dir() and not n.begins_with("."):
			expected.append(n)
		n = d.get_next()
	d.list_dir_end()
	expected.sort()
	assert_gt(expected.size(), 8,
		"SCOPE control: res://src lists %d subdirectories — the register is the thing being trusted here, so a short read makes every claim below free" % expected.size())

	## A subtree with no .gd at all is not a walk failure — src/shaders holds only
	## .gdshader, and demanding a hit there would be the guard over-claiming. Ask
	## the filesystem whether the subtree HAS any GDScript, then require it.
	var missing: Array[String] = []
	for sub in expected:
		var owned: Array[String] = []
		_files("res://src/" + sub, ".gd", owned)
		if owned.is_empty():
			continue
		var prefix: String = "res://src/" + sub + "/"
		var found: bool = false
		for p in paths:
			if p.begins_with(prefix):
				found = true
				break
		if not found:
			missing.append(sub)
	assert_eq(missing.size(), 0,
		"the consumer walk collected NOTHING from %d of %d src subtrees (%s) — every 'no consumer' verdict in this file is scoped to whatever it did reach, which is not what the guard claims" % [missing.size(), expected.size(), missing])


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
	## The same check for the OTHER store that shares this key space.
	assert_eq(text.find("\"sfx\": {"), -1,
		"CONTROL FAILED: sfx_manifest.json is inside the corpus — ambient_* keys exist in BOTH manifests, so an unplayed music bed matches its SFX twin and reads as reached")
	## Comment stripping must not eat the consumers. A real call is a string
	## literal, and over-stripping would report every named bed as an orphan.
	assert_gt(text.find("play_music(\"boss_mordaine\")"), 0,
		"CONTROL FAILED: comment stripping removed a real play_music call — strings are consumers in this lane, only '#' comments may go")


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


## Ids that exist in BOTH manifests. For these a bare literal proves nothing:
## `ambient_key = "ambient_forest"` is consumed by play_ambient(), which reads
## the SFX store, so the identically-named MUSIC bed stays unplayed.
func _dual_store_ids() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string("res://data/sfx_manifest.json")
	var sfx: Dictionary = (JSON.parse_string(raw) as Dictionary).get("sfx", {})
	assert_gt(sfx.size(), 100, "SCOPE control: parsed %d sfx entries — wrong root key?" % sfx.size())
	var mraw: String = FileAccess.get_file_as_string(MANIFEST)
	var tracks: Dictionary = (JSON.parse_string(mraw) as Dictionary).get("tracks", {})
	var out: Dictionary = {}
	for k in tracks.keys():
		if sfx.has(str(k)):
			out[str(k)] = true
	return out


func _is_reached(id: String, text: String, monsters: Dictionary) -> bool:
	## ⛔ A LITERAL DOES NOT SAY WHICH STORE CONSUMES IT. Excluding both
	## manifests from the corpus stopped an id matching its own entry, and was
	## still not enough: ambient_cave and ambient_forest appear in
	## OverworldScene as plain assignments feeding play_ambient(), which reads
	## sfx_manifest. The music beds of the same name — 187s and 214s against the
	## SFX twins' 5s — have never played. Measured 2026-09-11, after this file
	## twice reported a smaller orphan set than the truth.
	##
	## So for a dual-store id the consumer must be a MUSIC-side call. For every
	## other id a literal is proof enough, because only one store can claim it.
	## ⛔ A GENERIC ONE-WORD ID MATCHES PROSE, NOT A CONSUMER. Five manifest ids
	## carry no underscore — autogrind · danger · menu · title · victory — and
	## every one is an ordinary English word. `var title = Label.new()` and
	## "Complete an autogrind run" both score as consumers. Measured 2026-09-11
	## in the three files cowir-adhoc proved unreachable: all three "named" two
	## tracks each, and every hit was prose.
	##
	## No verdict moves today (all five are genuinely played from play_music's
	## match arms), which is exactly why it needed encoding rather than a note:
	## delete an arm and the bed would still read as reached, forever, on the
	## strength of a label variable. Same class as the brief keying the shop
	## theme "shop" and GameLoop's _smoke_shot("shop") excusing it.
	if _dual_store_ids().has(id) or not id.contains("_"):
		return _asked_for_by_a_music_call(id, text)
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


## Keys briefed in tools/music_prompts.json that no consumer would ask for if
## they were generated tomorrow. Each is Suno credits spent on silence.
const KNOWN_UNREACHABLE_BRIEFS := {
	"battle_blood_wolf_alpha": "reachable by key, but SHADOWED: blood_wolf_alpha declares music_track=battle_wolf in monsters.json, and BattleScene._declared_music_track says a declaration outranks every derived key. The declaration must change in the same commit that generates this track — changing it now would drop the alpha to generic battle music.",
}


## ⛔ A BARE-WORD SEARCH IS NOT SAFE HERE and the loose matcher above would have
## MISSED the defect this arm exists for. The brief used to key the shop theme
## as "shop"; `_is_reached` called it reached because `GameLoop:522` contains
## `_smoke_shot("shop")` — a screenshot test. The music consumer asks for
## `interior_shop` (ShopInterior.gd:99 -> play_area_music), so a track generated
## as "shop" would have been played by nothing. Short generic keys collide with
## ordinary prose; a pending key must be matched in a MUSIC context or not at all.
func _asked_for_by_a_music_call(id: String, text: String) -> bool:
	for shape in ["play_music(\"%s\")", "play_area_music(\"%s\")",
			"_try_play_from_manifest(\"%s\")", "\"track\": \"%s\"",
			"\"music_track\": \"%s\"", "\"music\": \"%s\""]:
		if text.find(shape % id) >= 0:
			return true
	## interior_ keys are resolved per-world before the base key is tried.
	if id.begins_with("interior_") and text.find("play_area_music(\"%s\")" % id) >= 0:
		return true
	return false


func test_every_briefed_but_ungenerated_track_has_somewhere_to_land() -> void:
	var braw: String = FileAccess.get_file_as_string("res://tools/music_prompts.json")
	assert_gt(braw.length(), 5000, "SCOPE control: music_prompts.json read back %d chars" % braw.length())
	var shared: Dictionary = (JSON.parse_string(braw) as Dictionary).get("shared_tracks", {})
	assert_gt(shared.size(), 100, "SCOPE control: shared_tracks holds %d entries" % shared.size())

	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	var text: String = _consumer_text()

	## Control: a key we KNOW is asked for by a music call must test true, and a
	## word that appears only as prose must test false.
	assert_true(_asked_for_by_a_music_call("interior_shop", text),
		"CONTROL FAILED: interior_shop is passed to play_area_music at ShopInterior.gd:99 but the matcher cannot see it")
	assert_false(_asked_for_by_a_music_call("shop", text),
		"CONTROL FAILED: the bare word 'shop' tests as a music call — the matcher is matching prose, which is the exact false positive this arm exists to avoid")

	var pending: Array[String] = []
	for k in shared.keys():
		if not tracks.has(str(k)):
			pending.append(str(k))
	pending.sort()
	assert_gt(pending.size(), 5,
		"SCOPE control: only %d briefed tracks are ungenerated — if the queue emptied, this arm is measuring nothing" % pending.size())

	var homeless: Array[String] = []
	for id in pending:
		if KNOWN_UNREACHABLE_BRIEFS.has(id):
			continue
		if _asked_for_by_a_music_call(id, text):
			continue
		## Composed families still count: nothing names boss_dragon_fire, but
		## "dungeon_"/"boss_" composition will ask for it once it exists.
		var comp: bool = false
		for prefix in COMPOSED_FAMILIES.keys():
			if id.begins_with(str(prefix)):
				comp = true
		if id.begins_with("battle_") or id.begins_with("village_"):
			comp = true
		if not comp:
			homeless.append(id)
	assert_eq(homeless.size(), 0,
		"briefed tracks that no consumer would ask for if generated (%d): %s — generating these spends credits on silence; fix the brief KEY to match what the runtime requests, before the queue is unblocked" % [homeless.size(), homeless])


func test_no_brief_entry_duplicates_an_already_shipped_track() -> void:
	## ⛔ THE "BLOCKED ON SUNO" COUNT WAS WRONG BY ONE FOR MONTHS, AND I REPORTED
	## IT EVERY HOUR. The brief keyed the shop theme "shop"; it was generated on
	## 2026-04-18 and registered as `interior_shop` (file shop.ogg), which is the
	## key ShopInterior actually asks for. Comparing brief keys against manifest
	## KEYS therefore listed a shipped, playing track as pending work.
	##
	## 🔑 THE TITLE IS THE STABLE IDENTITY, THE KEY IS NOT. A track can be
	## re-keyed to match its consumer — which is correct and should happen — and
	## a key-only comparison reads that correction as a regression to redo. So
	## this arm matches on `title_template`, and a hit means the brief entry is
	## stale bookkeeping, not a queued generation.
	var braw: String = FileAccess.get_file_as_string("res://tools/music_prompts.json")
	var shared: Dictionary = (JSON.parse_string(braw) as Dictionary).get("shared_tracks", {})
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})

	var by_title: Dictionary = {}
	for k in tracks.keys():
		var e: Variant = tracks[k]
		if e is Dictionary:
			var t: String = str((e as Dictionary).get("title", ""))
			if t != "":
				by_title[t] = str(k)
	assert_gt(by_title.size(), 100,
		"SCOPE control: indexed only %d manifest titles" % by_title.size())

	var stale: Array[String] = []
	var pending: int = 0
	for key in shared.keys():
		var k: String = str(key)
		if tracks.has(k):
			continue
		pending += 1
		var t: String = str((shared[k] as Dictionary).get("title_template", ""))
		if t != "" and by_title.has(t):
			stale.append("brief '%s' is already shipped as manifest '%s' (\"%s\")" % [k, by_title[t], t])
	assert_gt(pending, 5,
		"SCOPE control: only %d brief entries are unmatched by key — nothing to check" % pending)
	assert_eq(stale.size(), 0,
		"brief entries listed as pending that ALREADY SHIPPED under another key (%d): %s — this inflates the generation queue and spends a scarce unblock on work that is done" % [stale.size(), stale])


func test_no_briefed_battle_track_is_shadowed_by_a_declaration() -> void:
	## ⛔ THE PIN FOR THIS WAS INERT UNTIL THIS ARM EXISTED. A briefed
	## `battle_<monster>` key passes the reachability check above on its prefix
	## alone, so listing it in KNOWN_UNREACHABLE_BRIEFS suppressed nothing — the
	## detector could not emit it either way. An allowlist entry for something
	## your detector cannot produce is not a suppression, it is a comment that
	## looks like one.
	##
	## The real hazard is precedence, not naming: BattleScene._declared_music_track
	## states that a monsters.json `music_track` "outranks every derived key", so
	## generating battle_blood_wolf_alpha while blood_wolf_alpha declares
	## battle_wolf produces a track that can never play. The declaration has to
	## move in the same commit that generates the track — and not before, because
	## pointing it at a track that does not exist yet drops the alpha to generic
	## battle music today.
	var braw: String = FileAccess.get_file_as_string("res://tools/music_prompts.json")
	var shared: Dictionary = (JSON.parse_string(braw) as Dictionary).get("shared_tracks", {})
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	var mraw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var mdoc: Dictionary = JSON.parse_string(mraw) as Dictionary
	var monsters: Dictionary = mdoc.get("monsters", mdoc)
	assert_gt(monsters.size(), 50, "SCOPE control: parsed %d monsters" % monsters.size())

	var shadowed: Array[String] = []
	var checked: int = 0
	for key in shared.keys():
		var k: String = str(key)
		if tracks.has(k) or not k.begins_with("battle_"):
			continue
		var mid: String = k.substr(7)
		if not monsters.has(mid):
			continue
		checked += 1
		var declared: String = str((monsters[mid] as Dictionary).get("music_track", ""))
		if declared != "" and declared != k:
			shadowed.append("%s (but %s declares music_track=%s)" % [k, mid, declared])

	## CONTROL: the arm must be looking at something. If no briefed battle track
	## names a real monster, a green here means "nothing measured".
	assert_gt(checked, 0,
		"SCOPE control: no briefed-but-ungenerated battle_<monster> key names a monster in monsters.json — this arm measured nothing")

	var unpinned: Array[String] = []
	for s in shadowed:
		var id: String = s.split(" ")[0]
		if not KNOWN_UNREACHABLE_BRIEFS.has(id):
			unpinned.append(s)
	assert_eq(unpinned.size(), 0,
		"briefed battle tracks that a monsters.json declaration would outrank (%d): %s — generating these produces audio nothing can reach; move the declaration in the SAME commit that generates the track" % [unpinned.size(), unpinned])


## Beds whose ONLY namer is a cutscene that no dispatcher can play. They are not
## forgotten like the pinned orphans — they are WIRED, to a scene that does not
## run. cowir-story is wiring the epilogues (world1's landed 2026-09-11), so this
## set should shrink; when it does the arm says so.
## ⛔ "QUEUED" WAS MY INVENTION AND IT SHIPPED IN .296. Two of these said
## cowir-story had the epilogue queued. They do not — they ruled on 2026-09-11
## that they will not wire the remaining nine, and told me so when they read
## this pin. I inferred a plan from the fact that they had wired world1's and
## wrote it into a guard as fact. A claim about another lane's intent is a
## measurement I never took.
##
## 🔑 AND THE CORRECTED PICTURE IS WORSE, WHICH IS WHY IT MATTERS. Every credits
## bed is named by EXACTLY ONE cutscene — its own epilogue — so there is no
## second route to any of them:
##
##     credits_medieval  <- world1_epilogue    LIVE (wired 2026-09-11)
##     credits_abstract  <- world6_ending      LIVE
##     credits_suburban  <- world2_chapter11   LIVE (step moved .297)
##     credits_steampunk <- world3_chapter5    LIVE (step moved .297)
##     credits_industrial<- world4_chapter5    LIVE (step moved .299)
##     credits_digital   <- world5_chapter5    LIVE (step moved .299)
##
## RESOLVED 2026-09-11. All six campaign credits rolls now have a live route and
## the allowlist's four credits entries are drained. The paragraph below is kept
## as the record of how it read before, and one clause of it is now FALSE: the
## supersessors DO carry the roll_credits step, because moving it there was the
## fix. cowir-story took the pacing call this file deferred to them.
##
## cowir-story ruled W2/W3's epilogues superseded by world2_chapter11 and
## world3_chapter5 — true of the PROSE. Measured here: both supersessors have
## roll_credits = 0. The chapters inherited the beat and not the credits roll,
## so calling the epilogue superseded whole leaves these two beds with no route
## at all. Their revised proposal is to MOVE the step into the supersessor; that
## is a pacing decision about where a campaign's credits roll, so it is theirs
## or struktured's, not mine.
const KNOWN_WIRED_TO_DEAD_SCENES := {
	## 2026-09-11: DRAINED COMPLETELY. Four credits entries retired when their scenes
	## were wired (.297 + .298). The fifth — cutscene_w5_cached_memory — was never a
	## dead bed at all: world5_fragment_* are dispatched by GameLoop's _FRAGMENT_GATES
	## loop, which ends `return fid`. The entry documented an INSTRUMENT limit, and
	## _scene_is_dispatched can see a table loop now, so it is gone too.
}


## Everything that could DISPATCH a cutscene — source, scenes, and non-cutscene
## data. Deliberately excludes data/cutscenes/: a scene names its own id, so
## including them would make every scene look dispatched by itself.
## DECLARED, not merely printed. Measured 2026-09-11: dropping the data/*.json
## root and dropping the src/**.tscn root each left this file 11/11 GREEN,
## because no bed currently depends on either — so a root silently swallowed by
## a refactor was invisible. Printing the corpus makes the claim contradictable
## by a reader; asserting each root contributed makes a DROPPED one loud. It
## still buys nothing against a root never added (cowir-adhoc's limit, exact).
const DISPATCH_WALKS := [["res://src", ".gd"], ["res://src", ".tscn"], ["res://data", ".json"]]


func _dispatcher_text() -> String:
	var paths: Array[String] = []
	_files("res://src", ".gd", paths)
	var after_gd: int = paths.size()
	assert_gt(after_gd, 0, "CORPUS: res://src/**.gd contributed ZERO files — the dispatcher walk is empty and every scene would read as dead")
	_files("res://src", ".tscn", paths)
	assert_gt(paths.size(), after_gd, "CORPUS: res://src/**.tscn contributed ZERO files — a scene dispatched from a .tscn would read as dead, and nothing else reports it")
	var parts: PackedStringArray = []
	for p in paths:
		parts.append(_strip_comments(FileAccess.get_file_as_string(p)) if p.ends_with(".gd") else FileAccess.get_file_as_string(p))
	var json_seen: int = 0
	var d := DirAccess.open("res://data")
	if d != null:
		d.list_dir_begin()
		var n: String = d.get_next()
		while n != "":
			if n.ends_with(".json") and n != "music_manifest.json" and n != "sfx_manifest.json":
				parts.append(FileAccess.get_file_as_string("res://data/" + n))
				json_seen += 1
			n = d.get_next()
		d.list_dir_end()
	assert_gt(json_seen, 0, "CORPUS: res://data/*.json contributed ZERO files — a dispatch table authored in data would read as dead")
	return "\n".join(parts)


func test_no_cutscene_step_type_can_dispatch_another_cutscene() -> void:
	## ⛔ THIS IS WHY _dispatcher_text() MAY EXCLUDE data/cutscenes/ WHOLESALE.
	## If a step type could start another scene, a scene reachable only that way
	## would read as unplayable — a FALSE ZERO, which reads as "nothing can get
	## here" and is the direction that makes people skip live work. cowir-controller
	## hit exactly that today: their referrer filter deleted `load("res://…/X.gd")`
	## lines because the reference form carries the path they were excluding on,
	## and two live menus reported 0 referrers.
	##
	## Mine is safe by CONSTRUCTION rather than by content: CutsceneDirector's
	## `match step_type` has 37 arms and none names a scene, so a cutscene JSON
	## has no way to reach another cutscene. play_cutscene() is a director METHOD
	## called from source — which is the corpus I do scan. Measured alongside:
	## 0 cross-scene id references across 195 scene files.
	var src: String = FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	assert_gt(src.length(), 10000, "SCOPE control: CutsceneDirector read back %d chars" % src.length())
	var start: int = src.find("match step_type")
	assert_gt(start, 0, "SCOPE control: the step dispatch was renamed — re-derive this guard")
	var end: int = src.find("\nfunc ", start)
	var block: String = src.substr(start, end - start)

	var arms: Array[String] = []
	var re := RegEx.new()
	re.compile("\"([a-z_]+)\"")
	for m in re.search_all(block):
		if not arms.has(m.get_string(1)):
			arms.append(m.get_string(1))
	assert_gt(arms.size(), 25,
		"SCOPE control: parsed only %d step types — the arm reader has drifted and a green below would be vacuous" % arms.size())
	assert_true(arms.has("play_music"),
		"CONTROL FAILED: play_music is a real step type but was not parsed")

	var dispatchers: Array[String] = []
	for a in arms:
		for word in ["cutscene", "scene", "chain"]:
			if a.contains(word) and not dispatchers.has(a):
				dispatchers.append(a)
	assert_eq(dispatchers.size(), 0,
		"a cutscene step type can now start another cutscene (%s) — data/cutscenes/ can no longer be excluded from the dispatcher corpus, because a scene reached only by chaining would report as unplayable and its cues as stranded" % [dispatchers])


## ⚠️ ONE-LEVEL, AND SAFE BY THE CORPUS RATHER THAN BY THE CODE. "The scene id
## appears in src/" does not ask whether the file naming it can itself run —
## cowir-adhoc's transitive hole. A scene dispatched only from MenuScene.gd (a
## 1,500-line hub nothing references, found dead 2026-09-11) would score
## playable here. They measured it: 0 of 124 called cutscenes have a dead file
## as their only caller, so the shortcut costs nothing TODAY. It is recorded
## rather than defended because the day that changes, nothing here will say so.
## ⛔ A MENTION IS NOT A DISPATCH, and the looser test made two of this file's
## own pins INERT. The first version asked whether the scene id appears anywhere
## in the dispatcher corpus. It appears for world2_epilogue and world3_epilogue:
##
##     GameLoop:2009  _epilogue_done_or_unwired("world2_epilogue", flags)
##     GameLoop:2045  _epilogue_done_or_unwired("world3_epilogue", flags)
##
## That helper returns TRUE when the scene has no completion flag — it is a gate
## that TOLERATES the epilogue being unwired, and the function name says so. So
## the one reference each of those scenes has is code handling their ABSENCE,
## and I read it as evidence of their presence. Same shape as a reachability
## grep counting the documentation of a scene's death as proof of its life.
##
## 🔑 FOUND BY DELETION, NOT BY READING. cowir-autogrind's check — remove each
## pinned entry and confirm the guard reds — reported credits_steampunk and
## credits_suburban as suppressing nothing. The pin list was right (it came from
## a correct ad-hoc measurement); the guard's own predicate was looser than the
## claim the list makes, so two entries excused a verdict it could never reach.
## Loose: 3 stranded. Tight: 5, which is the list.
## Third dispatch shape: a TABLE LOOP. `for fid in _FRAGMENT_GATES: ... return fid`
## returns a LOOP VARIABLE, so the scene id never appears beside `return` as a
## literal. GameLoop states it above that very table — "the loop returns the id,
## so the static audit does not see these" — and this predicate could not see
## them for months. 20 fragment scenes read as dead, and one bed sat in
## KNOWN_WIRED_TO_DEAD_SCENES documenting the instrument rather than a defect.
## Bounded by INDENTATION and by brace matching, not by char windows: a window
## that is too small truncates and one that is too large swallows the next
## function's returns, and over-reporting dispatch is the silent direction.
## Named beside every verdict so the claim carries its own scope. A stranded-bed
## report is only as strong as this list is complete, and nothing in the test can
## know about a form nobody has thought of (cowir-adhoc, 2026-09-11).
## ATTRIBUTABLE forms — these name a scene id this predicate can tie to a bed.
## ⚠️ BOTH LISTS ARE FLOORS, NOT TOTALS. Together they read as a partition of
## five; they are not. cowir-adhoc published "two dispatch forms", was corrected
## to five, then to six, inside one hour of 2026-09-11 — each time from outside
## the lane that wrote it. An exhaustive count of FORMS drifts on discovery the
## way a file count drifts on content. Treat a new form as expected.
const DISPATCH_FORMS := ["return \"<id>\"", "play_cutscene(\"<id>\")", "for <v> in <TABLE>: return <v>"]
## UNATTRIBUTABLE forms — these dispatch a scene whose id is a VARIABLE or a
## composed path, so no static read can say WHICH scene. Deliberately not
## recognised: guessing would mark scenes live that are not, and that is the
## silent direction. Named because the failure they cause is a FALSE ALARM —
## a live scene reads as dead, a bed strands, and the report is a CANDIDATE
## rather than a verdict. cutscene_w5_cached_memory sat in the allowlist for
## exactly that reason until 2026-09-11. (cowir-adhoc found 5 forms where I
## had printed 3; these are the two I do not detect.)
const UNATTRIBUTABLE_FORMS := ["play_cutscene(<var>) — 6 sites incl. QuestSystem, PartyChatMenu, CutsceneGallery, CastleHarmonia(const)", "boss_cutscene_id composed into res://data/cutscenes/%s.json — DragonCave"]
## The ROOTS beside the forms. cowir-battle caught a sibling guard reading only
## src/ — two hours after its author had corrected that very scope — and caught it
## BECAUSE the guard printed its roots. A verdict that names neither what it read
## nor how it read it cannot be contradicted by anyone but its author.
const DISPATCH_ROOTS := "src/**.gd (comments stripped) + src/**.tscn + data/*.json — each asserted non-empty; data/cutscenes/ EXCLUDED by design, guarded by test_no_cutscene_step_type_can_dispatch_another_cutscene"


func _loop_dispatched_ids(disp: String) -> Dictionary:
	var out: Dictionary = {}
	var lines: PackedStringArray = disp.split("\n")
	var head := RegEx.new()
	head.compile("^(\\s*)for\\s+(\\w+)\\s+in\\s+(\\w+)\\s*:")
	for i in lines.size():
		var m: RegExMatch = head.search(lines[i])
		if m == null:
			continue
		var indent: int = m.get_string(1).length()
		var loop_var: String = m.get_string(2)
		var table: String = m.get_string(3)
		var returns_itself: bool = false
		for j in range(i + 1, lines.size()):
			var ln: String = lines[j]
			if ln.strip_edges() == "":
				continue
			if ln.length() - ln.lstrip(" \t").length() <= indent:
				break
			if ln.strip_edges() == "return %s" % loop_var:
				returns_itself = true
				break
		if not returns_itself:
			continue
		for key in _const_dict_keys(disp, table):
			out[key] = table
	return out


## Top-level string keys of `const <name> := { ... }`, by brace matching.
func _const_dict_keys(src: String, name: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var at: int = src.find("%s := {" % name)
	if at < 0:
		at = src.find("%s = {" % name)
	if at < 0:
		return out
	var open_brace: int = src.find("{", at)
	var depth: int = 0
	var end: int = open_brace
	while end < src.length():
		var c: String = src[end]
		if c == "{":
			depth += 1
		elif c == "}":
			depth -= 1
			if depth == 0:
				break
		end += 1
	var block: String = src.substr(open_brace, end - open_brace + 1)
	var kre := RegEx.new()
	kre.compile("\"([A-Za-z0-9_]+)\"\\s*:")
	var inner: int = 0
	for line in block.split("\n"):
		var ln: String = str(line)
		var km: RegExMatch = kre.search(ln)
		## Only TOP-level keys: a nested value dict's keys are not scene ids.
		if km != null and inner <= 1:
			out.append(km.get_string(1))
		inner += ln.count("{") - ln.count("}")
	return out


func _scene_is_dispatched(scene: String, disp: String) -> bool:
	## Three real shapes: _get_pending_story_cutscene returns the id literally, a
	## caller plays it by name, or a table loop returns its own loop variable.
	## Anything else is a mention.
	if disp.find("return \"%s\"" % scene) >= 0:
		return true
	if disp.find("play_cutscene(\"%s\")" % scene) >= 0:
		return true
	return _loop_dispatched_ids(disp).has(scene)


func test_no_bed_is_wired_only_to_a_cutscene_nothing_plays() -> void:
	var disp: String = _dispatcher_text()
	assert_gt(disp.length(), 500000,
		"SCOPE control: dispatcher corpus is %d chars — too small" % disp.length())
	assert_true(_scene_is_dispatched("world1_prologue", disp),
		"CONTROL FAILED: world1_prologue IS dispatched (GameLoop returns it from _get_pending_story_cutscene) but the predicate cannot see it — a green below would mean every scene reads as dead")
	assert_false(_scene_is_dispatched("world2_epilogue", disp),
		"CONTROL FAILED: world2_epilogue is only named by _epilogue_done_or_unwired, a gate that TOLERATES it being unwired. If the predicate counts that as dispatch it is the loose one this helper replaced")
	## The TABLE-LOOP form needs its own control, and it did not have one when the
	## form was added. The other two arms would still catch a total failure — a
	## fragment bed would strand and red — but only because a bed happens to
	## depend on it today. Rename _FRAGMENT_GATES and the parser silently finds
	## nothing. Named members, not a count: a floor cannot tell 20 from 2.
	var loop_ids: Dictionary = _loop_dispatched_ids(disp)
	for member in ["world1_fragment_warden", "world6_fragment_warden"]:
		assert_true(loop_ids.has(member),
			"CONTROL FAILED: the table-loop parser cannot see %s. GameLoop dispatches 20 fragment reveals through `for fid in _FRAGMENT_GATES: ... return fid`; if that stops parsing, every fragment bed reads as dead again and the allowlist grows back" % member)
	assert_false(loop_ids.has("world1_prologue"),
		"CONTROL FAILED: world1_prologue is returned as a LITERAL, not from a table loop — if the loop parser claims it, it is matching something other than dict keys")
	assert_eq(disp.find("\"tracks\": {"), -1,
		"CONTROL FAILED: music_manifest.json is in the dispatcher corpus — every id would match itself")

	## scene id -> its raw text
	var scenes: Dictionary = {}
	var cd := DirAccess.open("res://data/cutscenes")
	if cd != null:
		cd.list_dir_begin()
		var n: String = cd.get_next()
		while n != "":
			if n.ends_with(".json"):
				scenes[n.substr(0, n.length() - 5)] = FileAccess.get_file_as_string("res://data/cutscenes/" + n)
			n = cd.get_next()
		cd.list_dir_end()
	assert_gt(scenes.size(), 150, "SCOPE control: read %d cutscenes" % scenes.size())

	var stranded: Array[String] = []
	var revived: Array[String] = []
	for id in _manifest_ids():
		## Only ids with no consumer outside the cutscene corpus are candidates.
		var composed: bool = false
		for prefix in COMPOSED_FAMILIES.keys():
			if id.begins_with(str(prefix)):
				composed = true
		if composed or disp.find(id) >= 0:
			if KNOWN_WIRED_TO_DEAD_SCENES.has(id) and not composed:
				revived.append(id)
			continue
		var naming: Array[String] = []
		var live: bool = false
		for s in scenes.keys():
			if str(scenes[s]).find(id) >= 0:
				naming.append(str(s))
				if _scene_is_dispatched(str(s), disp):
					live = true
		if live and KNOWN_WIRED_TO_DEAD_SCENES.has(id):
			## The revival check above only sees ids reached through the DISPATCHER
			## text. This one is reached through a dispatched naming SCENE, and an
			## entry that goes stale on this route reported nothing at all —
			## measured 2026-09-11, when the loop-dispatch fix made this bed live
			## and its pin sat there inert in every arm.
			revived.append(id)
		if naming.is_empty() or live:
			continue
		if not KNOWN_WIRED_TO_DEAD_SCENES.has(id):
			stranded.append("%s <- %s" % [id, naming])

	assert_eq(stranded.size(), 0,
		"beds cued ONLY by cutscenes no dispatcher can play (%d): %s — the cue exists, so nothing reports it missing, and the bed still never sounds. DISPATCH CORPUS: %s. FORMS ATTRIBUTED (a floor): %s. FORMS THAT EXIST AND CANNOT BE ATTRIBUTED (also a floor): %s — a bed reached only through one of those strands here as a FALSE ALARM, so treat this list as candidates, not a verdict. A bed is dead only if no FOURTH form exists — the loop form was invisible here until 2026-09-11 and 20 scenes read as dead the whole time" % [stranded.size(), stranded, DISPATCH_ROOTS, DISPATCH_FORMS, UNATTRIBUTABLE_FORMS])
	assert_eq(revived.size(), 0,
		"pinned beds whose scene is now dispatched (%s) — the epilogue landed; delete the entries" % [revived])


## ⛔ THIS FILE IS THE SECOND CENSUS OF THE SAME SET, AND I WROTE IT WITHOUT
## KNOWING THE FIRST EXISTED. test_unreachable_music_is_pinned (2026-09-09)
## already pinned all ten — the seven ambient beds AND the three cutscene ones —
## with the git provenance proving them stillborn rather than superseded, and
## with the two-manifest mechanism spelled out. Its header even records the
## mistake I then made twice today: "my first pass called those three REACHABLE
## because the literal appears in OverworldScene — conflating 'this key appears
## in code' with 'this manifest entry is reachable'."
##
## 🔑 SO THE LISTS ARE TIED TOGETHER RATHER THAN ONE BEING DELETED. That file is
## the AUTHORITY for which beds are unreachable: it carries the evidence and the
## decision framing for struktured. This file carries the reachability MODEL —
## composed families, the brief pre-flight, shadowing, stranded cues — which is
## a different job on a wider corpus. Deleting either loses something.
##
## What must never happen again is the two drifting: my own guard reported 4,
## then 5, against a file that had said 7 since September, and nothing compared
## them. Now nothing CAN: this arm fails the moment they disagree, in either
## direction, so a future wrong count reds instead of being published.
const PEER_GUARD := "res://test/unit/test_unreachable_music_is_pinned.gd"


func _peer_pins() -> Array[String]:
	var src: String = FileAccess.get_file_as_string(PEER_GUARD)
	assert_gt(src.length(), 2000,
		"SCOPE control: %s read back %d chars — if it was renamed or retired, this agreement arm is measuring nothing and must be re-pointed, not deleted" % [PEER_GUARD, src.length()])
	var out: Array[String] = []
	for name in ["KNOWN_UNREACHABLE_CUTSCENE_TRACKS", "KNOWN_UNREACHABLE_AMBIENT_TRACKS"]:
		var at: int = src.find(name)
		assert_gt(at, 0, "SCOPE control: %s no longer declares %s" % [PEER_GUARD, name])
		if at < 0:
			continue
		## The declaration is `const NAME: Array[String] = [` — the type carries
		## its own brackets, so anchor on the assignment, not the first "[".
		var open_b: int = src.find("= [", at)
		var close_b: int = src.find("\n]", open_b)
		var block: String = src.substr(open_b, close_b - open_b)
		var re := RegEx.new()
		re.compile("\"([a-z0-9_]+)\"")
		for m in re.search_all(block):
			if not out.has(m.get_string(1)):
				out.append(m.get_string(1))
	out.sort()
	return out


func test_this_pin_agrees_with_the_older_census() -> void:
	var peer: Array[String] = _peer_pins()
	assert_gt(peer.size(), 5,
		"SCOPE control: parsed only %d pins from the peer guard — the `Array[String]` type annotation contains a bracket and broke an earlier parse of mine, yielding a silent zero" % peer.size())

	var mine: Array[String] = []
	for k in KNOWN_UNREACHED.keys():
		mine.append(str(k))
	mine.sort()

	var only_mine: Array[String] = []
	for k in mine:
		if not peer.has(k):
			only_mine.append(k)
	var only_peer: Array[String] = []
	for k in peer:
		if not mine.has(k):
			only_peer.append(k)

	assert_eq(only_mine.size(), 0,
		"this file pins beds the older census does not (%s) — one of the two is wrong about the same question; reconcile them rather than letting a reader find both" % [only_mine])
	assert_eq(only_peer.size(), 0,
		"the older census pins beds this file calls reached (%s) — that is the direction that cost two wrong counts today, because a smaller number looks like progress" % [only_peer])


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
	## ⛔ TWO CAUSES LOOK IDENTICAL HERE and the message used to name only one. A
	## pin drops out of `unreached` because the bed got WIRED — or because the
	## track was DELETED from the manifest entirely, which cowir-adhoc calls
	## inert-by-deletion. Measured 2026-09-11 by removing ambient_ocean: caught,
	## but told to "delete the entries so they are covered like the rest", which
	## is the right action for the wrong reason and sends the reader looking for
	## a consumer that was never added.
	var ids_now: Dictionary = {}
	for id in _manifest_ids():
		ids_now[id] = true
	var wired: Array[String] = []
	var deleted: Array[String] = []
	for id in KNOWN_UNREACHED.keys():
		var k: String = str(id)
		if unreached.has(k):
			continue
		if ids_now.has(k):
			wired.append(k)
		else:
			deleted.append(k)

	assert_eq(added.size(), 0,
		"authored beds that NOTHING reaches and that are not pinned (%d): %s — a track was added to the manifest with no consumer, which is silence nobody will notice" % [added.size(), added])
	assert_eq(wired.size(), 0,
		"pinned beds that ARE now reached (%s) — they were wired; delete the entries so they are covered like the rest" % [wired])
	assert_eq(deleted.size(), 0,
		"pinned beds that are no longer IN THE MANIFEST (%s) — the track was deleted, not wired. Delete the pin here AND check the peer census, the brief in tools/music_prompts.json, and whether the OGG went with it" % [deleted])
