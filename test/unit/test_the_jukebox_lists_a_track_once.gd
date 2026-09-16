extends GutTest

## The jukebox listed "Raid!" five times.
##
## `battle_brute.ogg` is named by five manifest keys under the monster-family ruling — a troll, a
## cave troll, an ogre, a barbarian and the brute itself share one theme. Four of those keys carry
## `alias_of: "battle_brute"`, and they carry its FILE and its TITLE too, so the jukebox built five
## rows that read identically and play the same bed:
##
##     battle_barbarian · battle_brute · battle_cave_troll · battle_ogre · battle_troll
##     all titled "Raid!", all assets/audio/music/battle_brute.ogg
##
## 🔑 THE ALIAS IS FOR `play_music`, WHICH ASKS FOR `battle_ogre`. A player browsing 165 rows is
## asking for a TRACK, and there are 161 of those. Nothing becomes unreachable: the bed is still
## one row away under its own name.
##
## ⛔ THE ALTERNATIVE WAS TO LABEL THEM, NOT HIDE THEM — "Raid! (Ogre)" and so on. Rejected: that
## adds four rows to scroll past for no new audio, in the one menu whose whole problem is length.
## Stated here so the choice is visible rather than implied by the diff.
##
## 📌 This gives `alias_of` its first runtime reader. It was provenance before — the routing works
## because each alias also carries `file`, and `alias_of` recorded WHY. It now also decides.

const JUKEBOX := preload("res://src/ui/JukeboxMenu.gd")
const MANIFEST := "res://data/music_manifest.json"


func _tracks_map() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: the manifest read back %d chars" % raw.length())
	return (JSON.parse_string(raw) as Dictionary).get("tracks", {})


func _alias_ids() -> Array:
	var out: Array = []
	for k in _tracks_map().keys():
		var e: Variant = _tracks_map()[k]
		if e is Dictionary and str((e as Dictionary).get("alias_of", "")) != "":
			out.append(str(k))
	out.sort()
	return out


## \u26d4 ONE TITLE IS AUTHORED TWICE ON TWO DIFFERENT BEDS, and hiding the aliases does not touch it.
## Declared rather than excluded from the check, so it cannot be silenced and a THIRD one reds:
##
##     overworld_abstract              1,144,648 B   128.8 s
##     cutscene_w6_entering_nothing    1,527,803 B   168.0 s
##
## Different files, different lengths, same name. Retitling one is authored content — a track title
## is writing, not data — so it is @struktured's call, not this lane's. The set must not grow OR
## shrink without this note changing: a shrink means somebody retitled one and did not say so.
const KNOWN_TITLE_COLLISIONS := {
	"The Answered Absence": ["cutscene_w6_entering_nothing", "overworld_abstract"],
}


func test_no_two_rows_read_the_same() -> void:
	var rows: Array = JUKEBOX._load_manifest_tracks()
	assert_gt(rows.size(), 100, "CONTROL: the jukebox built %d rows — it reads the live manifest" % rows.size())
	var by_title: Dictionary = {}
	for r in rows:
		var title: String = str(r[1])
		if not by_title.has(title):
			by_title[title] = []
		(by_title[title] as Array).append(str(r[0]))
	var undeclared: Array = []
	var declared_seen: Array = []
	for title in by_title.keys():
		var ids: Array = by_title[title]
		if ids.size() < 2:
			continue
		ids.sort()
		if KNOWN_TITLE_COLLISIONS.has(title) and ids == KNOWN_TITLE_COLLISIONS[title]:
			declared_seen.append(title)
			continue
		undeclared.append("%s: %s" % [title, str(ids)])
	assert_eq(undeclared.size(), 0,
		"%d jukebox rows read identically to another and are not declared: %s" % [undeclared.size(), str(undeclared)])
	## \u26d4 AND THE DECLARATION MUST STILL BE TRUE. A note that outlives its fact is worse than
	## none, because the next reader trusts it (@cowir-sprites, 2026-09-16).
	assert_eq(declared_seen.size(), KNOWN_TITLE_COLLISIONS.size(),
		"%d of %d declared collisions are no longer real — delete the entry that went away" % [declared_seen.size(), KNOWN_TITLE_COLLISIONS.size()])


func test_the_aliased_ids_are_not_rows() -> void:
	## Derived from the manifest, never a hardcoded list of four: a fifth alias must be excluded
	## too, and a hardcoded list would silently let it through.
	var aliases: Array = _alias_ids()
	assert_gt(aliases.size(), 0,
		"CONTROL: the manifest declares %d aliases — with none, this arm has no subject" % aliases.size())
	var ids: Array = []
	for r in JUKEBOX._load_manifest_tracks():
		ids.append(str(r[0]))
	for a in aliases:
		assert_false(ids.has(a), "%s is a routing alias and must not be its own jukebox row" % a)


func test_the_track_the_aliases_point_at_is_still_listed() -> void:
	## Hiding the aliases must not hide the bed. Every alias target is itself a row.
	var ids: Array = []
	for r in JUKEBOX._load_manifest_tracks():
		ids.append(str(r[0]))
	var m: Dictionary = _tracks_map()
	var checked: int = 0
	for a in _alias_ids():
		var target: String = str((m[a] as Dictionary).get("alias_of", ""))
		assert_true(ids.has(target),
			"%s aliases %s, which is not a row — the bed became unreachable from the jukebox" % [a, target])
		checked += 1
	assert_gt(checked, 0, "SCOPE control: walked %d aliases" % checked)


func test_every_other_authored_track_is_still_a_row() -> void:
	## ⛔ THE DANGEROUS DIRECTION. A filter that is too broad empties the menu, and "fewer rows" is
	## what this change looks like when it works — so the count alone cannot tell the two apart.
	## Require the row set to be EXACTLY the non-alias keys.
	var m: Dictionary = _tracks_map()
	var expected: Array = []
	for k in m.keys():
		var e: Variant = m[k]
		if e is Dictionary and str((e as Dictionary).get("alias_of", "")) == "":
			expected.append(str(k))
	expected.sort()
	var ids: Array = []
	for r in JUKEBOX._load_manifest_tracks():
		ids.append(str(r[0]))
	ids.sort()
	assert_eq(ids.size(), expected.size(),
		"the jukebox lists %d rows against %d non-alias tracks" % [ids.size(), expected.size()])
	var missing: Array = []
	for k in expected:
		if not ids.has(k):
			missing.append(k)
	assert_eq(missing.size(), 0, "these authored tracks lost their row: %s" % str(missing.slice(0, 8)))


func test_the_list_is_still_sorted_and_well_formed() -> void:
	## The skip runs inside the build loop; dropping an entry must not disturb the rest.
	var rows: Array = JUKEBOX._load_manifest_tracks()
	var prev: String = ""
	for r in rows:
		assert_gte(r.size(), 3, "each row stays [id, display, duration]")
		assert_true(str(r[1]).length() > 0, "%s has no display name" % str(r[0]))
		if prev != "":
			assert_true(str(r[0]) >= prev, "rows must stay sorted by id (saw %s after %s)" % [str(r[0]), prev])
		prev = str(r[0])
