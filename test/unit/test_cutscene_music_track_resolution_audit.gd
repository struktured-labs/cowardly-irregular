extends GutTest

## Regression: cadence #5 scout 2026-07-16 — 5 cutscenes had play_music
## steps referencing track ids that don't exist in the music manifest:
##   world1_chapter3: 'dungeon'
##   world1_chapter7: 'town_w1'
##   world1_chapter8: 'mystery_w1'
##   world1_chapter9: 'cutscene_w1_palace'
##   world2_chapter11: 'cutscene_w2_coordinator_after'
##
## SoundManager.play_music silently falls to _start_overworld_music when a
## track is neither in the manifest nor a special-cased match arm. Result:
## dungeon and palace scenes played peaceful-overworld music. The 4 W1
## scenes ship in tonight's playtest.
##
## Test-existing sibling: test_cutscene_music_track_orphan_audit (allowlist +
## stale-pruner). That test allowlists a set of "planned but not yet
## authored" tracks; this one is the harder pin — any play_music track
## MUST resolve in the manifest OR the SoundManager match statement, no
## silent overworld fallback.

const MUSIC_MANIFEST := "res://data/music_manifest.json"
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _manifest_track_ids() -> Dictionary:
	var text := _read(MUSIC_MANIFEST)
	var parsed = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "music_manifest.json must parse as Dictionary")
	var tracks = parsed.get("tracks", {})
	assert_true(tracks is Dictionary and not tracks.is_empty(),
		"music_manifest.json must have a non-empty 'tracks' dictionary")
	var out: Dictionary = {}
	for k in tracks:
		out[str(k)] = true
	return out


func _special_case_track_ids() -> Dictionary:
	# Any track name that appears as a quoted string in SoundManager's
	# play_music match statement is intentionally handled (title / autogrind
	# / dungeon location mappings / village location mappings / etc.).
	# Grep them out of the source rather than hand-maintaining a list.
	var out: Dictionary = {}
	var src := _read(SOUND_MANAGER)
	var fn := src.find("func play_music(")
	assert_gt(fn, -1, "SoundManager.play_music must exist")
	# Bound the search at the next top-level func — special-cased tracks
	# all live inside play_music (the outer match).
	var end := src.find("\nfunc ", fn + 1)
	var body := src.substr(fn, end - fn) if end > -1 else src.substr(fn)
	var regex := RegEx.new()
	regex.compile('"([a-z_][a-z0-9_]*)"\\s*:')  # a quoted id followed by a colon = a match arm
	for m in regex.search_all(body):
		out[m.get_string(1)] = true
	return out


func _all_resolvable_tracks() -> Dictionary:
	var out := _manifest_track_ids()
	for k in _special_case_track_ids():
		out[k] = true
	return out


func test_dungeon_medieval_pin_replaces_generic_dungeon() -> void:
	# Direct pin for the fix: world1_chapter3 must use dungeon_medieval
	# (Whispering Cave dungeon), not the generic 'dungeon' that fell to
	# overworld music.
	var d = JSON.parse_string(_read("res://data/cutscenes/world1_chapter3.json"))
	assert_true(d is Dictionary, "world1_chapter3 must parse")
	var found_track := ""
	for step in d.get("steps", []):
		if step is Dictionary and step.get("type") == "play_music":
			found_track = str(step.get("track", ""))
			break
	assert_eq(found_track, "dungeon_medieval",
		"world1_chapter3 (Whispering Cave dungeon) must play dungeon_medieval — 'dungeon' isn't a manifest key and fell through to the peaceful overworld theme")


func test_every_cutscene_music_track_resolves() -> void:
	var resolvable := _all_resolvable_tracks()
	var offenders: Dictionary = {}  # track -> [example files]
	var dir = DirAccess.open("res://data/cutscenes")
	assert_not_null(dir, "cutscenes dir must open")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var path = "res://data/cutscenes/%s" % f
		var parsed = JSON.parse_string(_read(path))
		if not (parsed is Dictionary):
			continue
		for step in parsed.get("steps", []):
			if not (step is Dictionary) or step.get("type") != "play_music":
				continue
			var track := str(step.get("track", "")).strip_edges()
			if track == "" or resolvable.has(track):
				continue
			if not offenders.has(track):
				offenders[track] = []
			if offenders[track].size() < 3:
				offenders[track].append(f)
	if offenders.is_empty():
		assert_true(true)
		return
	var reports: Array = []
	for t in offenders:
		reports.append("'%s' (e.g. in %s)" % [t, ", ".join(offenders[t])])
	assert_true(false,
		"cutscene JSON references play_music tracks with no manifest entry or SoundManager match arm (silent overworld-music fallback):\n  %s" % "\n  ".join(reports))
