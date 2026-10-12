extends GutTest

## `test_party_voice_pack_regression` asks whether every scripted line HAS a clip and whether every
## clip's file EXISTS. Neither question can see a clip that exists and holds the wrong audio, and the
## voice pipeline has a measured failure that produces exactly that: **the TTS server's first request
## after a cold boot returns HTTP 200 with an EMPTY BODY**, so a render can land as a valid file of
## no speech. I have hit that one for real; it is the reason this file exists rather than a
## hypothetical. 636 clips load in 246 ms, so the check is cheap.
##
## Measured over the 627 clips whose line is >= 8 characters (2026-10-12, 636 clips on disk):
##   sec/char   min 0.0525   p5 0.0650   median 0.0862   p95 0.1263   max 0.2412
##   as a multiple of the live median:   min 0.61x   max 2.80x
## A tight corpus, so the band below sits well clear of both ends while still catching a gross
## failure. ⚠️ WHAT IT CANNOT CATCH, stated so nobody over-reads a green: a SUBTLE truncation — the
## last word clipped, say 30% short — is inside the band. This catches an empty or near-empty render
## (decisively, via the absolute floor), a gross truncation, and a runaway generation. It says
## nothing about whether the clip speaks the RIGHT words; `source_sha` in the manifest is that guard.
##
## Everything is relative to the LIVE median, never a pinned number: a pipeline change (a different
## engine, a different speaking rate) moves every clip together and must not red. Three lines are
## shorter than 8 characters ('Noted.', 'Shh.', 'Begin.') and a 4-character denominator makes the
## rate meaningless, so they are judged by the absolute floor alone.

const SFX_DIR := "res://assets/audio/sfx"
const PERSONAS := "res://data/job_personas.json"
## 'Noted.' is the shortest real clip at 0.79s. An empty render is ~0.0s; the gap is 0.5s wide.
const MIN_CLIP_S := 0.5
const RATE_FLOOR_X := 0.35          # measured min 0.61x — 1.7x of headroom
const RATE_CEILING_X := 4.0         # measured max 2.80x — 1.4x of headroom
const MIN_LINE_CHARS := 8


## key -> the line it was cut from, built the way VoiceLines.variant_key builds the key, so the join
## is the consumer's own and not a second spelling of it.
func _line_for_key() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERSONAS))
	assert_true(parsed is Dictionary, "VOID: job_personas.json did not parse")
	if not (parsed is Dictionary):
		return {}
	var root: Dictionary = parsed as Dictionary
	var jobs: Dictionary = root.get("jobs", root)
	var out := {}
	for job_id in jobs:
		var tv: Dictionary = (jobs[job_id] as Dictionary).get("trigger_voices", {})
		for trig in tv:
			var entries: Array = VoiceLines.entries_of(tv[trig])
			for e in entries:
				var key: String = "voice_%s_%s" % [job_id, VoiceLines.variant_key(str(trig), int(e["index"]))]
				out[key] = str(e["line"])
	return out


