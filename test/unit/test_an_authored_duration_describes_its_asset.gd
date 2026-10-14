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
## ⛔ WHY `TOLERANCE_SECONDS` IS NOT TIGHTENED, measured 2026-10-13 rather than assumed. @cowir-music
## found that an ABSOLUTE 2.0s window over cues spanning 0.02s to 10s cannot fire at the short end at
## all — a 0.035s file cannot differ from any sub-2s declaration by more than 2s, so the arm is a
## TAUTOLOGY over the whole short population, not merely loose there. Reproduced: of 334 declared
## durations, exactly ONE exceeds 2.0s and it is the allowlisted entry below.
##
## ⚠️ AND THE OBVIOUS REPAIR IS WRONG. Tightening the window flags mostly SOURCE-LOCKED entries —
## at 0.5s, 6 of 10; at 0.06s, 18 of 31 — whose `duration_seconds` the generator never reads, because
## it refuses them before it gets there. Their drift is documentation debt with NO consumer, so a
## tighter bound buys a long explained-away list, which is the rot CLAUDE.md names. Nor is a RATIO
## bound derivable from the distribution: the ratios run continuously 1.415, 1.444, 1.471, 1.500,
## 1.562 with no corridor, so any `k` there is a coincidental value.
## The hazard lives in the REGENERABLE population alone, and that is what the arm below scopes to.
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


## ⛔ A REGENERABLE CUE WHOSE ASSET CANNOT BE THE OUTPUT OF ITS OWN REQUEST (2026-10-13)
##
## `elevenlabs_sfx.py` refuses a cue whose `source` names a non-ElevenLabs method — but its predicate
## is `if src and not src.startswith("elevenlabs")`, so an ABSENT source is falsy and PROCEEDS. 833 of
## 988 entries are regenerable that way, which is mostly correct (the label convention arrived after
## the early bank). It also means a tool-rebuilt asset whose label was never set is one `--force` from
## being replaced by a render of its prompt.
##
## ⚠️ MEASURE WITH THE CONSUMER'S OWN ACCESSOR. This arm reads `AudioStream.get_length()`, and that
## is not a formality: across 25 cues checked three ways, Godot and `ffprobe -show_entries
## format=duration` agree on 24, while a hand-rolled f32le decode disagreed by up to 1.5x on sub-90ms
## files. The one file where Godot and ffprobe part is `screen_shake` — ffprobe's header read says
## 0.0246s where Godot and ffmpeg's DECODER both say ~1.004s against a declared 1.00. So its
## declaration is correct, nothing in the project reads that header, and it is NOT a defect; it was
## briefly in the ledger below purely because I had measured it with ffprobe rather than the engine.
##
## 🔑 THE DETECTOR IS INDEPENDENT EVIDENCE, which is what makes it work where the prose-based guard
## cannot: `test_a_synthesised_cue_carries_its_source_label` judges cues whose PROMPT announces
## synthesis, so an asset rebuilt by a tool whose prompt was never updated is outside its corpus by
## construction. A 0.5s request did not produce a 0.035s file. The CONTENT contradicting the REQUEST
## is evidence of provenance that no self-declaration is needed for.
##
## 📌 WORKED INSTANCE, and why this is not hypothetical: all 18 footstep cues declared 0.5s against
## 0.032-0.086s assets, carried NO source, and their prompts still read "hard sole on cobblestone" /
## "industrial steel floor clang". Commit 3767131e3 says in its own message that struktured rejected
## the ElevenLabs footsteps TWICE — "kind of awful", "harsh crunching" — and all 18 were rebuilt with
## sox. A --force run would have restored precisely what he turned down. Fixed in this commit: labelled
## `sox_synth` (so the generator refuses them) and re-declared to their shipped lengths.
##
## ⛔ `_trim_seconds` IS THE DECLARED EXPLANATION, AND HONOURING IT IS THE FIRST THING THAT READS IT.
## Four entries were in this ledger with the note "the generator of the shipped file is not recorded
## in the commit". It WAS recorded — in the entry itself, in a field I had not read:
##     exp_bar_tick_ramp_hi/lo/mid   declared 0.500   _trim_seconds 0.120   actual 0.120
##     loot_pop                      declared 0.500   _trim_seconds 0.250   actual 0.250
## The declared value is the ElevenLabs REQUEST and the trim is deliberate, so the discrepancy was
## declared in the data all along. `_trim_seconds` had ZERO readers (src 0, tools 0, test 0); the arm
## below is its first consumer, which is the right shape — a field whose job is to document a
## discrepancy should be what silences the discrepancy check.
##
## ✅ AND IT CANNOT BE USED AS A SUPPRESSION FLAG, which is the only reason an exemption belongs here
## at all. The exemption requires `_trim_seconds` to MATCH THE SHIPPED ASSET, so you cannot silence a
## real mismatch by adding the field — you can only state the truth, and stating the truth is the
## fix. A wrong trim value reds in `test_a_declared_trim_describes_its_asset` below rather than
## quietly widening the exemption. "You can't silence it green, only explain it green."
##
## ⚠️ THE RESIDUAL HOLE, NAMED RATHER THAN PRETENDED AWAY: a matching `_trim_seconds` proves the
## NUMBER is true, not that a TRIM is what produced it. `menu_move` is 0.50 declared against a 0.320
## asset because 554fbfaa3 pitched it up 50% (0.50 / 1.5 = 0.333), so a `_trim_seconds: 0.32` there
## would be an accurate number attached to the wrong mechanism, and this arm would exempt it. No
## check over this data can tell a trim from a pitch raise — the asset is short either way. What the
## exemption does buy is that the discrepancy must be DECLARED and the declaration must be
## arithmetically true, which is strictly more than the silence it replaces.
##
## ⚠️ THE 1.5x FIGURE IS A REVIEW TRIGGER, NOT A BOUND — the assertion is the SET, exactly as the
## door_open ledger works. No threshold is derivable here (see the note by TOLERANCE_SECONDS), so a
## number that merely decides what gets LOOKED AT is honest where a number deciding pass/fail is not.
## A new name appearing reds; a resolved name must leave in the same commit.
const REGEN_MISMATCH := {
	"menu_move": "a DERIVED asset: 554fbfaa3 is a user-directed iteration — 'low bubbly wobble with dampened highs and 50% pitch raise'. 0.50 / 1.5 = 0.333 against the shipped 0.320, so the pitch raise accounts for the length exactly. A regen would restore the un-pitched version he asked to change; it wants an ffmpeg_derive-class label, not a new number",
	"advance_rogue_2": "source IS elevenlabs_foley, so deliberately regenerable — but b05d114b5 records the shipped asset as 'range compressed + floor raised after struktured flagged the set read quieter than fighter/cleric', i.e. post-processed AFTER generation. A regen loses a change his feedback caused. Whether the label should still say elevenlabs is his call, not this guard's",
}


