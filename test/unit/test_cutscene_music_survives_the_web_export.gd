extends GutTest

## A cutscene's play_music cue is NOT protected by the _start_* fallbacks.
##
## Those live inside SoundManager's `match track:` arms and were given a
## shipped-bed tier in v3.33.294 so a W4-W6 battle could not reach a procedural
## generator on web. A cutscene does not go through them: it calls
## play_music("cutscene_w6_entering_nothing") directly, the manifest HAS the key
## (music_manifest.json ships in the pck; only the OGG is excluded), load()
## fails, and the `_:` arm catches nothing because the id begins with neither
## "battle_" nor "boss". It ends at push_warning.
##
## 🔑 SO THE FAILURE IS SILENCE, NOT A FREEZE — and it is silence AFTER the
## outgoing bed was already stopped, because play_music crossfades the old
## stream to player B before it discovers the new one is missing. The scene
## plays dead. That is strictly better than the 8.5s main-thread hang the
## generator tier caused, and it is still wrong.
##
## Measured 2026-09-11: 21 of the 42 music ids referenced by data/cutscenes/*
## are dropped by the Web preset's exclude_filter, including every world
## epilogue's credits roll and world6_ending — the campaign ending rolls its
## credits in silence on web.
##
## ⚠️ WHAT THIS TEST DOES NOT DO IS PICK A REPLACEMENT. Substituting
## credits_medieval for credits_abstract plays the WRONG music instead of none,
## and which bed stands in for a missing one is @struktured's call, not a
## defect I get to fix quietly. The pin records the set and its reason; it goes
## RED when the set GROWS, so a newly authored W4-W6 cutscene cue cannot join
## it unnoticed, and RED when it SHRINKS, so the pin cannot outlive the fix.

const MANIFEST := "res://data/music_manifest.json"
const PRESETS := "res://export_presets.cfg"
const CUTSCENE_DIR := "res://data/cutscenes"

## The 21 measured 2026-09-11. Not permission to stay — the count is asserted
## both ways below.
## 21 until 2026-09-11, when the three credits_* beds were un-excluded so the
## W4/W5/W6 credits rolls — world6_ending's included — are audible on web.
## 18 until 2026-09-11, when the nine cutscene_w6_* beds were un-excluded so
## world6_ending and world5_transition stop playing in silence on web.
## ⛔ THESE NUMBERS DESCRIBE A BUILD NOBODY SHIPS. Renamed 2026-09-11 after I
## reported them as player experience for a day and was wrong every time.
##
## deploy_web.sh publishes through make_web_stage.sh (WEB_STAGE=1, the DEFAULT).
## That stage swaps in a 48 kbps tier and then DELIBERATELY DROPS every music
## pattern from the Web preset's exclude_filter — "drop every music pattern that
## actually matches a master", derived, not hand-listed. Measured: 25 live music
## exclusions dropped, 161 of 161 masters packed, 0 deliberately excluded.
##
## So on the build in the store, EVERY bed ships. SoundManager.music_is_available
## decides by attempting load(), which answers from the pack — not from this
## filter, which nothing in src/ reads at all (0 occurrences).
##
## WEB_STAGE=0 is a faster direct export that deploy_web.sh itself labels
## "ships WITHOUT the W4-W6 endings". It is not the default and is not published.
## These two numbers are true of THAT export and of nothing a player runs.
##
## Kept rather than deleted because the fallback path still exists and a silent
## regression there is worth knowing about — but the name now says which build,
## so the next reader does not do what I did: read a config file, call it a
## player experience, and build a scene count, a budget argument and a ruling
## request on top of it.
const SILENT_ON_THE_FALLBACK_EXPORT := 9
## The consequence, not the cause. 9 BEDS are dropped; 5 SCENES go silent
## because they stop the music before requesting one. The other 21 restore the
## world's bed and are merely wrong-flavoured. world6_ending WAS in that set
## until the w6 beds shipped; the five that remain are W4 and W5 scenes.
const FALLBACK_EXPORT_SILENT_SCENES := 5