## [{key, line, seconds}] for every voice clip on disk whose line resolves. voice_blip_* carry no
## line at all — they are text-advance blips of 0.04-0.13s by design — so they fall out naturally.
func _clips() -> Array:
	var lines := _line_for_key()
	assert_gt(lines.size(), 100, "VOID: only %d lines derived from job_personas, so the join below is empty" % lines.size())
	var out: Array = []
	var d := DirAccess.open(SFX_DIR)
	assert_not_null(d, "VOID: cannot open %s" % SFX_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.begins_with("voice_") and f.ends_with(".ogg") and not f.begins_with("voice_blip_"):
			var key := f.trim_suffix(".ogg")
			if lines.has(key):
				var stream: AudioStream = load("%s/%s" % [SFX_DIR, f])
				if stream != null:
					out.append({"key": key, "line": str(lines[key]), "seconds": stream.get_length()})
		f = d.get_next()
	d.list_dir_end()
	return out


func test_no_voice_clip_is_an_empty_render() -> void:
	## The failure I have actually hit: HTTP 200, empty body, a valid file of no speech. It passes
	## "the file exists" and every other arm in the pack guard.
	var clips := _clips()
	assert_gt(clips.size(), 100,
		"VOID: only %d voice clips joined to a line — the key shape or the manifest has moved and this arm is checking almost nothing" % clips.size())
	var empties: Array = []
	for c in clips:
		if float(c["seconds"]) < MIN_CLIP_S:
			empties.append("%s (%.2fs for %d chars)" % [c["key"], c["seconds"], str(c["line"]).length()])
	assert_eq(empties, [],
		"these voice clips are under %.2fs, which no spoken line is — the shortest real one is 'Noted.' at 0.79s. An empty or near-empty render passes every other arm in the pack guard: %s" % [MIN_CLIP_S, empties])


func test_every_clip_runs_at_a_plausible_speaking_rate() -> void:
	## RELATIVE to the live median, so a pipeline-wide change in speaking rate moves everything
	## together and reds nothing — the defect is one clip disagreeing with its siblings, not a number.
	var clips := _clips()
	var rates: Array[float] = []
	for c in clips:
		if str(c["line"]).length() >= MIN_LINE_CHARS:
			rates.append(float(c["seconds"]) / float(str(c["line"]).length()))
	assert_gt(rates.size(), 100, "VOID: only %d clips have a line long enough to rate" % rates.size())
	rates.sort()
	var median: float = rates[rates.size() / 2]
	## A broken join would make every line length 0 or 1 and the median absurd; 0.03..0.30 brackets
	## every plausible speaking rate and nothing else.
	## ⛔ THE REFERENCE ITSELF IS BOUNDED, because a relative band goes blind exactly when everything
	## breaks at once: regenerate the whole pack against a cold server and the median moves WITH the
	## corpus, so every empty clip reads as 1.0x of an empty median (@cowir-music raised this; the
	## scenario is reachable — a full 627-clip regeneration, where a 56-clip Fighter recast is only 9%
	## and reds per-clip). MEASURED with 320 of 627 planted empty: the median collapses to 0.0044 and
	## this fires. Two bounds, not one — the clip against the median, and the median against reality.
	var median_is_sane: bool = median >= 0.03 and median <= 0.30
	assert_true(median_is_sane,
		("the median rate is %.4f s/char, which is not a speaking rate at all, so the per-clip band below has no reference and is not run. TWO causes, and the per-clip floor tells you which: if many clips are also under %.2fs, the RENDERS are bad (a whole pack regenerated against a cold or misconfigured server); if they are fine, the line JOIN is broken and the denominators are wrong.") % [median, MIN_CLIP_S])
	var odd: Array = []
	## Only while the reference means something. With a collapsed median the band inverts and names
	## the HEALTHY clips as outliers — a long list pointing at the files that are fine, next to the one
	## message that names the true cause. The run is red either way; this keeps it red for one reason.
	for c in (clips if median_is_sane else []):
		var n: int = str(c["line"]).length()
		if n < MIN_LINE_CHARS:
			continue
		var rate: float = float(c["seconds"]) / float(n)
		if rate < median * RATE_FLOOR_X or rate > median * RATE_CEILING_X:
			odd.append("%s %.2fs for %d chars = %.3f s/char (%.2fx median)" % [c["key"], c["seconds"], n, rate, rate / median])
	assert_eq(odd, [],
		"these clips' durations are not explained by the length of the line they were cut from — under %.2fx the median rate reads as a truncated render, over %.2fx as a runaway generation (median %.4f s/char over %d clips): %s" % [RATE_FLOOR_X, RATE_CEILING_X, median, rates.size(), odd])


func test_the_band_is_wide_enough_for_the_corpus_that_exists() -> void:
	## The band is only honest if it is not grazing the live data: a threshold pinned just past the
	## current worst clip reds on the next legitimate one and gets widened by whoever is in a hurry.
	## This states the headroom as a fact, so a shrinking margin is visible before it is a false red.
	var clips := _clips()
	var rates: Array[float] = []
	for c in clips:
		if str(c["line"]).length() >= MIN_LINE_CHARS:
			rates.append(float(c["seconds"]) / float(str(c["line"]).length()))
	assert_gt(rates.size(), 100, "VOID: nothing to rate")
	rates.sort()
	var median: float = rates[rates.size() / 2]
	## Over the clips the band ACCEPTS, not all of them. Measured on a planted empty render: the
	## outlier dragged this arm red too, and its advice — "move the floor deliberately" — is the wrong
	## remedy for a bad clip. A second message pointing at the wrong fix is worse than silence; the arm
	## above already names the clip. Headroom is a claim about the healthy corpus.
	var inside: Array[float] = []
	for r in rates:
		if r >= median * RATE_FLOOR_X and r <= median * RATE_CEILING_X:
			inside.append(r)
	assert_gt(inside.size(), 100, "VOID: only %d clips fall inside the band, so there is no corpus to measure headroom over" % inside.size())
	var lo_x: float = inside[0] / median
	var hi_x: float = inside[inside.size() - 1] / median
	assert_gt(lo_x, RATE_FLOOR_X * 1.3,
		"the fastest clip sits at %.2fx the median against a floor of %.2fx — under 30%% headroom, so the next legitimate fast line will red. Re-measure the corpus and move the floor deliberately, do not nudge it." % [lo_x, RATE_FLOOR_X])
	assert_lt(hi_x, RATE_CEILING_X * 0.77,
		"the slowest clip sits at %.2fx the median against a ceiling of %.2fx — under 30%% headroom; same reasoning as the floor." % [hi_x, RATE_CEILING_X])
