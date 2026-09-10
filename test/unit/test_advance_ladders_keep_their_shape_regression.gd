extends GutTest

## The two per-job advance ladders escalate in OPPOSITE directions, and that is the joke.
##
##   FIGHTER  ascends  — steel: blade tap -> draw+shield -> full-draw CLANG -> shield slam -> a wall
##   ROGUE    DESCENDS — the inversion: coin-flick -> quieter tick -> quietest -> cloth -> one click
##
## struktured 2026-09-09 on the rogue: "I liked the rogue one already so dont change that one much."
## The rogue's whole character is that MORE commitment sounds like LESS, so anyone normalising that
## ladder — the obvious, well-meant "fix" for a cue measuring 30 dB below its siblings — destroys it
## silently. Nothing else in the repo records that intent as an enforceable property.
##
## GUT cannot do DSP, so tools/audit_whoop.py records rms_db per pinned cue and this asserts the
## SHAPE from that fixture. Same split as the whoop ratchet.
##
## ⚠️ These cues were generated for TEXTURE and MASTERED for level — ElevenLabs does not honour
## loudness intent (the first pass came back with the fifth fighter cue at -43.7 dB and the rogue
## pair moving the wrong way). Level is a mix decision, so it is pinned here rather than trusted.

const BASELINE := "res://test/fixtures/sfx_whoop_baseline.json"


func _cues() -> Dictionary:
	var raw := FileAccess.get_file_as_string(BASELINE)
	assert_ne(raw, "", "whoop baseline missing — run `tools/audit_whoop.py --write`")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "baseline did not parse")
	return (parsed as Dictionary).get("cues", {})


func _ladder(job: String) -> Array:
	var cues := _cues()
	var out: Array = []
	for n in range(1, 6):
		var k := "advance_%s_%d" % [job, n]
		if not cues.has(k):
			return []
		out.append(float((cues[k] as Dictionary).get("rms_db", 0.0)))
	return out


func test_both_ladders_are_pinned_with_levels() -> void:
	## PREMISE: without rms_db every shape assertion below reads 0.0 and passes trivially.
	for job in ["fighter", "rogue"]:
		var l := _ladder(job)
		assert_eq(l.size(), 5, "%s ladder is not fully pinned in the baseline — re-run tools/audit_whoop.py --write" % job)
		for v in l:
			assert_lt(float(v), 0.0, "%s ladder has a 0.0 rms_db — the baseline predates rms recording and this guard is inert" % job)


func test_the_fighter_ladder_ascends_at_the_new_rungs() -> void:
	var l := _ladder("fighter")
	assert_eq(l.size(), 5, "control: fighter ladder incomplete")
	if l.size() < 5:
		return
	assert_gt(l[3], l[2], "fighter press 4 (%.1f dB) must be LOUDER than press 3 (%.1f) — the steel ladder escalates" % [l[3], l[2]])
	assert_gt(l[4], l[3], "fighter press 5 (%.1f dB) must be LOUDER than press 4 (%.1f)" % [l[4], l[3]])
	assert_gt(l[4] - l[3], l[3] - l[2],
		"the 4->5 step (%.1f dB) must be the biggest — the fifth action is the new thing and has to land as one" % [l[4] - l[3]])


func test_the_rogue_ladder_still_INVERTS() -> void:
	## THE LOAD-BEARING ONE. Normalising this ladder is the well-meant change that kills the joke.
	var l := _ladder("rogue")
	assert_eq(l.size(), 5, "control: rogue ladder incomplete")
	if l.size() < 5:
		return
	assert_lt(l[3], l[2], "rogue press 4 (%.1f dB) must be QUIETER than press 3 (%.1f) — more commitment sounds like less, and struktured likes this ladder as it is" % [l[3], l[2]])
	assert_lt(l[4], l[3], "rogue press 5 (%.1f dB) must be QUIETER than press 4 (%.1f)" % [l[4], l[3]])
	assert_lt(l[4], l[0] - 6.0,
		"rogue press 5 (%.1f dB) must be well below press 1 (%.1f) — if the ladder has been flattened the inversion is gone" % [l[4], l[0]])


func test_the_two_ladders_disagree_in_direction() -> void:
	## The pair is the point: same mechanic, opposite reading, per character. If both ever run the
	## same way, one of them has been "fixed" to match the other.
	var f := _ladder("fighter")
	var r := _ladder("rogue")
	if f.size() < 5 or r.size() < 5:
		fail_test("control: both ladders must be pinned for this comparison")
		return
	assert_gt(f[4] - f[0], 0.0, "fighter must end LOUDER than it started")
	assert_lt(r[4] - r[0], 0.0, "rogue must end QUIETER than it started")
