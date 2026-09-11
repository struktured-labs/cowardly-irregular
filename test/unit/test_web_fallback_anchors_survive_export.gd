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

## ⛔ THIS WAS A HAND-LIST AND FOUR OF ITS SEVEN ENTRIES WERE **FALSE** —
## cowir-sfx's third suppression shape (2026-09-09): never true, the mechanism
## simply unmodelled. No rot check can catch that; there is no transition.
##
## I listed battle_medieval / boss_medieval / danger_medieval / victory_medieval
## as fallback anchors "derived from SoundManager". Measured: ZERO literal
## occurrences of any of them in SoundManager.gd. Those families are built
## dynamically as "battle_" + suffix, so a web-excluded W5 track resolves to
## battle_digital and falls to PROCEDURAL generation — it never tries the
## medieval member. I had confused "the medieval member of a world-mapped
## family" with "a fallback target". The assertions passed anyway, for the
## wrong reason, protecting nothing.
##
## Only three were genuine, each named EXPLICITLY as a fallback:
##     _start_dungeon_music         -> dungeon_medieval
##     _start_village_music         -> village_medieval
##     _start_overworld_music       -> overworld_medieval
##
## ⛔ I THEN TRIED cowir-sfx's FIX SHAPE — model the mechanism, derive every
## literal passed to _try_play_from_manifest — AND REFUSED IT WITH THE NUMBER,
## the way cowir-overworld refused a guard suggested to them. It derives 18
## anchors and goes RED ON A HEALTHY TREE, naming six:
##     battle_abstract · battle_digital · battle_industrial
##     overworld_abstract · overworld_digital · overworld_industrial
## Those are not fallback targets. They are each world's FIRST attempt —
## _start_abstract_music tries overworld_abstract, then falls to procedural —
## so being web-excluded is the DESIGNED path, not a broken anchor. The
## derivation cannot tell "first attempt for this world" from "what another
## world falls back to", and a guard that reds on health is worse than the
## hand-list it replaced.
##
## So: a hand-list, but only the three that were VERIFIED BY READING, with the
## four false ones gone. Small enough to check, and each carries its call site.
const FALLBACK_ANCHORS: Array[String] = [
	"dungeon_medieval",    # _start_dungeon_music, when world_id != "medieval"
	"village_medieval",    # _start_village_music, the generic fallback
	## ⚠️ This entry's reason was WRONG until 2026-09-10. It named
	## _start_overworld_music, where overworld_medieval is that world's OWN
	## first-tier bed, not a fallback for anyone — so the message below ("worlds
	## 3-6 fall back to these") was true of the two above and false of this one.
	## Nothing fell back to it; the excluded worlds went straight to a 19.9s
	## main-thread generation. It is a real cross-world fallback now:
	"overworld_medieval",  # _start_abstract_music / _futuristic / _industrial
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