func _regenerable(entry: Dictionary) -> bool:
	## The generator's predicate, verbatim from elevenlabs_sfx.py: an empty source is falsy and
	## PROCEEDS, which is the whole reason this arm exists.
	var src: String = str(entry.get("source", ""))
	return not (src != "" and not src.begins_with("elevenlabs"))


func test_a_regenerable_cue_is_plausibly_the_output_of_its_request() -> void:
	var sfx: Dictionary = _sfx()
	assert_gt(sfx.size(), 0, "VOID, not clean: the sfx manifest read back 0 entries")
	var considered := 0
	var flagged: Array[String] = []
	var locked := 0
	var untimed := 0
	var undecodable := 0
	var trim_declared := 0
	for k in sfx.keys():
		var e: Dictionary = sfx[k] if sfx[k] is Dictionary else {}
		if not _regenerable(e):
			locked += 1
			continue
		if not e.has("duration_seconds"):
			untimed += 1
			continue
		var actual: float = _length_of(str(e.get("file", "")))
		if actual <= 0.0:
			undecodable += 1
			continue
		considered += 1
		var declared: float = float(e["duration_seconds"])
		if declared <= 0.0:
			continue
		## a declared trim that matches the shipped asset IS the explanation — the declared value is
		## the request, the trim is what was kept, and both are recorded
		if e.has("_trim_seconds") and absf(float(e["_trim_seconds"]) - actual) <= 0.03:
			trim_declared += 1
			continue
		var ratio: float = maxf(declared / actual, actual / declared)
		if ratio >= 1.5:
			flagged.append(str(k))
	## Buckets must sum, the same discipline as the arm above: a silent skip is a finding.
	assert_eq(locked + untimed + undecodable + considered, sfx.size(),
		"the buckets do not sum (%d locked + %d untimed + %d undecodable + %d considered != %d entries), so some entry fell into an unnamed void" % [locked, untimed, undecodable, considered, sfx.size()])
	assert_gt(considered, 100,
		"only %d regenerable cues carried a declared duration AND a loadable asset — the corpus is too small for the set comparison below to mean anything" % considered)
	## FLOOR on the exemption: if nothing is exempted the arm above is judging a corpus that no longer
	## contains the four entries this mechanism was built for, so the exemption is untested.
	assert_gt(trim_declared, 0,
		"no entry was exempted by a matching _trim_seconds, so that branch ran on nothing and the four cues it was written for have changed shape")
	flagged.sort()
	var expected: Array[String] = []
	for k in REGEN_MISMATCH.keys():
		expected.append(str(k))
	expected.sort()
	assert_eq(flagged, expected,
		"the set of regenerable cues whose asset contradicts its own request has CHANGED.\n  now:      %s\n  declared: %s\nA NEW name means a tool-rebuilt asset is one --force from being replaced by a render of its prompt: give it a source label the generator refuses, or correct its declaration. A name that LEFT must come out of REGEN_MISMATCH in the same commit." % [flagged, expected])


