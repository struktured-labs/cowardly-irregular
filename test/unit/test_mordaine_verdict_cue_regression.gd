extends GutTest

## The verdict beat played a paper riffle (2026-08-06).
##
## world1_mordaine_intro step 45 fires a cue, step 46 narrates "…closed the ledger on the
## table. A sound like a verdict." The cue was `paper_shuffle`, whose own authored prompt is
## "shuffled and squared on a desk, DRY BUREAUCRATIC RIFFLE." Mordaine's battle theme is
## TITLED "A Sound Like a Verdict"; two more tracks in her arc are titled from this scene's
## prose. Every lane read this scene as source text except the one that filled the sfx slot.
##
## SHIPPED, REACHABLE, AND WRONG — the class no presence-shaped instrument catches. The cue
## resolved, the manifest had it, the step was well-formed, every sweep was green. It was
## found by joining a staging note to a manifest prompt BY HAND.
##
## So this test pins a VALUE, not an existence. That is the only shape that catches the class:
## "a cue is present" was already true and always would have been.

const SCENE: String = "res://data/cutscenes/world1_mordaine_intro.json"
const VERDICT_CUE: String = "ledger_close"
const RIFFLE_CUE: String = "paper_shuffle"
const STEP_COUNT: int = 54


func _scene() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCENE))
	if parsed is Dictionary and parsed.has("steps"):
		return parsed["steps"]
	return parsed if parsed is Array else []


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	return parsed.get("sfx", {}) if parsed is Dictionary else {}


func _cue_of(step: Variant) -> String:
	if not (step is Dictionary):
		return ""
	return str(step.get("sound", step.get("sfx", "")))


func test_premise_the_scene_parses() -> void:
	var steps: Array = _scene()
	assert_eq(steps.size(), STEP_COUNT,
		"PREMISE: the scene must have %d steps — every assertion below indexes into it, and a changed count means the staging blocking's step numbers moved too" % STEP_COUNT)


func test_the_verdict_beat_is_scored_by_the_verdict_cue() -> void:
	## THE LOAD-BEARING PIN. Finds the beat by its NARRATION, not by a step number, so it
	## survives an insertion above it — the blocking is authored against these indices and
	## someone will eventually add a step.
	var steps: Array = _scene()
	var verdict_idx: int = -1
	for i in range(steps.size()):
		if steps[i] is Dictionary and str(steps[i].get("text", "")).to_lower().contains("a sound like a verdict"):
			verdict_idx = i
			break
	assert_gt(verdict_idx, 0,
		"could not find the 'a sound like a verdict' narration — if that line was rewritten, this guard needs re-anchoring, not deleting")

	var cue_idx: int = verdict_idx - 1
	assert_true(steps[cue_idx] is Dictionary, "the step before the verdict narration is malformed")
	assert_eq(_cue_of(steps[cue_idx]), VERDICT_CUE,
		"the step before 'a sound like a verdict' plays '%s'. The prose NAMES the sound it wants and the boss theme is titled after it — a riffle here is the defect this test exists for." % _cue_of(steps[cue_idx]))


func test_the_riffle_is_not_on_the_verdict_beat() -> void:
	## NEGATIVE CONTROL, stated separately so the diagnostic names the actual regression.
	##
	## ⚠️ Written first as a loop over paper_shuffle steps — which asserts NOTHING once the
	## fix lands, because there are none. It scored [Risky] and passed, i.e. a control that
	## only exists while the bug does. Anchored on the beat instead so it asserts in BOTH
	## states, which is the whole difference between a guard and an alarm.
	var steps: Array = _scene()
	var verdict_idx: int = -1
	for i in range(steps.size()):
		if steps[i] is Dictionary and str(steps[i].get("text", "")).to_lower().contains("a sound like a verdict"):
			verdict_idx = i
			break
	assert_gt(verdict_idx, 0, "could not find the verdict narration to anchor against")
	var cue: String = _cue_of(steps[verdict_idx - 1])
	assert_ne(cue, RIFFLE_CUE,
		"%s (its own prompt: 'dry bureaucratic riffle') is on the verdict beat at step %d" % [RIFFLE_CUE, verdict_idx])
	assert_false(cue.is_empty(),
		"the verdict beat has NO cue at all — silence here is a different defect, not a fix")


