extends GutTest

## Manifest `duration` must match the audio it describes (2026-07-29).
##
## 65 of 152 entries disagreed with their file by more than 2s — worst case
## cutscene_w6_answer_exploit declaring 22.92s for a 144.5s track.
##
## I called this inert after checking SoundManager, which reads `file`,
## `fallback_to` and `loop` and never `duration`. That was correct and
## incomplete: JukeboxMenu.gd:96 reads it and renders it as an M:SS column on
## EVERY row, so ~65 wrong times were on a screen the player reads. The second
## consumer lives in src/ui/, owned by another lane, with nothing in the audio
## surface pointing at it — findable only by grepping the field name across the
## whole tree rather than across the lane that owns the data. (cowir-ai found
## it; the check that settles it is `grep -rn '"duration"' src/`.)
##
## This asserts against the STREAM, not against a recorded number, because the
## defect was precisely that the recorded number lied. Godot decodes the OGG,
## so get_length() reports what the engine — and the Jukebox — will actually
## use.

const MANIFEST := "res://data/music_manifest.json"
const TOLERANCE_SECONDS := 2.0


func _tracks() -> Dictionary:
	var t: String = FileAccess.get_file_as_string(MANIFEST)
	assert_ne(t, "", "music_manifest.json must be readable")
	var parsed = JSON.parse_string(t)
	if parsed is Dictionary:
		return parsed.get("tracks", parsed)
	return {}


## Entries that describe no audio yet. `boss_rat_king` omits `file` on purpose
## so the integrity audit doesn't fail on a known-pending placeholder, and its
## duration 0.0 is a SENTINEL — JukeboxMenu renders blank for it, meaning
## "unrendered". A mechanical pass that wrote a real number everywhere would
## destroy that signal silently, so it is skipped by the absence of `file`
## rather than by name.
func _describes_audio(entry: Dictionary) -> bool:
	return str(entry.get("file", "")) != ""


func test_positive_control_manifest_parses_and_has_audio_entries() -> void:
	var tracks := _tracks()
	assert_gt(tracks.size(), 100, "expected the full manifest — a short parse makes every check below vacuous")
	var with_audio := 0
	for k in tracks:
		if tracks[k] is Dictionary and _describes_audio(tracks[k]):
			with_audio += 1
	assert_gt(with_audio, 100, "expected >100 entries pointing at real audio")


func test_declared_duration_matches_the_stream() -> void:
	var tracks := _tracks()
	var offenders: Array = []
	var checked := 0
	for key in tracks:
		var entry = tracks[key]
		if not (entry is Dictionary) or not _describes_audio(entry):
			continue
		if not entry.has("duration"):
			continue
		var path: String = str(entry["file"])
		if not ResourceLoader.exists(path):
			continue
		var stream = load(path)
		if stream == null or not stream.has_method("get_length"):
			continue
		var actual: float = stream.get_length()
		if actual <= 0.0:
			continue
		checked += 1
		var declared: float = float(entry["duration"])
		if abs(actual - declared) > TOLERANCE_SECONDS:
			offenders.append("%s: manifest says %.2fs, stream is %.2fs (Jukebox renders the manifest value)" % [key, declared, actual])
	assert_gt(checked, 100, "positive control: expected to measure >100 streams — an empty offender list means nothing if nothing was measured")
	assert_eq(offenders, [], "\n".join(offenders))


func test_placeholder_sentinel_is_preserved() -> void:
	## 0.0 means "unrendered" and JukeboxMenu renders it blank. Pin it so a
	## future duration sweep can't quietly turn the signal into a time.
	var tracks := _tracks()
	for key in tracks:
		var entry = tracks[key]
		if not (entry is Dictionary):
			continue
		if _describes_audio(entry):
			assert_ne(float(entry.get("duration", 0.0)), 0.0,
				"%s points at real audio, so 0.0 would render a blank Jukebox row" % key)
		elif entry.has("duration"):
			assert_eq(float(entry["duration"]), 0.0,
				"%s describes no audio yet — its duration must stay the 0.0 blank sentinel" % key)
