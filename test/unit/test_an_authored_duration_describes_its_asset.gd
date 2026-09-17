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

## Measured 2026-09-17: authored 5.0, file 8.0. CAUSE FOUND (cowir-music, from the entry's own
## `prompt`): the 5.0 is not a stale measurement of this file, it is the length of the RETIRED
## ElevenLabs asset. The shipped 8.0s file is a synthesised replacement built by
## tools/gen_steam_bed.py — periodic by construction, because the original was 3.0s of fade in a
## 5.0s file with a +53 dB wrap step. So the field and the file describe two different assets,
## which is why no "is this entry correct" check could resolve it.
## The regeneration hazard it created is CLOSED at the source (80ab31df3: elevenlabs_sfx.py now
## refuses any non-elevenlabs `source`, and this entry's is `sox_synth`). The number itself is
## still wrong and still his call: correct it to 8.0, or keep it as the request that produced the
## rebuild. Declared, not rewritten — rewriting would erase the only record of why the asset exists.
const KNOWN_DRIFT := {"weather_steam": "authored 5.0 is the RETIRED ElevenLabs asset's length; the shipped 8.0s file is the sox_synth rebuild — two assets, one field. Regen hazard closed by 80ab31df3"}


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
	## ⛔ EVERY ENTRY LANDS IN EXACTLY ONE BUCKET AND THEY MUST SUM. These three `continue`s used to
	## discard into an unnamed void under a single `checked > 100` floor — so 220 of 321 entries
	## could stop being checked and this arm still passed. A silent skip is a finding.
	var untimed: Array = []
	var no_file: Array = []
	var undecodable: Array = []
	for k in sfx.keys():
		var e = sfx[k]
		if not (e is Dictionary) or not e.has("duration_seconds"):
			untimed.append(str(k))
			continue
		var f: String = str(e.get("file", ""))
		if f == "":
			no_file.append(str(k))
			continue
		var actual: float = _length_of(f)
		if actual < 0.0:
			undecodable.append(str(k))
			continue
		checked += 1
		var delta: float = absf(actual - float(e["duration_seconds"]))
		if delta > TOLERANCE_SECONDS and not KNOWN_DRIFT.has(str(k)):
			drifted.append("%s authored %.1f vs %.2f on disk (delta %.2f)" % [str(k), float(e["duration_seconds"]), actual, delta])
	assert_eq(checked + untimed.size() + no_file.size() + undecodable.size(), sfx.size(),
		"the buckets do not sum to the manifest — an entry left the partition and is judged by nothing")
	assert_eq(no_file, [],
		"manifest entries with a duration and an EMPTY file (%d): %s" % [no_file.size(), no_file])
	assert_eq(undecodable, [],
		"manifest entries whose file does not decode (%d) — the duration describes nothing: %s" % [undecodable.size(), undecodable])
	## The skip is pinned by its REASON, not by its count. An untimed entry is a hand-built asset
	## (`source_sha`, no generator prompt), so its length is not a generation parameter. A GENERATED
	## entry missing its duration is the real defect, and it lands here rather than in a bucket of 25.
	var untimed_without_reason: Array = []
	for k in untimed:
		if not (sfx[k] as Dictionary).has("source_sha"):
			untimed_without_reason.append(k)
	assert_eq(untimed_without_reason, [],
		"entries with no duration_seconds and no source_sha (%d) — a generated cue whose length nothing checks: %s" % [untimed_without_reason.size(), untimed_without_reason])
	assert_eq(drifted, [],
		"authored durations that do not describe their asset (%d) — regenerating these produces a different length than shipped: %s" % [drifted.size(), drifted])
	print("[duration-parity] %d of %d checked · %d untimed (hand-built) · %d declared drift" % [checked, sfx.size(), untimed.size(), KNOWN_DRIFT.size()])


func test_a_declared_drift_still_drifts() -> void:
	## Retirement trigger: fix the number or the asset and this entry must go, or it becomes a
	## standing exemption for a fact that stopped being true — which is how allowlists rot.
	var sfx: Dictionary = _sfx()
	assert_gt(sfx.size(), 0, "VOID, not clean: the sfx manifest read back 0 entries")
	## Without this the arm goes VACUOUS exactly when it succeeds: an empty KNOWN_DRIFT means the
	## loop below never runs and only the manifest floor asserts, so a retired list leaves a guard
	## that passes about nothing, forever, with nothing telling anyone to remove it.
	## (cowir-autogrind hit the same shape when their ignore census reached zero.)
	assert_gt(KNOWN_DRIFT.size(), 0,
		"KNOWN_DRIFT is empty — every declared drift is resolved, so DELETE THIS ARM with the last entry rather than leaving it asserting nothing")
	for k in KNOWN_DRIFT.keys():
		assert_true(sfx.has(k), "KNOWN_DRIFT names %s and the manifest has no such key" % k)
		var e: Dictionary = sfx[k]
		var actual: float = _length_of(str(e.get("file", "")))
		assert_gt(actual, 0.0, "CONTROL: %s must decode, or this arm cannot judge it" % k)
		assert_gt(absf(actual - float(e["duration_seconds"])), TOLERANCE_SECONDS,
			"%s no longer drifts — DELETE its KNOWN_DRIFT entry rather than leaving a standing exemption" % k)
		assert_gt(str(KNOWN_DRIFT[k]).length(), 40,
			"%s is declared without a reason long enough to be one" % k)
