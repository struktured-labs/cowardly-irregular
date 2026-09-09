extends GutTest

## The W1 tracks every web fallback lands on must never be export-excluded (2026-09-09).
##
## The Web preset drops 54 of 165 music tracks — everything matching
## *industrial*, *digital*, *abstract*, *futuristic* and cutscene_w4/5/6,
## because the itch.io HTML5 embed caps a single file near 200 MB. That is
## deliberate and the degradation is graceful: a W5 dungeon falls back to
## dungeon_medieval, a village to village_<world> then a procedural generator.
##
## The whole chain rests on a handful of MEDIEVAL anchors still being in the
## build. Nothing checked that. If a future exclude pattern widened — or one of
## these were renamed to contain a world word — worlds 3 to 6 would lose their
## music on web only, and no desktop run and no unit test would show it.
##
## This is the shape cowir-sfx named on items: the one case everybody tests is
## the one that works, and it certifies the ones that do not. W1 has its own
## files, so every W1 path is fine whatever happens here.
##
## Checked at the time of writing: all anchors survive. The guard is the point.

const MANIFEST := "res://data/music_manifest.json"
const PRESETS := "res://export_presets.cfg"

## Every fallback target reachable when a world-specific track is missing.
## Derived from SoundManager: _start_dungeon_music -> dungeon_medieval,
## _start_village_location_music -> village_<world>, and play_music's world
## mapping for the generic battle/boss/danger/victory keys.
const FALLBACK_ANCHORS: Array[String] = [
	"dungeon_medieval",
	"village_medieval",
	"battle_medieval",
	"boss_medieval",
	"danger_medieval",
	"victory_medieval",
	"overworld_medieval",
]


func _web_exclude_patterns() -> Array:
	var text: String = FileAccess.get_file_as_string(PRESETS)
	assert_gt(text.length(), 100, "SCOPE control: export_presets.cfg read back %d chars" % text.length())
	## Walk presets in order, keep the exclude_filter that follows name="Web".
	var out: Array = []
	var in_web: bool = false
	for line in text.split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("name="):
			in_web = t == 'name="Web"'
		elif in_web and t.begins_with("exclude_filter="):
			var raw: String = t.substr(t.find("=") + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
			for p in raw.split(","):
				var s: String = p.strip_edges()
				if s != "":
					out.append(s)
			break
	return out


func test_web_fallback_anchors_are_not_excluded() -> void:
	var patterns: Array = _web_exclude_patterns()
	assert_gt(patterns.size(), 5,
		"SCOPE control: parsed %d Web exclude patterns — the parse is broken and a green would be vacuous" % patterns.size())

	## Control: the parse must actually match something it is SUPPOSED to.
	var known_excluded: String = "assets/audio/music/battle_digital.ogg"
	var matched_control: bool = false
	for p in patterns:
		if known_excluded.match(p):
			matched_control = true
			break
	assert_true(matched_control,
		"CONTROL FAILED: a track we KNOW the Web preset drops (%s) matched no pattern — the filter parse is wrong, so the assertions below cannot detect anything" % known_excluded)

	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})

	var lost: Array[String] = []
	for key in FALLBACK_ANCHORS:
		assert_true(tracks.has(key), "fallback anchor %s is not in the manifest at all" % key)
		var f: String = str((tracks.get(key, {}) as Dictionary).get("file", ""))
		if f == "":
			lost.append("%s (no file)" % key)
			continue
		for p in patterns:
			if f.match(p):
				lost.append("%s matches %s" % [key, p])
				break

	assert_eq(lost.size(), 0,
		"Web export would drop a FALLBACK ANCHOR (%d): %s — worlds 3-6 fall back to these when their own tracks are excluded, so losing one makes those worlds silent ON WEB ONLY. No desktop run and no other test would show it." % [lost.size(), lost])
