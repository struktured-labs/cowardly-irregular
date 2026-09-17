extends GutTest

## sfx_manifest's `duration_seconds` is what tools/elevenlabs_sfx.py:137 REQUESTS when a cue is
## regenerated — `entry.get("duration_seconds", 1.0)`. Nothing in src/ reads it (checked across the
## whole tree, not just SoundManager: 0 hits), so playback is unaffected and the exposure is
## reproducibility — regenerate a cue whose authored length disagrees with its file and the
## replacement is a different length from the asset that shipped.
##
## The music half hit this first and its guard records why a lane-scoped check was not enough:
## `duration` looked inert against SoundManager and JukeboxMenu renders it on every row. Here the
## whole-tree check is the claim, not an assumption.
##
## Asserts against the DECODED STREAM rather than a recorded number, because a recorded number is
## exactly what is in question.

const MANIFEST := "res://data/sfx_manifest.json"
const TOLERANCE_SECONDS := 2.0

## Measured 2026-09-17: authored 5.0, file 8.0. One of the 18 looping ambience beds. Either the
## generator overshot and the manifest records the REQUEST, or the number is stale — struktured's
## call, so it is declared with its measurement rather than silently rewritten to match.
const KNOWN_DRIFT := {"weather_steam": "authored 5.0 vs an 8.0s file; a looping bed, so the loop period changes on regeneration"}


func _sfx() -> Dictionary:
	var t: String = FileAccess.get_file_as_string(MANIFEST)
	assert_ne(t, "", "sfx_manifest.json must be readable")
	var parsed = JSON.parse_string(t)
	if parsed is Dictionary:
		var s = parsed.get("sfx", {})
		return s if s is Dictionary else {}
	return {}


func _length_of(path: String) -> float:
	var res := path if path.begins_with("res://") else "res://" + path
	if not ResourceLoader.exists(res):
		return -1.0
	var stream = load(res) as AudioStream
	return stream.get_length() if stream != null else -1.0


func test_every_authored_duration_matches_its_file() -> void:
	var sfx: Dictionary = _sfx()
	assert_gt(sfx.size(), 0, "VOID, not clean: the sfx manifest read back 0 entries")
	var checked := 0
	var drifted: Array = []
	for k in sfx.keys():
		var e = sfx[k]
		if not (e is Dictionary) or not e.has("duration_seconds"):
			continue
		var f: String = str(e.get("file", ""))
		if f == "":
			continue
		var actual: float = _length_of(f)
		if actual < 0.0:
			continue
		checked += 1
		var delta: float = absf(actual - float(e["duration_seconds"]))
		if delta > TOLERANCE_SECONDS and not KNOWN_DRIFT.has(str(k)):
			drifted.append("%s authored %.1f vs %.2f on disk (delta %.2f)" % [str(k), float(e["duration_seconds"]), actual, delta])
	assert_gt(checked, 100,
		"CONTROL: only %d entries had both a duration and a decodable file — the reader is broken, not the data" % checked)
	assert_eq(drifted, [],
		"authored durations that do not describe their asset (%d) — regenerating these produces a different length than shipped: %s" % [drifted.size(), drifted])
	print("[duration-parity] %d authored durations checked, %d declared drift" % [checked, KNOWN_DRIFT.size()])


func test_a_declared_drift_still_drifts() -> void:
	## Retirement trigger: fix the number or the asset and this entry must go, or it becomes a
	## standing exemption for a fact that stopped being true — which is how allowlists rot.
	var sfx: Dictionary = _sfx()
	assert_gt(sfx.size(), 0, "VOID, not clean: the sfx manifest read back 0 entries")
	for k in KNOWN_DRIFT.keys():
		assert_true(sfx.has(k), "KNOWN_DRIFT names %s and the manifest has no such key" % k)
		var e: Dictionary = sfx[k]
		var actual: float = _length_of(str(e.get("file", "")))
		assert_gt(actual, 0.0, "CONTROL: %s must decode, or this arm cannot judge it" % k)
		assert_gt(absf(actual - float(e["duration_seconds"])), TOLERANCE_SECONDS,
			"%s no longer drifts — DELETE its KNOWN_DRIFT entry rather than leaving a standing exemption" % k)
		assert_gt(str(KNOWN_DRIFT[k]).length(), 40,
			"%s is declared without a reason long enough to be one" % k)