## ⛔ SELECT THE PRESET BY NAME. The first version of this took the LONGEST
## exclude_filter, having rejected taking the FIRST as "a proxy that follows a
## preset reorder" -- and then used a different proxy. Length is not identity.
## cowir-overworld scored six tracks against the FIRST filter (Linux, 134 chars,
## zero audio patterns) and got six-for-six "ships", which was the only answer
## that list could produce; one of the six is excluded. Mine is right today only
## because Web happens to be the longest, and a second preset gaining a long
## filter would silently redirect it.
func _web_exclude_patterns() -> PackedStringArray:
	var cfg: String = FileAccess.get_file_as_string(PRESETS)
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
		"SCOPE control: no preset named \"Web\" carries an exclude_filter — the config shape changed and every result below would describe the wrong build")
	var out: PackedStringArray = []
	for p in raw.split(","):
		var s: String = str(p).strip_edges()
		if s != "":
			out.append(s)
	return out


func _is_web_excluded(path: String, pats: PackedStringArray) -> bool:
	for p in pats:
		if path.match(p):
			return true
	return false


## Every music id a cutscene hands to play_music / roll_credits.
func _cutscene_music_ids() -> Dictionary:
	var out: Dictionary = {}
	var d := DirAccess.open(CUTSCENE_DIR)
	assert_true(d != null, "SCOPE control: cannot open %s" % CUTSCENE_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var n: String = d.get_next()
	var seen: int = 0
	while n != "":
		if n.ends_with(".json"):
			seen += 1
			var raw: String = FileAccess.get_file_as_string(CUTSCENE_DIR + "/" + n)
			var doc: Variant = JSON.parse_string(raw)
			if doc is Dictionary:
				_collect(doc, n.substr(0, n.length() - 5), out)
		n = d.get_next()
	d.list_dir_end()
	assert_gt(seen, 150, "SCOPE control: walked only %d cutscene files" % seen)
	return out


func _collect(node: Variant, scene: String, out: Dictionary) -> void:
	if node is Dictionary:
		var dict: Dictionary = node as Dictionary
		var t: String = str(dict.get("type", ""))
		## Two different keys carry a track: play_music uses `track`,
		## roll_credits uses `music`. Reading only the first misses every
		## credits roll, which is where the endings are.
		if t == "play_music" and str(dict.get("track", "")) != "":
			_note(out, str(dict["track"]), scene)
		if t == "roll_credits" and str(dict.get("music", "")) != "":
			_note(out, str(dict["music"]), scene)
		for k in dict.keys():
			_collect(dict[k], scene, out)
	elif node is Array:
		for v in (node as Array):
			_collect(v, scene, out)


func _note(out: Dictionary, id: String, scene: String) -> void:
	if not out.has(id):
		out[id] = []
	if not (out[id] as Array).has(scene):
		(out[id] as Array).append(scene)


func test_control_the_filter_and_the_walk_both_fire() -> void:
	## Without this, a broken parse yields zero excluded ids and the arm below
	## passes meaning "nothing measured" rather than "nothing broken".
	var pats: PackedStringArray = _web_exclude_patterns()
	assert_gt(pats.size(), 15, "SCOPE control: parsed %d exclude patterns" % pats.size())
	## A filter with no audio patterns at all is the Linux/macOS/Android shape,
	## and scoring audio against it returns "ships" for everything. Assert the
	## list can answer the question being asked of it.
	var audio_pats: int = 0
	for p in pats:
		if str(p).contains("assets/audio"):
			audio_pats += 1
	assert_gt(audio_pats, 3,
		"SCOPE control: the selected filter has %d audio patterns — that is a DESKTOP preset, and every track would score as shipping" % audio_pats)
	assert_true(_is_web_excluded("assets/audio/music/overworld_industrial.ogg", pats),
		"CONTROL FAILED: a known-excluded bed tests as included — the glob match has drifted")
	assert_false(_is_web_excluded("assets/audio/music/overworld_medieval.ogg", pats),
		"CONTROL FAILED: a shipped W1 bed tests as excluded — the filter is matching everything")

	var ids: Dictionary = _cutscene_music_ids()
	assert_gt(ids.size(), 20, "SCOPE control: found %d cutscene music ids" % ids.size())
	assert_true(ids.has("credits_medieval"),
		"CONTROL FAILED: credits_medieval not found, but world1_epilogue rolls it via a roll_credits step — the `music` key is not being read")


func test_every_cutscene_cue_resolves_in_the_manifest() -> void:
	## Separate from the web question: a cue naming nothing is silent on EVERY
	## platform, and none of these scenes have played, so none has been checked.
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	assert_gt(tracks.size(), 100, "SCOPE control: walked %d manifest tracks" % tracks.size())
	var ids: Dictionary = _cutscene_music_ids()
	var missing: Array[String] = []
	for id in ids.keys():
		if not tracks.has(str(id)):
			missing.append("%s <- %s" % [id, ids[id]])
	assert_eq(missing.size(), 0,
		"cutscenes play music ids absent from the manifest (%d): %s — play_music falls to push_warning and the scene is silent" % [missing.size(), missing])


func test_the_set_of_web_silent_cues_has_not_grown() -> void:
	var pats: PackedStringArray = _web_exclude_patterns()
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	var ids: Dictionary = _cutscene_music_ids()

	var silent: Array[String] = []
	for id in ids.keys():
		var e: Variant = tracks.get(str(id), null)
		if not (e is Dictionary):
			continue
		var f: String = str((e as Dictionary).get("file", ""))
		if f != "" and _is_web_excluded(f, pats):
			silent.append(str(id))
	silent.sort()

	assert_true(silent.size() <= SILENT_ON_THE_FALLBACK_EXPORT,
		"MORE cutscene cues are dropped from the WEB_STAGE=0 FALLBACK export (not the published build) than the %d measured 2026-09-11 (now %d): %s — a newly authored W4-W6 cutscene cue is silent on web, and nothing else would have said so" % [SILENT_ON_THE_FALLBACK_EXPORT, silent.size(), silent])
	## And it must not silently shrink either: if the fallback lands, or the
	## exclusions change, this pin is stale and should be deleted rather than
	## left describing a state that no longer exists.
	assert_true(silent.size() >= SILENT_ON_THE_FALLBACK_EXPORT,
		"FEWER cutscene cues are silent on the WEB_STAGE=0 FALLBACK export than the %d pinned (now %d) — this was fixed or the export changed; delete the pin rather than leave it documenting history" % [SILENT_ON_THE_FALLBACK_EXPORT, silent.size()])


## What a PLAYER experiences, which the cue count above does not measure.
##
## SILENT_ON_THE_FALLBACK_EXPORT counts BEDS whose file the Web preset drops — 18 of them.
## That is a property of the manifest and the preset. It is not the consequence,
## and reading it as one is how `world6_ending` went unnoticed: the campaign's
## closer plays its whole scene in SILENCE on web.
##
## CutsceneDirector splits these two ways, and only one is graceful:
##
##   cue unavailable, music still playing  -> restore_music_state, the world's
##                                            bed comes back. A wrong-flavoured
##                                            bed, not a hole.
##   cue unavailable AFTER a stop_music    -> "the scene stays as it is" —
##                                            SILENCE for the rest of the scene.
##
## The second is authored intent per CutsceneDirector's own comment (a scene that
## silenced the world should not have it restored behind its back), and it is
## still the number that decides whether the bytes are worth buying: 24.88 MiB of
## source, ~14 MiB at the shipped 48k tier, to give 14 scenes their cue back.
##
## Derived, never a hand-list: a scene authored tomorrow lands in whichever half
## its own step order puts it in.
func test_the_web_silent_population_is_reported_as_scenes() -> void:
	var pats: PackedStringArray = _web_exclude_patterns()
	var tracks: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) as Dictionary).get("tracks", {})
	assert_gt(tracks.size(), 100, "SCOPE control: walked %d manifest tracks" % tracks.size())
	var dir := DirAccess.open("res://data/cutscenes")
	assert_not_null(dir, "SCOPE control: the cutscene directory did not open")
	var silent: Array[String] = []
	var restores: Array[String] = []
	var walked: int = 0
	for f in dir.get_files():
		if not str(f).ends_with(".json"):
			continue
		walked += 1
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/" + str(f)))
		if not (d is Dictionary):
			continue
		var stopped: bool = false
		for step in (d as Dictionary).get("steps", []):
			if not (step is Dictionary):
				continue
			var t: String = str((step as Dictionary).get("type", ""))
			if t == "stop_music":
				stopped = true
			elif t == "play_music":
				var bed: String = str((step as Dictionary).get("track", (step as Dictionary).get("music", "")))
				if bed == "" or not tracks.has(bed):
					continue
				var file: String = str((tracks[bed] as Dictionary).get("file", ""))
				if file == "" or not _is_web_excluded(file, pats):
					continue
				var scene: String = str(f).replace(".json", "")
				if stopped:
					silent.append("%s (%s)" % [scene, bed])
				else:
					restores.append(scene)
	assert_gt(walked, 150, "SCOPE control: walked %d cutscene files" % walked)
	assert_gt(restores.size(), 0,
		"CONTROL FAILED: no scene reaches an excluded cue with music still playing. Both halves should be non-empty; one empty means the step-order read is broken, not that the population moved")
	assert_eq(silent.size(), FALLBACK_EXPORT_SILENT_SCENES,
		"scenes that play silent on the WEB_STAGE=0 FALLBACK export changed: %d, pinned %d. This is the player-facing half of SILENT_ON_THE_FALLBACK_EXPORT — those are beds, these are scenes. %s" % [silent.size(), FALLBACK_EXPORT_SILENT_SCENES, silent])


