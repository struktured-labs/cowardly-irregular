extends GutTest

## The Rat King was the only W1 boss without a composed track — every other boss had one and
## the tutorial boss, the climax of the alpha demo, fell back to procedural audio. The track
## landed 2026-08-26 (struktured: "I head it- its fine").
##
## Shipping the OGG is NOT the same as playing it. SoundManager.play_music consults the manifest
## FIRST and returns on success, then falls through to `match track: "boss_rat_king":
## _start_rat_king_music()`. A manifest entry missing its `file` key makes
## _try_play_from_manifest return false and the procedural generator wins — silently, with the
## audio sitting on disk unreferenced. That is the failure this file exists to catch.

const MANIFEST := "res://data/music_manifest.json"
const OGG := "res://assets/audio/music/boss_rat_king.ogg"


func _entry() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_not_null(f, "CONTROL: the manifest must be readable")
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	var stack: Array = [d]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Dictionary:
			var nd: Dictionary = n
			if nd.has("boss_rat_king"):
				var e = nd["boss_rat_king"]
				return e if e is Dictionary else {}
			for k in nd:
				stack.append(nd[k])
	return {}


func test_the_audio_actually_ships() -> void:
	assert_true(ResourceLoader.exists(OGG), "the composed track must be in the export, not just the repo")
	var stream = load(OGG)
	assert_not_null(stream, "the track must load as an AudioStream")
	assert_gt(stream.get_length(), 30.0, "a boss theme under 30s is a stub, not a track")


func test_the_manifest_entry_carries_a_FILE_so_the_composed_path_wins() -> void:
	# THE load-bearing assertion. Without `file`, _try_play_from_manifest returns false and
	# play_music falls through to _start_rat_king_music() — the OGG ships and never plays.
	var e := _entry()
	assert_false(e.is_empty(), "boss_rat_king must exist in the manifest")
	assert_ne(str(e.get("file", "")), "", "the entry needs a non-empty 'file' or the procedural fallback wins")
	assert_true(ResourceLoader.exists("res://" + str(e.get("file", "")).trim_prefix("res://")),
		"the manifest's file path must resolve: %s" % str(e.get("file", "")))


func test_it_is_no_longer_declared_a_placeholder() -> void:
	var e := _entry()
	assert_false(bool(e.get("placeholder", false)), "placeholder must be cleared once the track lands")
	assert_false(e.has("planned_file"), "planned_file is the not-yet-generated marker and must be gone")


func test_the_declared_duration_matches_the_stream() -> void:
	# The Jukebox renders the manifest value; a stale 0.0 shows a blank row.
	var e := _entry()
	var declared := float(e.get("duration", 0.0))
	assert_gt(declared, 0.0, "duration 0.0 renders as a blank Jukebox row")
	var stream = load(OGG)
	assert_almost_eq(declared, stream.get_length(), 2.0,
		"manifest says %.2fs, stream is %.2fs" % [declared, stream.get_length()])


func test_the_procedural_fallback_is_still_present_as_a_safety_net() -> void:
	# Keeping it is deliberate: it sits BELOW the manifest path, so it costs nothing while the
	# track resolves and saves the fight if the audio ever fails to load in an export.
	var src := FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	assert_true(src.contains("_start_rat_king_music"), "the fallback generator must remain")


func test_every_w1_boss_now_has_a_composed_track() -> void:
	# The gap this closes, asserted as a set rather than for the Rat King alone — so a future
	# boss added without audio fails here rather than being noticed by a player.
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	var missing: Array = []
	var checked := 0
	var stack: Array = [d]
	while not stack.is_empty():
		var n = stack.pop_back()
		if not (n is Dictionary):
			continue
		var nd: Dictionary = n
		for k in nd:
			var v = nd[k]
			if str(k).begins_with("boss_") and v is Dictionary:
				checked += 1
				if str((v as Dictionary).get("file", "")) == "":
					missing.append(str(k))
			elif v is Dictionary:
				stack.append(v)
	assert_gt(checked, 5, "CONTROL: found %d boss entries — a 0 here means the walk is dead" % checked)
	assert_eq(missing.size(), 0, "boss tracks with no file: %s" % str(missing))