func test_short_narration_REQUIRES_the_verdict_cue() -> void:
	## THE COUPLING, ENCODED. The narration was cut to three words BECAUSE the sound now
	## carries the beat. Those two changes are individually sensible and jointly required:
	##
	##   cue fixed  + prose kept   safe, slightly redundant
	##   cue fixed  + prose cut    intended
	##   cue unfixed + prose kept  the prose compensates for the wrong cue
	##   cue unfixed + prose CUT   🔴 WORSE THAN EITHER — thinner AND still wrong
	##
	## A fold reviewer sees a prose trim and a cue swap as two reasonable changes and has no
	## reason to check they arrived together. Three lanes reasoned about this correctly in
	## chat and encoded it nowhere; a rule indexed on FOLD ORDER was agreed twice and would
	## have shipped the forbidden row. The dependency is not "who folds second" — it is
	## "is ledger_close in this tree", so it belongs in the tree.
	##
	## Relationship, not coordinate: it survives a rewrite that renumbers every step.
	var steps: Array = _scene()
	var idx: int = -1
	for i in range(steps.size()):
		if steps[i] is Dictionary and str(steps[i].get("text", "")).to_lower().contains("a sound like a verdict"):
			idx = i
			break
	assert_gt(idx, 0, "could not find the verdict narration")

	var text: String = str(steps[idx].get("text", "")).to_lower()
	var cue: String = _cue_of(steps[idx - 1])
	## The long form names the physical action ("closed the ledger"); the short form leaves
	## that entirely to the screen and the sound.
	var prose_compensates: bool = text.contains("closed the ledger")

	if not prose_compensates:
		assert_eq(cue, VERDICT_CUE,
			"the verdict narration is the SHORT form but its cue is '%s'. Trimming that line is only safe once the sound carries the beat — with %s here the moment is thinner AND still wrong, which is worse than not trimming at all." % [cue, cue])
	else:
		assert_false(cue.is_empty(),
			"the long-form narration is present but the beat has no cue at all")


func test_both_cues_resolve_in_the_manifest() -> void:
	## paper_shuffle is deliberately KEPT despite being unreferenced after the swap — the
	## folding beat ("She finished reading the document. Folded it.") is genuinely a
	## bureaucratic riffle and has no cue at all. Deleting it would lose the right sound
	## for a beat that still wants one.
	var m: Dictionary = _manifest()
	assert_gt(m.size(), 200, "control: manifest parsed to %d entries — implausible" % m.size())
	for key in [VERDICT_CUE, RIFFLE_CUE]:
		assert_true(m.has(key), "%s missing from the sfx manifest" % key)
		var path: String = str(m[key].get("file", "")) if m[key] is Dictionary else ""
		assert_true(FileAccess.file_exists("res://" + path),
			"%s -> '%s' does not exist on disk" % [key, path])


func test_the_verdict_cue_actually_loads() -> void:
	## A manifest entry plus a file on disk is not a playable stream — a missing .import
	## sidecar ships a cue that silently fails to load, which is how 11 status cues shipped
	## dark once already.
	var stream: Variant = load("res://assets/audio/sfx/ledger_close.ogg")
	assert_not_null(stream, "ledger_close.ogg did not load — check its .import sidecar is committed")
	assert_true(stream is AudioStreamOggVorbis, "ledger_close loaded as %s, not an ogg stream" % [stream.get_class() if stream else "null"])
	assert_gt(stream.get_length(), 0.1, "ledger_close is %.2fs long — implausibly short" % stream.get_length())