## The fact that makes every number above describe a build nobody ships, pinned
## so it cannot go invisible again. If the staged path ever stops dropping music
## exclusions, these counts start describing the store and this arm says so.
func test_the_published_path_drops_these_exclusions_entirely() -> void:
	var stage: String = FileAccess.get_file_as_string("res://tools/make_web_stage.sh")
	assert_gt(stage.length(), 2000, "SCOPE control: make_web_stage.sh read back %d chars" % stage.length())
	assert_true(stage.contains("assets/audio/music/"),
		"make_web_stage.sh no longer inspects music exclusions — the counts in this file may now describe the published build, which is the opposite of what its header says")
	assert_true(stage.contains("dropped.append"),
		"the staged export no longer DROPS music exclusions. That is the one fact making SILENT_ON_THE_FALLBACK_EXPORT a statement about a fallback rather than about the store — re-read this file's header before trusting either number")
	var deploy: String = FileAccess.get_file_as_string("res://tools/deploy_web.sh")
	assert_true(deploy.contains("WEB_STAGE:-1"),
		"deploy_web.sh no longer defaults to the STAGED export — if the direct export became the default, these counts describe the published build and the header is wrong")
	## And the filter is invisible to the game: nothing in src/ reads it, so no
	## runtime behaviour follows from it on any platform.
	var dir := DirAccess.open("res://src")
	assert_not_null(dir, "SCOPE control: src/ did not open")
	assert_eq(_count_in_tree("res://src", "exclude_filter"), 0,
		"something in src/ now reads exclude_filter — availability is decided by load() against the pack, and a second reader would change that")


