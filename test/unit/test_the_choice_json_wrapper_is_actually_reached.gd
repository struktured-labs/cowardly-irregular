extends GutTest

## The `{"choice": X}` stage of _guard_choice had two arms named for it and neither
## notices its ABSENCE.
##
## _guard_choice is a four-stage chain:
##   1. exact match   2. case-insensitive exact   3. unique whole-token   4. {"choice":X}
##
## ⛔ MEASURED: deleting stage 4 ENTIRELY left test_llm_infra at EC=0, 112 passing —
## including test_llm_service_guard_choice_json_wrapper_extraction and
## ..._json_wrapper_invalid_value, the two arms whose names are that stage.
##
## ⚠️ PRECISELY: blind to DELETION, not to every break. Mutating stage 4 to extract
## without validating against the options DOES red ..._json_wrapper_invalid_value.
## So the pair covers a stage-4 that misbehaves and is silent about one that is not
## there at all — which is the mutation a refactor actually performs.
##
## Both are blind for their own reason, which is why neither author noticed:
##   '{"choice": "beta"}'  with opts [alpha, beta, gamma]
##       stage 3 matches `beta` as a WHOLE TOKEN — the quotes around it are
##       non-alphanumeric, so they read as word boundaries. Stage 4 never runs.
##   '{"choice": "delta"}' with the same opts
##       no option appears, so stage 3 finds nothing and the arm asserts the
##       FALLBACK — which is also what you get with stage 4 deleted.
##
## 🔑 Stage 4 is load-bearing in exactly the case neither arm constructs: a wrapper
## that names MORE THAN ONE option, so stage 3 is ambiguous and abstains. A model
## emitting {"choice":"aggressive","rejected":"defensive"} is the live shape.
##
## This is the general trap: to test stage N the input must be one that stages
## 1..N-1 REFUSE, and a naturally-chosen fixture is the clean one an early stage is
## built to absorb.

const OPTS: Array[String] = ["aggressive", "defensive", "trickster"]


func _svc() -> Object:
	return LLMService


func test_an_ambiguous_wrapper_resolves_to_the_choice_key() -> void:
	## THE ARM THE OLD PAIR WAS MISSING. Two option names are present, so stage 3
	## finds two whole-token matches and abstains; only stage 4 can pick the right
	## one, by reading the `choice` KEY rather than counting words.
	var raw: String = '{"choice": "aggressive", "rejected": "defensive"}'
	var got: String = _svc()._guard_choice(raw, OPTS, "trickster")
	assert_eq(got, "aggressive",
		("an ambiguous {\"choice\":X} wrapper must resolve to the choice key, got '%s'. "
		+ "Stage 3 sees two options and abstains — if this returns the fallback, the "
		+ "JSON stage is not being reached.") % got)


func test_an_ambiguous_wrapper_with_a_bad_choice_falls_back() -> void:
	## The same shape with a `choice` the caller never offered. Stage 4 must be reached
	## AND must reject — a stage that extracted without validating would return "sideways".
	var raw: String = '{"choice": "sideways", "rejected": "defensive", "also": "aggressive"}'
	var got: String = _svc()._guard_choice(raw, OPTS, "trickster")
	assert_eq(got, "trickster",
		("a wrapper naming an option the caller never offered must fall back, got '%s' — "
		+ "the JSON stage extracted a value and did not validate it against the options") % got)


func test_the_wrapper_choice_is_honoured_over_the_prose_around_it() -> void:
	## Direction matters: the `choice` key must WIN, not merely break the tie. A stage 4
	## that returned the first option it saw in the text would pass the arm above by
	## coincidence whenever `choice` happened to come first, so this one puts it second.
	var raw: String = '{"rejected": "defensive", "choice": "trickster"}'
	var got: String = _svc()._guard_choice(raw, OPTS, "aggressive")
	assert_eq(got, "trickster",
		("the choice key must be honoured wherever it sits in the object, got '%s' — "
		+ "a stage reading position rather than the key passes only by luck") % got)


func test_a_wrapper_with_a_case_shifted_choice_still_resolves() -> void:
	## Stage 4 carries its own case-insensitive pass. Ambiguous prose, so stage 3
	## cannot answer, and the value is cased differently from the option.
	var raw: String = '{"choice": "TRICKSTER", "rejected": "defensive", "x": "aggressive"}'
	var got: String = _svc()._guard_choice(raw, OPTS, "aggressive")
	assert_eq(got, "trickster",
		"the JSON stage's case-insensitive pass did not resolve '%s'" % got)


# ── controls: why the old arms were blind, pinned so the explanation cannot rot ──

func test_the_simple_wrapper_is_answered_by_the_token_stage() -> void:
	## THE EXPLANATION, as an assertion. The old arm's fixture resolves correctly —
	## it always did — but by stage 3, which is why deleting stage 4 left it green.
	## If this ever stops being a unique token match, the old arms change meaning and
	## somebody should re-read them rather than trust their names.
	var lower: String = '{"choice": "beta"}'
	var hits: int = 0
	for opt in ["alpha", "beta", "gamma"]:
		if lower.contains(opt):
			hits += 1
	assert_eq(hits, 1,
		"'{\"choice\": \"beta\"}' no longer contains exactly one option name — the "
		+ "reason the original wrapper arms could not fail has changed")


func test_the_plain_paths_still_work() -> void:
	## FLOOR. Every arm above is about stage 4; if the earlier stages broke, this file
	## would still be green while _guard_choice was useless for ordinary replies.
	assert_eq(_svc()._guard_choice("aggressive", OPTS, "trickster"), "aggressive",
		"stage 1 (exact) stopped working")
	assert_eq(_svc()._guard_choice("AGGRESSIVE", OPTS, "trickster"), "aggressive",
		"stage 2 (case-insensitive) stopped working")
	assert_eq(_svc()._guard_choice("play it defensive for now", OPTS, "trickster"), "defensive",
		"stage 3 (unique whole token) stopped working")
	assert_eq(_svc()._guard_choice("", OPTS, "trickster"), "trickster",
		"an empty reply no longer falls back")
