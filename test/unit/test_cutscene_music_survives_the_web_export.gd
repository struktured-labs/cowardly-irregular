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
const KNOWN_SILENT_ON_WEB := 21


func _web_exclude_patterns() -> PackedStringArray:
	var cfg: String = FileAccess.get_file_as_string(PRESETS)
	assert_gt(cfg.length(), 500, "SCOPE control: export_presets.cfg read back %d chars" % cfg.length())
	## The Web preset is the only one excluding music; take the LONGEST filter
	## rather than an index, which would silently follow a preset reorder.
	var best: String = ""
	for line in cfg.split("\n"):
		var l: String = str(line)
		if l.begins_with("exclude_filter=") and l.length() > best.length():
			best = l
	var raw: String = best.substr(best.find("\"") + 1)
	raw = raw.substr(0, raw.rfind("\""))
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

	assert_true(silent.size() <= KNOWN_SILENT_ON_WEB,
		"MORE cutscene cues are dropped from the web build than the %d measured 2026-09-11 (now %d): %s — a newly authored W4-W6 cutscene cue is silent on web, and nothing else would have said so" % [KNOWN_SILENT_ON_WEB, silent.size(), silent])
	## And it must not silently shrink either: if the fallback lands, or the
	## exclusions change, this pin is stale and should be deleted rather than
	## left describing a state that no longer exists.
	assert_true(silent.size() >= KNOWN_SILENT_ON_WEB,
		"FEWER cutscene cues are web-silent than the %d pinned (now %d) — this was fixed or the export changed; delete the pin rather than leave it documenting history" % [KNOWN_SILENT_ON_WEB, silent.size()])


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
