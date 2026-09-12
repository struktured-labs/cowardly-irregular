extends GutTest

## A staged brief is the only instruction the generator gets, and ours asked for
## a SONG.
##
## Five shipped beds died to silence at their loop point (f1849ca3) and had to be
## repaired after the fact by tools/trim_loop_seams.py + trim_wrap_padding.py —
## a tail fade, a ritardando, a final sustained chord, all perfectly good music
## and all wrong for a bed that restarts. The trim tools exist because the briefs
## did not say so. Every track staged behind the Suno block would have arrived
## with the same defect and needed the same hand pass.
##
## 🔑 SCOPED TO THE STAGED SET, NOT THE CORPUS. The 135 prompts whose bed already
## exists are history: their audio shipped, was measured, and in five cases was
## trimmed. Requiring the sentence there would red 135 entries to describe work
## already done, so the guard quantifies over what a FUTURE generation reads.
##
## The staged set is DERIVED — a shared_tracks key the manifest does not name has
## no bed and no render. That is 14 today, which independently reproduces the
## count cowir-main corrected to 14 in abc84372 (the 15th, interior_shop, has a
## manifest entry pointing at shop.ogg, generated 2026-04-18). A hand-list would
## go stale the moment a track renders; this set empties itself.
##
## ⚠️ THE MONO CLAUSE IS NOT COSMETIC. The published web build is the staged
## export, which swaps in a 48 kbps MONO tier for every bed — so stereo width and
## air above 10 kHz are spent on nothing a web player hears. That is a mixing
## instruction the generator can act on, which is why it rides with the loop one.

const MANIFEST := "res://data/music_manifest.json"
const PROMPTS := "res://tools/music_prompts.json"

## Substrings, not the full sentence: the brief may be reworded, and pinning the
## prose would make every edit a test failure. These two are the instruction.
const LOOP_CLAUSE := "Built to LOOP"
const MONO_CLAUSE := "mono playback chain"

## A one-shot must NOT be told to arrive back at full intensity and stop — that
## is the opposite of a stinger. Nothing staged is a one-shot today; this is here
## so the first staged stinger does not read as a defect. The mono clause still
## applies to them, because the playback chain does not care about the shape.
const ONE_SHOT_PREFIXES: Array[String] = ["stinger_", "victory", "game_over"]


func _json(path: String) -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(path)
	assert_gt(raw.length(), 1000, "SCOPE control: %s read back %d chars" % [path, raw.length()])
	return JSON.parse_string(raw) as Dictionary


func _staged() -> Dictionary:
	var named: Dictionary = _json(MANIFEST).get("tracks", {})
	var shared: Dictionary = _json(PROMPTS).get("shared_tracks", {})
	assert_gt(shared.size(), 100, "SCOPE control: shared_tracks holds %d briefs" % shared.size())
	assert_gt(named.size(), 100, "SCOPE control: manifest names %d tracks" % named.size())
	var out: Dictionary = {}
	for key in shared.keys():
		if not named.has(str(key)):
			out[str(key)] = shared[key]
	return out


func test_control_the_staged_set_is_neither_empty_nor_everything() -> void:
	## Both degenerate answers pass every arm below while measuring nothing: an
	## empty set quantifies over no briefs, and a set equal to the corpus means
	## the manifest read failed and every shipped track looks unrendered.
	var staged: Dictionary = _staged()
	var shared: Dictionary = _json(PROMPTS).get("shared_tracks", {})
	assert_gt(staged.size(), 0,
		"CONTROL FAILED: zero staged briefs derived — either the queue is empty (say so here) or the manifest read broke, and the arms below would pass either way")
	assert_lt(staged.size(), shared.size() / 2,
		"CONTROL FAILED: %d of %d shared briefs look unrendered. A staged set that large means the manifest lookup is failing, not that the queue grew" % [staged.size(), shared.size()])


func test_every_staged_brief_asks_for_a_loop_and_a_mono_mix() -> void:
	var staged: Dictionary = _staged()
	var missing: Array[String] = []
	var checked: int = 0
	for key in staged.keys():
		var id: String = str(key)
		var prompt: String = str((staged[id] as Dictionary).get("prompt", ""))
		if prompt.length() < 100:
			missing.append("%s: prompt is %d chars — empty or absent" % [id, prompt.length()])
			continue
		checked += 1
		var one_shot: bool = false
		for pre in ONE_SHOT_PREFIXES:
			if id.begins_with(pre):
				one_shot = true
		if not one_shot and not prompt.contains(LOOP_CLAUSE):
			missing.append("%s: no loop instruction" % id)
		if not prompt.contains(MONO_CLAUSE):
			missing.append("%s: no mono-chain instruction" % id)
	assert_gt(checked, 5, "SCOPE control: read only %d staged prompts" % checked)
	assert_eq(missing.size(), 0,
		"%d staged brief(s) would generate a song rather than a bed: %s — append the loop/mono paragraph in tools/music_prompts.json. A bed generated without it needs a hand pass through trim_loop_seams.py, which is what this guard exists to avoid" % [missing.size(), missing])


func test_the_shipped_corpus_is_deliberately_exempt() -> void:
	## Without this, a reader who sees the arm above green concludes the clause is
	## a corpus-wide invariant and "fixes" the other 135. It is not: those beds
	## exist, and their briefs describe what was already made.
	var named: Dictionary = _json(MANIFEST).get("tracks", {})
	var shared: Dictionary = _json(PROMPTS).get("shared_tracks", {})
	var rendered_without_clause: int = 0
	for key in shared.keys():
		if not named.has(str(key)):
			continue
		if not str((shared[key] as Dictionary).get("prompt", "")).contains(LOOP_CLAUSE):
			rendered_without_clause += 1
	assert_gt(rendered_without_clause, 50,
		"the rendered corpus now carries the loop clause almost everywhere (%d without it). If that was deliberate, widen this guard to the whole file and delete this arm — but do not leave it asserting an exemption nobody uses" % rendered_without_clause)
