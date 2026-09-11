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
	if _dual_store_ids().has(id):
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
const KNOWN_WIRED_TO_DEAD_SCENES := {
	"credits_digital": "world5_epilogue — unplayable; cowir-story has it queued",
	"credits_industrial": "world4_epilogue — unplayable; queued",
	"credits_steampunk": "world3_epilogue — cowir-story ruled it SUPERSEDED by world3_chapter5, so this may never wire",
	"credits_suburban": "world2_epilogue — ruled SUPERSEDED by world2_chapter11, same",
	"cutscene_w5_cached_memory": "all four world6_fragment_* scenes, none dispatched",
}


## Everything that could DISPATCH a cutscene — source, scenes, and non-cutscene
## data. Deliberately excludes data/cutscenes/: a scene names its own id, so
## including them would make every scene look dispatched by itself.
func _dispatcher_text() -> String:
	var paths: Array[String] = []
	_files("res://src", ".gd", paths)
	_files("res://src", ".tscn", paths)
	var parts: PackedStringArray = []
	for p in paths:
		parts.append(_strip_comments(FileAccess.get_file_as_string(p)) if p.ends_with(".gd") else FileAccess.get_file_as_string(p))
	var d := DirAccess.open("res://data")
	if d != null:
		d.list_dir_begin()
		var n: String = d.get_next()
		while n != "":
			if n.ends_with(".json") and n != "music_manifest.json" and n != "sfx_manifest.json":
				parts.append(FileAccess.get_file_as_string("res://data/" + n))
			n = d.get_next()
		d.list_dir_end()
	return "\n".join(parts)


## ⚠️ ONE-LEVEL, AND SAFE BY THE CORPUS RATHER THAN BY THE CODE. "The scene id
## appears in src/" does not ask whether the file naming it can itself run —
## cowir-adhoc's transitive hole. A scene dispatched only from MenuScene.gd (a
## 1,500-line hub nothing references, found dead 2026-09-11) would score
## playable here. They measured it: 0 of 124 called cutscenes have a dead file
## as their only caller, so the shortcut costs nothing TODAY. It is recorded
## rather than defended because the day that changes, nothing here will say so.
func test_no_bed_is_wired_only_to_a_cutscene_nothing_plays() -> void:
	var disp: String = _dispatcher_text()
	assert_gt(disp.length(), 500000,
		"SCOPE control: dispatcher corpus is %d chars — too small" % disp.length())
	assert_gt(disp.find("world1_prologue"), 0,
		"CONTROL FAILED: world1_prologue is dispatched by GameLoop but was not found — the corpus is wrong")
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
				if disp.find(str(s)) >= 0:
					live = true
		if naming.is_empty() or live:
			continue
		if not KNOWN_WIRED_TO_DEAD_SCENES.has(id):
			stranded.append("%s <- %s" % [id, naming])

	assert_eq(stranded.size(), 0,
		"beds cued ONLY by cutscenes no dispatcher can play (%d): %s — the cue exists, so nothing reports it missing, and the bed still never sounds" % [stranded.size(), stranded])
	assert_eq(revived.size(), 0,
		"pinned beds whose scene is now dispatched (%s) — the epilogue landed; delete the entries" % [revived])


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
	var gone: Array[String] = []
	for id in KNOWN_UNREACHED.keys():
		if not unreached.has(str(id)):
			gone.append(str(id))

	assert_eq(added.size(), 0,
		"authored beds that NOTHING reaches and that are not pinned (%d): %s — a track was added to the manifest with no consumer, which is silence nobody will notice" % [added.size(), added])
	assert_eq(gone.size(), 0,
		"pinned beds that ARE now reached (%s) — they were wired; delete the entries so they are covered like the rest" % [gone])