func test_every_declared_regen_mismatch_still_mismatches() -> void:
	## No stale allowlist, mirroring test_a_declared_drift_still_drifts: an entry that has been fixed
	## must leave the ledger, or the ledger starts vouching for cues nobody has looked at.
	var sfx: Dictionary = _sfx()
	var resolved: Array[String] = []
	for k in REGEN_MISMATCH.keys():
		var key := str(k)
		assert_true(sfx.has(key), "REGEN_MISMATCH names %s, which is not in the manifest" % key)
		if not sfx.has(key):
			continue
		var e: Dictionary = sfx[key]
		assert_true(_regenerable(e),
			"%s is in REGEN_MISMATCH but now carries a source the generator refuses (%s) — it is protected, so take it out of the ledger" % [key, e.get("source", "")])
		assert_gt(str(REGEN_MISMATCH[k]).length(), 60,
			"%s needs an explanation naming its CAUSE and what it needs, not a placeholder" % key)
		var actual: float = _length_of(str(e.get("file", "")))
		var declared: float = float(e.get("duration_seconds", 0.0))
		if actual <= 0.0 or declared <= 0.0:
			continue
		if maxf(declared / actual, actual / declared) < 1.5:
			resolved.append(key)
	assert_eq(resolved, [],
		"these cues no longer contradict their request and must leave REGEN_MISMATCH: %s" % [resolved])


func test_the_rejected_footsteps_cannot_be_regenerated() -> void:
	## The regression arm for this commit. struktured turned the ElevenLabs footsteps down TWICE;
	## the sox rebuilds carried no label, so the generator would have replaced them from prompts that
	## still described the rejected sound. If this reds, those 18 assets are exposed again.
	var sfx: Dictionary = _sfx()
	var unprotected: Array[String] = []
	var mis_declared: Array[String] = []
	var seen := 0
	for k in sfx.keys():
		var key := str(k)
		if not key.begins_with("footstep_"):
			continue
		seen += 1
		var e: Dictionary = sfx[key]
		if _regenerable(e):
			unprotected.append(key)
		var actual: float = _length_of(str(e.get("file", "")))
		var declared: float = float(e.get("duration_seconds", 0.0))
		if actual > 0.0 and declared > 0.0 and maxf(declared / actual, actual / declared) >= 1.5:
			mis_declared.append("%s declares %.3f for a %.3fs asset" % [key, declared, actual])
	assert_eq(seen, 18, "expected 18 footstep cues (6 terrains x 3 variants), found %d" % seen)
	assert_eq(unprotected, [],
		"these footstep cues are regenerable again — a --force run restores the ElevenLabs footsteps struktured called \"kind of awful\" and \"harsh crunching\": %s" % [unprotected])
	assert_eq(mis_declared, [],
		"these footstep declarations no longer describe their assets: %s" % [mis_declared])


func test_a_declared_trim_describes_its_asset() -> void:
	## ⛔ WHAT STOPS THE EXEMPTION ABOVE BEING A SUPPRESSION FLAG. `_trim_seconds` forgives a
	## declared/actual mismatch, so a WRONG trim value would forgive it falsely and quietly. Every
	## entry carrying the field must have it match the shipped asset — then adding the field can only
	## ever state the truth, and the exemption is earned per entry rather than granted.
	var sfx: Dictionary = _sfx()
	var wrong: Array[String] = []
	var seen := 0
	for k in sfx.keys():
		var e: Dictionary = sfx[k] if sfx[k] is Dictionary else {}
		if not e.has("_trim_seconds"):
			continue
		var actual: float = _length_of(str(e.get("file", "")))
		if actual <= 0.0:
			continue
		seen += 1
		var trim: float = float(e["_trim_seconds"])
		if absf(trim - actual) > 0.03:
			wrong.append("%s declares a %.3fs trim for a %.3fs asset" % [str(k), trim, actual])
	assert_gt(seen, 0,
		"no entry carries a _trim_seconds with a loadable asset, so this arm judges nothing — and the exemption in the arm above would then be unguarded")
	assert_eq(wrong, [],
		"a declared trim does not match its asset. This field EXEMPTS an entry from the request-vs-asset check, so a wrong value here silences a real mismatch: %s" % [wrong])
