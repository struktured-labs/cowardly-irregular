extends GutTest

## A measurement committed as data goes stale when the thing it measured is
## re-encoded, and nothing says so.
##
## `data/victory_downbeats.json` records the first-downbeat offset of every
## victory fanfare, measured 2026-08-17 (`b0fd4390`) so the overlay's title slam
## could land ON the downbeat. Since then ALL SEVEN beds were re-encoded by this
## lane's own trim passes — e26a38d9, 94000af3, 52e6715e — and every stored
## duration was wrong by 2.0 to 5.0 seconds.
##
## 🔑 A TAIL TRIM IS HARMLESS TO AN OFFSET AND A HEAD TRIM IS NOT, which is why
## the drift had to be measured per track rather than assumed from the fact of
## an edit. Five downbeats survived unchanged; two did not:
##
##     victory          718ms -> 188ms     the head lost ~530ms of lead-in
##     victory_digital  344ms -> 116ms
##
## Had the feature been wired before this was noticed, those two slams would
## have fired half a second late against audio that had already started.
##
## ⚠️ NOTHING READS THIS FILE YET. It is authored data with no consumer — the
## class four lanes found today in `one_shot`, the cutscene `trigger` field,
## `evolution` and `supports_json`. The wiring is a FEEL decision on
## VictoryOverlay, a surface struktured direction-locked on 2026-08-18, so it is
## not mine to make. What IS mine is that the number be true whenever someone
## does reach for it: a stale measurement that looks authoritative is worse than
## an absent one, because the consumer has no way to tell.

const DATA := "res://data/victory_downbeats.json"
const TOOL := "res://tools/measure_victory_downbeats.py"

## Godot's get_length() and the tool's ffmpeg probe agree to 1.0 ms across all
## seven files (measured 2026-09-11), so anything above that is a real edit.
## The ceiling comes from the smallest cut the lane's own tools will make:
## trim_wrap_padding's MIN_PAD_S is 40 ms, so 10 ms sits four times below the
## smallest trim that could move a downbeat and ten times above the residual.
const TOLERANCE_MS := 10.0


func _data() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(DATA)
	assert_gt(raw.length(), 200, "SCOPE control: %s read back %d chars" % [DATA, raw.length()])
	return JSON.parse_string(raw) as Dictionary


func test_control_the_data_and_its_audio_both_resolve() -> void:
	## Without this a broken path yields zero comparisons and the arm below
	## passes having measured nothing.
	var d: Dictionary = _data()
	assert_gt(d.size(), 5, "SCOPE control: parsed %d downbeat entries" % d.size())
	assert_true(d.has("victory_medieval"),
		"CONTROL FAILED: victory_medieval is not in the data — the file changed shape")
	var probe: AudioStream = load("res://assets/audio/music/victory_medieval.ogg") as AudioStream
	assert_not_null(probe,
		"CONTROL FAILED: victory_medieval.ogg does not load, so no duration can be compared")


func test_every_stored_duration_still_matches_its_file() -> void:
	## The staleness detector. `duration_ms` is recorded beside every offset, so
	## it dates the whole measurement for free: if the file is a different length
	## than when it was measured, the offsets were taken against audio that no
	## longer exists.
	var d: Dictionary = _data()
	var checked: int = 0
	var stale: Array[String] = []
	for key in d.keys():
		var k: String = str(key)
		var s: AudioStream = load("res://assets/audio/music/%s.ogg" % k) as AudioStream
		if s == null:
			stale.append("%s: the file does not load at all" % k)
			continue
		checked += 1
		var actual_ms: float = s.get_length() * 1000.0
		var stored_ms: float = float((d[k] as Dictionary).get("duration_ms", 0))
		if abs(actual_ms - stored_ms) > TOLERANCE_MS:
			stale.append("%s: file is %.0fms, measurement assumed %.0fms (%+.0fms)"
				% [k, actual_ms, stored_ms, actual_ms - stored_ms])
	assert_gt(checked, 5, "SCOPE control: compared only %d tracks" % checked)
	assert_eq(stale.size(), 0,
		"the downbeat measurement predates an edit to its audio (%d of %d): %s — re-run `uv run tools/measure_victory_downbeats.py --json`. A head trim moves every offset; a tail trim moves none, so the numbers cannot be repaired by arithmetic" % [stale.size(), checked, stale])


func test_the_regeneration_path_still_exists() -> void:
	## The failure message above tells the reader to re-run a tool. If that tool
	## is gone or renamed, the instruction is the only thing left and it is
	## wrong — the guard would report a real defect with an unusable fix.
	var tool: String = FileAccess.get_file_as_string(TOOL)
	assert_gt(tool.length(), 1000,
		"the tool this guard tells you to re-run (%s) is missing or empty" % TOOL)
	assert_gt(tool.find("victory_downbeats.json"), 0,
		"%s no longer writes victory_downbeats.json — the fix named in the failure message above would not repair anything" % TOOL)
