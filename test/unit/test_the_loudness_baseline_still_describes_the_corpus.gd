extends GutTest

## `data/loudness_baseline.json` is three summary numbers — `median_lufs`, `n_tracks`,
## `outlier_bound_lu` — and they are a claim ABOUT A CORPUS. Nothing checked that the corpus is still
## the one they describe, and @cowir-sfx measured the file at ZERO guards while sweeping data/.
##
## ⛔ WHAT THIS DOES **NOT** DO: it does not measure loudness. `tools/audit_loudness.py` does, it is
## the only consumer of this file, and NOTHING INVOKES IT — not tools/, not .github/. So no run
## compares any bed against this baseline. That is the larger gap and it is not closable in a unit
## test: EBU R128 over 165 tracks is minutes of work, and the tool's own `BASELINE_JITTER_LU` exists
## because R128 is not bit-reproducible.
##
## ⚠️ SO THIS GUARD IS DELIBERATELY NARROW: it catches the baseline going STALE, which is the failure
## that makes the outlier test meaningless without anything looking wrong. The tool's docstring names
## the scenario itself — NINE Suno tracks staged behind a ToS block, and "a bed arriving at -8 LUFS
## would be a 7 LU outlier and nothing else in the repo would notice".
##
## LATENT: in sync today (165 == 165).

const BASELINE := "res://data/loudness_baseline.json"
const MANIFEST := "res://data/music_manifest.json"


func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, "CONTROL: %s must parse as a Dictionary" % path)
	return parsed if parsed is Dictionary else {}


func test_the_baseline_track_count_matches_the_manifest() -> void:
	var base := _json(BASELINE)
	var man := _json(MANIFEST)
	## ANTI-VACUITY on both sides: a missing key would make the comparison trivially true.
	assert_true(base.has("n_tracks"),
		"ANTI-VACUITY: the baseline has no n_tracks key, so there is nothing to compare")
	var tracks = man.get("tracks", {})
	assert_true(tracks is Dictionary and (tracks as Dictionary).size() > 50,
		"ANTI-VACUITY: the manifest read back %d tracks" % [(tracks as Dictionary).size() if tracks is Dictionary else -1])

	var n: int = int(base.get("n_tracks", -1))
	var corpus: int = (tracks as Dictionary).size()
	assert_eq(n, corpus,
		"the loudness baseline describes %d tracks and the manifest now has %d. median_lufs %s and outlier_bound_lu %s are claims about a corpus that no longer exists, so the outlier test they define is against a stale reference — re-run `uv run tools/audit_loudness.py` and update data/loudness_baseline.json" % [n, corpus, str(base.get("median_lufs")), str(base.get("outlier_bound_lu"))])


func test_the_baseline_carries_the_numbers_its_only_consumer_reads() -> void:
	## The tool reads all three. A baseline missing one is not a stale-corpus problem — it is a file
	## the tool cannot use, and since nothing invokes the tool, nothing would report that either.
	var base := _json(BASELINE)
	var missing: Array = []
	for key in ["median_lufs", "n_tracks", "outlier_bound_lu"]:
		if not base.has(key):
			missing.append(key)
	assert_eq(missing.size(), 0,
		"data/loudness_baseline.json is missing %s — tools/audit_loudness.py reads all three and is this file's only consumer" % str(missing))
	assert_lt(float(base.get("median_lufs", 0.0)), 0.0,
		"median_lufs should be negative (LUFS below full scale); got %s" % str(base.get("median_lufs")))
	assert_gt(float(base.get("outlier_bound_lu", 0.0)), 0.0,
		"outlier_bound_lu is the +/- LU window an outlier must exceed; got %s" % str(base.get("outlier_bound_lu")))
