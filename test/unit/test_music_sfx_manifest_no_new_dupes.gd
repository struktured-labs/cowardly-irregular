extends GutTest

## Cross-manifest key-collision ratchet (2026-07-16).
##
## music_manifest.json and sfx_manifest.json use disjoint keyspaces at
## runtime: play_music() reads music_manifest, play_ambient() /
## play_ui() / play_sfx-family reads sfx_manifest. But nothing enforces
## the disjointness structurally — a key can exist in BOTH and neither
## side notices until someone refactors a lookup and silently gets a
## different track.
##
## As of 2026-07-16 four keys already collide (ambient_cave,
## ambient_forest, ambient_village, victory). The music_manifest side
## is dead code (no play_music consumer with those names in src/) but
## a naive future refactor of play_ambient to "check music_manifest
## first as override" would silently swap the tracks — the sfx side
## has the ambient loops OverworldScene expects; the music side has
## unrelated Suno tracks with the same key.
##
## Guarantees:
##   1. Any NEW cross-manifest key collision fails the gate.
##   2. Any KNOWN_CROSS_MANIFEST_DUPES entry that stops colliding fails
##      the gate until it's removed from the snapshot — no stale
##      allowlist entries.
##
## To resolve an entry cleanly: pick which manifest OWNS the key
## (typically sfx_manifest for the runtime consumer), delete the other
## side's entry AND move its .ogg out of assets/audio/music/ if the
## music-manifest side was the dead one. Then drop the entry here.


const MUSIC_MANIFEST := "res://data/music_manifest.json"
const SFX_MANIFEST := "res://data/sfx_manifest.json"

## Snapshot 2026-07-16. All four have music_manifest entries with no
## known runtime consumer; sfx_manifest side is the live consumer via
## SoundManager.play_ambient / stinger family.
const KNOWN_CROSS_MANIFEST_DUPES: Array[String] = [
	"ambient_cave",     # sfx-side: OverworldScene ice+swamp zones; music-side: "Dripping Stone" (dead)
	"ambient_forest",   # sfx-side: OverworldScene forest+swamp zones; music-side: "Whispering Canopy" (dead)
	"ambient_village",  # sfx-side: village ambient loop; music-side: "Market Morning" (dead)
	"victory",          # sfx-side: victory stinger; music-side: victory fanfare (both used — pattern differs)
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _keys_of(manifest_path: String, key_path: Array) -> Dictionary:
	## Parse a manifest and drill down to the container-of-tracks. key_path
	## is the list of dict keys to descend, e.g. ["tracks"] for music,
	## ["sfx"] for sfx.
	var text: String = _read(manifest_path)
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "%s must parse to a Dictionary" % manifest_path)
	var cursor: Variant = parsed
	for step in key_path:
		assert_true(cursor is Dictionary and cursor.has(step),
			"%s must contain nested key %s" % [manifest_path, step])
		cursor = cursor[step]
	assert_true(cursor is Dictionary, "%s[%s] must be a Dictionary" % [manifest_path, key_path])
	return cursor


func test_no_new_cross_manifest_key_dupes() -> void:
	var music := _keys_of(MUSIC_MANIFEST, ["tracks"])
	var sfx := _keys_of(SFX_MANIFEST, ["sfx"])

	var music_keys: Array[String] = []
	for k in music.keys():
		music_keys.append(str(k))
	var sfx_keys: Array[String] = []
	for k in sfx.keys():
		sfx_keys.append(str(k))

	var actual_dupes: Array[String] = []
	for k in music_keys:
		if k in sfx_keys:
			actual_dupes.append(k)
	actual_dupes.sort()

	var known_set: Dictionary = {}
	for k in KNOWN_CROSS_MANIFEST_DUPES:
		known_set[k] = true

	# Guarantee 1: no new dupes.
	var new_dupes: Array[String] = []
	for k in actual_dupes:
		if not known_set.has(k):
			new_dupes.append(k)
	assert_eq(new_dupes.size(), 0,
		"NEW cross-manifest key collision (%d): %s — pick which manifest owns the key (typically sfx_manifest for the runtime consumer), delete the other side, OR add to KNOWN_CROSS_MANIFEST_DUPES with a documented reason." % [new_dupes.size(), new_dupes])

	# Guarantee 2: no stale snapshot.
	var actual_set: Dictionary = {}
	for k in actual_dupes:
		actual_set[k] = true
	var stale_allowlist: Array[String] = []
	for k in KNOWN_CROSS_MANIFEST_DUPES:
		if not actual_set.has(k):
			stale_allowlist.append(k)
	assert_eq(stale_allowlist.size(), 0,
		"KNOWN_CROSS_MANIFEST_DUPES entries that no longer collide — remove them from the allowlist (%d): %s" % [stale_allowlist.size(), stale_allowlist])
