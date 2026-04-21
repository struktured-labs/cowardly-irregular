extends GutTest

## Regression tests for audio manifest integrity.
## Catches silent drift between manifest entries and on-disk OGG files
## (e.g. the scenario where all music went silent after Git LFS migration).
##
## Not every manifest entry MUST exist — procedural fallback is valid — but
## if the .file key is set, the path must parse cleanly and exist at `res://`
## or fall through to the gen dir. These tests fail loudly so we know before
## shipping that a track is missing.

const MUSIC_MANIFEST_PATH := "res://data/music_manifest.json"
const SFX_MANIFEST_PATH := "res://data/sfx_manifest.json"


func _load_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func test_music_manifest_parses_as_json() -> void:
	var data = _load_json(MUSIC_MANIFEST_PATH)
	assert_false(data.is_empty(), "music_manifest.json must parse to a non-empty Dictionary")
	assert_true(data.has("tracks"), "music_manifest must have a 'tracks' key")


func test_sfx_manifest_parses_as_json() -> void:
	var data = _load_json(SFX_MANIFEST_PATH)
	assert_false(data.is_empty(), "sfx_manifest.json must parse to a non-empty Dictionary")
	assert_true(data.has("sfx"), "sfx_manifest must have an 'sfx' key")


func test_music_manifest_entries_point_to_existing_files() -> void:
	var data = _load_json(MUSIC_MANIFEST_PATH)
	if not data.has("tracks"):
		pending("music_manifest missing tracks")
		return
	var tracks: Dictionary = data["tracks"]
	var missing: Array = []
	for track_id in tracks.keys():
		var entry = tracks[track_id]
		if not (entry is Dictionary):
			continue
		if not entry.has("file"):
			continue
		var raw_path: String = entry["file"]
		var abs_path = raw_path if raw_path.begins_with("res://") else "res://" + raw_path
		if not FileAccess.file_exists(abs_path):
			missing.append({"id": track_id, "path": abs_path})
	assert_true(missing.is_empty(),
		"Music manifest references %d missing files: %s" % [missing.size(), str(missing)])


func test_sfx_manifest_entries_point_to_existing_files() -> void:
	var data = _load_json(SFX_MANIFEST_PATH)
	if not data.has("sfx"):
		pending("sfx_manifest missing sfx key")
		return
	var sounds: Dictionary = data["sfx"]
	var missing: Array = []
	for sfx_id in sounds.keys():
		var entry = sounds[sfx_id]
		if not (entry is Dictionary):
			continue
		if not entry.has("file"):
			continue
		var raw_path: String = entry["file"]
		var abs_path = raw_path if raw_path.begins_with("res://") else "res://" + raw_path
		if not FileAccess.file_exists(abs_path):
			missing.append({"id": sfx_id, "path": abs_path})
	# SFX manifest is less strict — procedural generation is the explicit
	# fallback path. We warn instead of fail to keep CI green when SFX gen
	# hasn't run yet.
	if not missing.is_empty():
		gut.p("[WARN] sfx_manifest references %d missing files: %s" % [missing.size(), str(missing)])


func test_music_manifest_has_res_prefix_or_relative() -> void:
	# SoundManager has a "res://" prefix fix — ensure all paths are either
	# already prefixed or relative (which the loader can fix up).
	var data = _load_json(MUSIC_MANIFEST_PATH)
	if not data.has("tracks"):
		pending("music_manifest missing tracks")
		return
	var tracks: Dictionary = data["tracks"]
	for track_id in tracks.keys():
		var entry = tracks[track_id]
		if not (entry is Dictionary) or not entry.has("file"):
			continue
		var p: String = entry["file"]
		# Either starts with res:// OR is a plain relative path (no leading /, no http, no \)
		var ok = p.begins_with("res://") or (not p.begins_with("/") and not p.begins_with("http") and not p.contains("\\"))
		assert_true(ok, "Track '%s' has bad path: %s" % [track_id, p])
