extends GutTest

## Audit: cross-reference cutscene play_music step track names against
## music_manifest.json AND the known generic-alias / proc-gen handler
## lists in SoundManager.play_music. Pre-audit, 6 distinct music track
## names referenced by W1 chapters 7-9 and W2 chapter 11 cutscenes
## don't exist in any of the three resolvable paths — they get silently
## dropped at runtime, so the cutscene's intended atmospheric music
## simply doesn't play.
##
## Orphan-ratchet pattern (same shape as test_cutscene_grant_item_
## orphan_audit): NEW orphans fail loud; existing orphans being closed
## (track added to manifest or proc-gen handler) keeps passing; stale
## allowlist entries (now-resolved tracks still in KNOWN_ORPHAN_MUSIC)
## fail to force pruning.

const MUSIC_MANIFEST_PATH := "res://data/music_manifest.json"
const CUTSCENES_DIR := "res://data/cutscenes"
const SOUND_MANAGER_PATH := "res://src/audio/SoundManager.gd"

# Music track names that SoundManager.play_music resolves WITHOUT a
# manifest entry — generic aliases mapped to world-specific tracks, OR
# proc-gen handlers via _start_<name>_music. Verified by reading
# play_music's match blocks (lines ~1066 / ~1090 in SoundManager.gd).
const RESOLVED_VIA_ALIAS := {
	"battle": true,
	"boss": true,
	"danger": true,
	"victory": true,
	"title": true,
	"autogrind": true,
	"boss_rat_king": true,
	"game_over": true,
}


# Snapshot 2026-05-25 — cutscene play_music tracks referenced from
# JSON but not in music_manifest.json and not resolved via alias/proc-gen.
# Remove entries from this list as cowir-music authors the tracks (or
# corrects the cutscene JSON to point at a real manifest entry).
const KNOWN_ORPHAN_MUSIC := {
	"cutscene_w1_palace": true,
	"cutscene_w2_coordinator_after": true,
	"dungeon": true,
	"mystery_w1": true,
	"town_w1": true,
	"world3_overworld": true,  # Likely typo — manifest has `overworld_steampunk`
}


func _read_text(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func _load_manifest_tracks() -> Dictionary:
	var raw = _read_text(MUSIC_MANIFEST_PATH)
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary and parsed.has("tracks"):
		return parsed["tracks"]
	return {}


func _collect_cutscene_music_refs() -> Dictionary:
	## Returns {music_track: [cutscene_basenames]}.
	var refs: Dictionary = {}
	var dir = DirAccess.open(CUTSCENES_DIR)
	if dir == null:
		return refs
	dir.list_dir_begin()
	var name = dir.get_next()
	while name != "":
		if name.ends_with(".json"):
			var path = CUTSCENES_DIR + "/" + name
			var parsed = JSON.parse_string(_read_text(path))
			if parsed is Dictionary and parsed.has("steps"):
				for step in parsed["steps"]:
					if step is Dictionary and step.get("type", "") == "play_music":
						var track = str(step.get("track", ""))
						if track != "":
							refs[track] = refs.get(track, []) + [name]
		name = dir.get_next()
	return refs


func test_every_cutscene_music_track_resolves() -> void:
	var refs: Dictionary = _collect_cutscene_music_refs()
	var manifest: Dictionary = _load_manifest_tracks()
	assert_gt(refs.size(), 0, "Test setup: should find some cutscene music refs")
	assert_gt(manifest.size(), 50, "Test setup: music_manifest.json should have many tracks")

	var new_orphans: Array = []
	for track in refs:
		if manifest.has(track):
			continue
		if RESOLVED_VIA_ALIAS.has(track):
			continue
		if KNOWN_ORPHAN_MUSIC.has(track):
			continue
		new_orphans.append({
			"track": track,
			"sources": refs[track],
		})

	if not new_orphans.is_empty():
		var msg: String = "NEW orphan cutscene music tracks (no manifest entry, no alias, no proc-gen):\n"
		for o in new_orphans:
			msg += "  - %s (in: %s)\n" % [o.track, ", ".join(o.sources)]
		msg += "Either add the track to music_manifest.json OR fix the cutscene JSON OR add to KNOWN_ORPHAN_MUSIC."
		fail_test(msg)


func test_known_orphan_music_list_stays_pruned() -> void:
	## Inverse: KNOWN_ORPHAN_MUSIC entries that now DO exist in the
	## manifest or alias map must be removed — keeps the list honest.
	var manifest: Dictionary = _load_manifest_tracks()
	var stale: Array = []
	for orphan in KNOWN_ORPHAN_MUSIC:
		if manifest.has(orphan) or RESOLVED_VIA_ALIAS.has(orphan):
			stale.append(orphan)
	if not stale.is_empty():
		fail_test("KNOWN_ORPHAN_MUSIC contains entries that now DO resolve — remove them: %s" % [stale])


func test_alias_list_matches_sound_manager_dispatch() -> void:
	## Source pin: RESOLVED_VIA_ALIAS must match what SoundManager.play_music
	## actually handles. Catches drift where someone removes a play_music
	## case (e.g. retires "victory" alias) without updating this test, which
	## would let real orphans slip through.
	var sm_text = _read_text(SOUND_MANAGER_PATH)
	for alias in RESOLVED_VIA_ALIAS:
		# Either a match case OR a generic-alias rewrite must exist.
		var case_pat = "\"" + alias + "\":"
		assert_true(sm_text.find(case_pat) > -1,
			"SoundManager.play_music must still have a case for alias '%s' — RESOLVED_VIA_ALIAS is now stale" % alias)
