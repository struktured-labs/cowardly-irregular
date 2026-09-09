extends GutTest

## `alias_of` is DOCUMENTATION — assert it agrees with the routing (2026-09-09).
##
## Five keys share one bed: battle_brute.ogg serves battle_brute plus
## barbarian / cave_troll / ogre / troll, one creature class. The four
## non-canonical entries carry `alias_of: battle_brute`, and all five carry
## `repurposed_from: battle_goblin` — this bed WAS the goblin track before
## struktured's recast.
##
## ⚠️ NOTHING READS EITHER FIELD. Measured: 0 references to alias_of anywhere
## in src/. The routing runs entirely on `file`, and _try_play_from_manifest
## reads that. So alias_of is metadata that READS LIKE A MECHANISM — the same
## shape CLAUDE.md documents for sprite `tier`, and the shape cowir-battle hit
## today with summon_id / summon_count / summon_message: fields an author sets,
## with zero readers, where setting them looks like it did something.
##
## The failure it invites is specific: add `alias_of: battle_brute` to a new
## track and leave `file` unset or wrong, and the alias is silently inert — the
## track plays its own file, or nothing.
##
## Per CLAUDE.md's rule for two sources describing one thing: these are
## REDUNDANT (both should agree), so assert AGREEMENT rather than modelling
## precedence. Never silence it with a flag; make them agree.

const MANIFEST := "res://data/music_manifest.json"


func test_alias_of_agrees_with_the_file_that_actually_routes() -> void:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})
	assert_gt(tracks.size(), 100, "SCOPE control: manifest walked %d tracks" % tracks.size())

	var aliased: int = 0
	var broken: Array[String] = []
	for key in tracks.keys():
		var entry: Dictionary = tracks[key]
		var target: String = str(entry.get("alias_of", ""))
		if target == "":
			continue
		aliased += 1
		if not tracks.has(target):
			broken.append("%s -> alias_of '%s' which is not a track" % [key, target])
			continue
		var mine: String = str(entry.get("file", ""))
		var theirs: String = str((tracks[target] as Dictionary).get("file", ""))
		if mine == "":
			broken.append("%s declares alias_of %s but has NO file — the alias is inert, nothing routes" % [key, target])
		elif mine != theirs:
			broken.append("%s aliases %s but plays %s while %s plays %s" % [key, target, mine, target, theirs])

	## Control: the walk must FIND aliases, or a green means "nothing was checked".
	assert_gt(aliased, 0,
		"SCOPE control: no track declares alias_of — either the field was removed (delete this file) or the walk is broken")

	assert_eq(broken.size(), 0,
		"alias_of disagrees with the file that actually routes (%d): %s — nothing in src/ reads alias_of, so a mismatch is SILENT: the track plays its own file and the documented alias is a lie." % [broken.size(), broken])
