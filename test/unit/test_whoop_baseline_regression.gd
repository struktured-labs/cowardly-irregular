extends GutTest

## struktured rejected the same sound THREE times — fireball, then lightning, then the cure spell —
## because each fix touched a base and left its rotation siblings alone, and because the signature
## (spectral centroid climbing into the late third) is invisible to a whole-file spectrum. Two
## lanes measured these cues and called them fine.
##
## GUT cannot do an FFT, so the ratchet is split: tools/audit_whoop.py measures and records the
## sha256 of the exact bytes it measured; this test asserts the shipped bytes still hash to that.
## Re-roll a pinned cue and this reds, naming the tool — you must re-measure, not silently replace.

const BASELINE := "res://test/fixtures/sfx_whoop_baseline.json"
const MANIFEST := "res://data/sfx_manifest.json"


func _baseline() -> Dictionary:
	var raw := FileAccess.get_file_as_string(BASELINE)
	assert_ne(raw, "", "whoop baseline missing — run `tools/audit_whoop.py --write`")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "baseline did not parse")
	return (parsed as Dictionary).get("cues", {})


func test_no_pinned_cue_was_recorded_whooping() -> void:
	var cues := _baseline()
	assert_gt(cues.size(), 10, "baseline holds almost nothing — it was written against a broken scan")
	assert_true(cues.has("ability_fire"), "baseline lacks ability_fire, a known-pinned member — it is not the file we think")
	var whooping: Array = []
	for k in cues:
		if bool((cues[k] as Dictionary).get("whoops", false)):
			whooping.append(k)
	if not whooping.is_empty():
		fail_test("cues recorded as WHOOPING in the baseline — he has rejected this sound three times: %s" % [whooping])


func test_the_baseline_was_written_by_the_TREND_AWARE_tool() -> void:
	## The metric changed on 2026-09-09: mean-of-thirds COMPRESSED a monotonic ramp, so a synthetic
	## glide with a true 3.43x centroid ratio reported 2.10x and passed a 2.5x threshold. It fired
	## on the extremes and so looked like it worked while being blind to the case struktured
	## complained about.
	##
	## THE HAZARD THIS CLOSES: every assert in this file reads the baseline FILE. A baseline written
	## by the OLD tool records old-metric verdicts, and "no pinned cue was recorded whooping" is
	## then true of a measurement that could not see the defect. Reverting tools/audit_whoop.py
	## would leave this whole ratchet green while disarming it. The discriminator fields are the
	## only in-file evidence of WHICH instrument produced the numbers.
	var cues := _baseline()
	var missing: Array = []
	for k in cues:
		var e := cues[k] as Dictionary
		if not (e.has("rho_time") and e.has("rho_energy") and e.has("low_hz") and e.has("high_hz")):
			missing.append(k)
	assert_gt(cues.size(), 10, "control: baseline nearly empty — the loop below checked almost nothing")
	if not missing.is_empty():
		fail_test("%d pinned cue(s) lack the trend fields — the baseline was written by the pre-2026-09-09 mean-of-thirds tool, which cannot see a 3.4x glide. Re-run `tools/audit_whoop.py --write`: %s" % [missing.size(), missing])


func test_recorded_sweep_is_the_excursion_not_the_endpoints() -> void:
	## Guards the specific regression: excursion (high/low) must be at least the endpoint ratio.
	## If someone restores mean-of-thirds, recorded sweeps drop below high_hz/low_hz and this reds.
	var cues := _baseline()
	var wrong: Array = []
	var checked := 0
	for k in cues:
		var e := cues[k] as Dictionary
		var lo := float(e.get("low_hz", 0.0))
		var hi := float(e.get("high_hz", 0.0))
		if lo <= 0.0 or hi <= 0.0:
			continue
		checked += 1
		## allow rounding slack; the compression this catches was 2.10 vs 3.43, not 0.01
		if float(e.get("sweep", 0.0)) < (hi / lo) - 0.05:
			wrong.append("%s: sweep %s but excursion %.2f" % [k, e.get("sweep"), hi / lo])
	assert_gt(checked, 10, "control: no cue carried low/high — this guard checked nothing")
	if not wrong.is_empty():
		fail_test("recorded sweep is smaller than the measured excursion — the endpoint-averaging metric is back: %s" % [wrong])


func test_shipped_bytes_match_what_was_measured() -> void:
	# The hash is of the actual audio, so this cannot drift without someone noticing.
	var cues := _baseline()
	var drifted: Array = []
	var checked := 0
	for k in cues:
		var e := cues[k] as Dictionary
		var path := "res://" + str(e.get("file", ""))
		if not FileAccess.file_exists(path):
			drifted.append("%s: file missing (%s)" % [k, path])
			continue
		assert_gt(FileAccess.get_file_as_bytes(path).size(), 0, "%s read as empty — the hash below would be of nothing" % k)
		var got: String = FileAccess.get_sha256(path)
		checked += 1
		if got != str(e.get("sha256", "")):
			drifted.append(k)
	assert_gt(checked, 10, "hashed almost nothing — this guard would pass vacuously")
	if not drifted.is_empty():
		fail_test("pinned cues changed since they were measured — re-run `tools/audit_whoop.py --write` and LISTEN before shipping: %s" % [drifted])


func test_every_pinned_cue_is_still_in_the_manifest() -> void:
	# A pin on a key nothing plays is inert — the allowlist trap, one layer over.
	var cues := _baseline()
	var raw := FileAccess.get_file_as_string(MANIFEST)
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "manifest did not parse")
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	assert_true(sfx.has("menu_select"), "manifest lacks a known-present key — not reading the file")
	var orphaned: Array = []
	for k in cues:
		if not sfx.has(k):
			orphaned.append(k)
	if not orphaned.is_empty():
		fail_test("baseline pins cues the manifest no longer has — the pin protects nothing: %s" % [orphaned])