func _count_in_tree(root: String, needle: String) -> int:
	var n: int = 0
	var dir := DirAccess.open(root)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var e: String = dir.get_next()
	while e != "":
		var path: String = root + "/" + e
		if dir.current_is_dir():
			n += _count_in_tree(path, needle)
		elif e.ends_with(".gd") and FileAccess.get_file_as_string(path).find(needle) >= 0:
			n += 1
		e = dir.get_next()
	dir.list_dir_end()
	return n


func test_no_cutscene_cue_can_reach_a_procedural_generator() -> void:
	## The freeze tier is the one that actually hurt (8.5s main-thread hangs,
	## v3.33.294). Confirm the cutscene door does not reopen it: SoundManager's
	## `_:` arm only routes ids beginning "battle_" or "boss" to a generator, so
	## a cutscene_* id ends at push_warning. If someone ever names a cutscene cue
	## "boss_something" that is NOT in the manifest, it would generate instead.
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	var ids: Dictionary = _cutscene_music_ids()
	var risky: Array[String] = []
	for id in ids.keys():
		var s: String = str(id)
		if tracks.has(s):
			continue
		if s.begins_with("battle_") or s.begins_with("boss"):
			risky.append("%s <- %s" % [s, ids[s]])
	assert_eq(risky.size(), 0,
		"cutscene cues that are absent from the manifest AND route to a generator (%d): %s — this is the 8.5s main-thread freeze door, reached from a cutscene instead of a battle" % [risky.size(), risky])
