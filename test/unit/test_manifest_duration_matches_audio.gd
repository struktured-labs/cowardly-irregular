extends GutTest

## Manifest `duration` must describe the file that actually ships (2026-09-09).
##
## This drift has happened twice and neither time was visible from inside the
## game: tools/trim_loop_seams.py shortened OGGs and left the manifest saying
## the old length (107 entries repaired by hand after the 2026-08-26 run), and
## the same tool did it again on a later batch. Nothing failed, nothing warned
## — the number is read by the Jukebox's M:SS display and by anything sizing a
## loop, so a stale value is a quiet lie rather than a crash.
##
## Godot can settle it without ffprobe: the imported AudioStream knows its own
## length. That makes this a CONTENT check, not a bookkeeping one — it compares
## the manifest against the audio the engine will actually play, so it also
## catches a track reverted to an older, longer render.
##
## Tolerance is deliberately loose (0.6s). Vorbis length via the import
## pipeline and the encoder's own idea of duration disagree in the third
## decimal, and the defect class this defends is measured in SECONDS (2-33s
## cuts), never in frames.

const MANIFEST := "res://data/music_manifest.json"
const TOLERANCE_S := 0.6

## A duration of 0.0 means "not rendered yet" by convention (JukeboxMenu reads
## it that way and prints no time), so it is a declaration, not a measurement.
const UNRENDERED := 0.0


func test_every_manifest_duration_matches_the_shipped_audio() -> void:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "manifest must parse to a Dictionary")
	var tracks: Dictionary = (parsed as Dictionary).get("tracks", {})
	assert_gt(tracks.size(), 100, "SCOPE control: manifest carries %d tracks" % tracks.size())

	var checked: int = 0
	var drifted: Array[String] = []
	var unloadable: Array[String] = []
	for key in tracks.keys():
		var entry: Variant = tracks[key]
		if not (entry is Dictionary):
			continue
		var f: String = str((entry as Dictionary).get("file", ""))
		if f == "":
			continue
		var declared: float = float((entry as Dictionary).get("duration", UNRENDERED))
		if declared == UNRENDERED:
			continue
		var res_path: String = f if f.begins_with("res://") else "res://" + f
		if not ResourceLoader.exists(res_path):
			unloadable.append("%s (%s)" % [key, f])
			continue
		var stream: Variant = load(res_path)
		if stream == null or not (stream is AudioStream):
			unloadable.append("%s (loaded as %s)" % [key, type_string(typeof(stream))])
			continue
		var actual: float = (stream as AudioStream).get_length()
		checked += 1
		if absf(actual - declared) > TOLERANCE_S:
			drifted.append("%s: manifest %.1fs vs audio %.1fs (%+.1fs)"
				% [key, declared, actual, actual - declared])

	assert_gt(checked, 100,
		"SCOPE control: only %d tracks were actually measured — the walk is broken, and a zero-drift result would be vacuous" % checked)
	assert_eq(unloadable.size(), 0,
		"manifest names audio that will not load (%d): %s — run --import, or the file is missing/an LFS pointer" % [unloadable.size(), unloadable])
	assert_eq(drifted.size(), 0,
		"manifest duration disagrees with the shipped audio (%d): %s — whatever rewrote the OGG did not rewrite the number. This is SILENT at runtime; the Jukebox just prints the wrong time." % [drifted.size(), drifted])
