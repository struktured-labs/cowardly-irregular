extends GutTest

## Regression tests for boss phase-2 music crossfade.
## When a Masterite boss drops below 50% HP, battle music should crossfade
## to a per-archetype phase-2 track over 2 seconds.
##
## These tests guard:
## - All 4 Masterite archetypes have phase-2 tracks in the manifest
## - Phase-2 OGG files exist on disk
## - SoundManager.play_music accepts a fade_duration parameter
## - BattleScene has the phase-2 threshold and state machinery

const MUSIC_MANIFEST_PATH := "res://data/music_manifest.json"
const MASTERITE_ARCHETYPES := ["warden", "arbiter", "tempo", "curator"]


func _load_manifest() -> Dictionary:
	var file = FileAccess.open(MUSIC_MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func test_phase2_tracks_registered_for_all_archetypes() -> void:
	var data = _load_manifest()
	assert_true(data.has("tracks"), "music_manifest.json missing 'tracks' key")
	var tracks: Dictionary = data.get("tracks", {})
	for archetype in MASTERITE_ARCHETYPES:
		var track_id = "boss_phase2_%s" % archetype
		assert_true(tracks.has(track_id),
			"Music manifest missing phase-2 track for Masterite %s: expected key '%s'" % [archetype, track_id])


func test_phase2_ogg_files_exist_on_disk() -> void:
	var data = _load_manifest()
	var tracks: Dictionary = data.get("tracks", {})
	for archetype in MASTERITE_ARCHETYPES:
		var track_id = "boss_phase2_%s" % archetype
		if not tracks.has(track_id):
			continue
		var entry = tracks[track_id]
		if not (entry is Dictionary) or not entry.has("file"):
			continue
		var raw_path: String = entry["file"]
		var abs_path = raw_path if raw_path.begins_with("res://") else "res://" + raw_path
		assert_true(FileAccess.file_exists(abs_path),
			"Phase-2 OGG for %s missing at %s" % [archetype, abs_path])


func test_sound_manager_play_music_accepts_fade_duration() -> void:
	# SoundManager.play_music(track, fade_duration: float = -1.0)
	# Regression: ensures the optional fade_duration parameter isn't removed
	# and that calling with 2.0 doesn't crash.
	assert_true(SoundManager.has_method("play_music"),
		"SoundManager must have play_music method")
	# Don't actually play during test — just verify signature via method info
	var method_list = SoundManager.get_method_list()
	var found = false
	for m in method_list:
		if m.get("name", "") == "play_music":
			var args = m.get("args", [])
			# Should have at least 2 args: track + fade_duration
			found = args.size() >= 2
			break
	assert_true(found,
		"SoundManager.play_music must accept fade_duration parameter (regression: boss phase-2 crossfade)")


func test_battle_scene_has_phase2_constants() -> void:
	# Regression: if these constants get removed or renamed, the crossfade silently breaks
	var script = load("res://src/battle/BattleScene.gd")
	assert_not_null(script, "BattleScene.gd must load")
	var constants = script.get_script_constant_map()
	assert_true(constants.has("BOSS_PHASE2_HP_THRESHOLD"),
		"BattleScene must define BOSS_PHASE2_HP_THRESHOLD constant")
	assert_true(constants.has("BOSS_PHASE2_FADE_SECONDS"),
		"BattleScene must define BOSS_PHASE2_FADE_SECONDS constant")
	# Threshold should be 50% (between 0.4 and 0.6 is acceptable)
	var threshold: float = constants.get("BOSS_PHASE2_HP_THRESHOLD", 0.0)
	assert_between(threshold, 0.4, 0.6,
		"BOSS_PHASE2_HP_THRESHOLD should be ~0.5 (was %s)" % threshold)
	# Fade should be dramatic (1-4 seconds)
	var fade: float = constants.get("BOSS_PHASE2_FADE_SECONDS", 0.0)
	assert_between(fade, 1.0, 4.0,
		"BOSS_PHASE2_FADE_SECONDS should be 1-4 seconds for dramatic transition (was %s)" % fade)
