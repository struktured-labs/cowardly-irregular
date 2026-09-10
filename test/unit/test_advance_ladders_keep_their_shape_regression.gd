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
	## Rungs 3..5 — the escalation the 2026-09-09 work is about. Rungs 1-2 are not required here
	## because advance_mage_2 is deliberately unpinned (a documented detector artifact, see
	## tools/audit_whoop.py), and asserting a level for it would be asserting a number nothing
	## measures rather than a property anyone chose.
	var cues := _cues()
	var out: Array = []
	for n in range(3, 6):
		var k := "advance_%s_%d" % [job, n]
		if not cues.has(k):
			return []
		out.append(float((cues[k] as Dictionary).get("rms_db", 0.0)))
	return out


func _rung(job: String, n: int) -> float:
	var cues := _cues()
	var k := "advance_%s_%d" % [job, n]
	return float((cues.get(k, {}) as Dictionary).get("rms_db", 0.0)) if cues.has(k) else 0.0


func test_both_ladders_are_pinned_with_levels() -> void:
	## PREMISE: without rms_db every shape assertion below reads 0.0 and passes trivially.
	for job in ["fighter", "rogue", "cleric", "mage", "bard"]:
		var l := _ladder(job)
		assert_eq(l.size(), 3, "%s rungs 3-5 are not pinned in the baseline — re-run tools/audit_whoop.py --write" % job)
		for v in l:
			assert_lt(float(v), 0.0, "%s ladder has a 0.0 rms_db — the baseline predates rms recording and this guard is inert" % job)


func test_the_fighter_ladder_ascends_at_the_new_rungs() -> void:
	## All FOUR ascending ladders, not just the fighter — cleric/mage/bard gained rungs 4-5 on
	## 2026-09-10 and the same shape has to hold for each.
	for job in ["fighter", "cleric", "mage", "bard"]:
		var l := _ladder(job)
		assert_eq(l.size(), 3, "control: %s rungs 3-5 incomplete" % job)
		if l.size() < 3:
			continue
		assert_gt(l[1], l[0], "%s press 4 (%.1f dB) must be LOUDER than press 3 (%.1f)" % [job, l[1], l[0]])
		assert_gt(l[2], l[1], "%s press 5 (%.1f dB) must be LOUDER than press 4 (%.1f)" % [job, l[2], l[1]])
		assert_gt(l[2] - l[1], l[1] - l[0],
			"%s: the 4->5 step (%.1f dB) must be the biggest — the fifth action is the new thing and has to land as one" % [job, l[2] - l[1]])


func test_the_rogue_ladder_still_INVERTS() -> void:
	## THE LOAD-BEARING ONE. Normalising this ladder is the well-meant change that kills the joke.
	var l := _ladder("rogue")
	assert_eq(l.size(), 3, "control: rogue rungs 3-5 incomplete")
	if l.size() < 3:
		return
	assert_lt(l[1], l[0], "rogue press 4 (%.1f dB) must be QUIETER than press 3 (%.1f) — more commitment sounds like less, and struktured likes this ladder as it is" % [l[1], l[0]])
	assert_lt(l[2], l[1], "rogue press 5 (%.1f dB) must be QUIETER than press 4 (%.1f)" % [l[2], l[1]])
	assert_lt(l[2], _rung("rogue", 1) - 6.0,
		"rogue press 5 (%.1f dB) must be well below press 1 (%.1f) — if the ladder has been flattened the inversion is gone" % [l[2], _rung("rogue", 1)])


func test_no_ladder_step_is_absurd_in_EITHER_direction() -> void:
	## ⛔ THE FAR SIDE. Every other assertion here is one-sided — "louder than", "quieter than" —
	## which is correct for a DIRECTIONAL claim and blind to magnitude. cowir-autogrind's split
	## (2026-09-10) is the reason this exists: only PRECONDITIONS may be one-sided; for a SUBJECT the
	## opposite excursion is usually a bug too. A press 5 thirty dB above press 4 is deafening and a
	## rogue press 5 forty dB down is inaudible, and both would sail through every assert above.
	##
	## Bounds are generous by design — this catches a mastering target typo'd by an order of
	## magnitude, not a taste difference. The ladders currently step 0.3-4.5 dB.
	var worst := 0.0
	var offenders: Array = []
	var checked := 0
	for job in ["fighter", "rogue", "cleric", "mage", "bard"]:
		var l := _ladder(job)
		if l.size() < 3:
			continue
		for i in range(1, l.size()):
			var step: float = absf(l[i] - l[i - 1])
			checked += 1
			worst = maxf(worst, step)
			if step > 12.0:
				offenders.append("%s rung %d->%d: %.1f dB" % [job, i + 2, i + 3, step])
			if step < 0.2:
				offenders.append("%s rung %d->%d: %.1f dB — flat, the escalation is not audible" % [job, i + 2, i + 3, step])
	assert_gte(checked, 10, "control: only %d steps measured across five ladders — expected at least 10" % checked)
	assert_lt(worst, 12.0, "largest step is %.1f dB" % worst)
	assert_eq(offenders.size(), 0, "ladder step(s) outside the audible-but-sane band: %s" % [offenders])
	## And the total span, so a ladder cannot creep out of range one small step at a time.
	for job in ["fighter", "rogue", "cleric", "mage", "bard"]:
		var l := _ladder(job)
		if l.size() < 3:
			continue
		assert_lt(absf(l[l.size() - 1] - l[0]), 20.0,
			"%s spans %.1f dB across rungs 3-5 — that is a mix error, not an escalation" % [job, absf(l[l.size() - 1] - l[0])])


func test_the_two_ladders_disagree_in_direction() -> void:
	## The pair is the point: same mechanic, opposite reading, per character. If both ever run the
	## same way, one of them has been "fixed" to match the other.
	var f := _ladder("fighter")
	var r := _ladder("rogue")
	if f.size() < 3 or r.size() < 3:
		fail_test("control: both ladders must be pinned for this comparison")
		return
	assert_gt(f[2] - _rung("fighter", 1), 0.0, "fighter must end LOUDER than it started")
	assert_lt(r[2] - _rung("rogue", 1), 0.0, "rogue must end QUIETER than it started")
