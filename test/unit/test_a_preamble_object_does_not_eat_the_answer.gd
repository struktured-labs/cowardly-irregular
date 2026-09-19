extends GutTest

## A model reply is not guaranteed to be one object with nothing around it.
##
## _extract_json_from_raw's step 3 used to take ONE slice — first '{' to last '}' —
## which is correct only when the reply holds exactly one brace-shaped thing. Two
## shapes defeat it, and both end with the player's composition silently unparsed:
##
##     "Here is {your} result: {…}"    a prose brace ahead of the object
##     "{\"thinking\":true} {…}"       a preamble object ahead of the answer
##
## In each case the single slice spans BOTH and parses as neither. Measured before
## the fix: 13 of 20 malformed shapes recovered; after: 15, with nothing lost.
##
## ⚠️ THE ORDER IS THE LOAD-BEARING PART, not the scan. Candidates are tried LAST
## first, because a preamble precedes the answer. Taking the first that parses
## returns `{"thinking":true}` — a Dictionary, so every is-it-a-dict assertion
## passes — and the player gets the model's throat-clearing instead of their rules.
## That is why the arms below assert on CONTENT and not on type.

const ANSWER := '{"rules":[1]}'


func test_a_preamble_object_does_not_win() -> void:
	var got: Variant = LLMService._extract_json_from_raw('{"thinking":true} ' + ANSWER)
	assert_true(got is Dictionary, "nothing parsed out of a preamble+answer reply: %s" % [got])
	assert_true((got as Dictionary).has("rules"),
		("the preamble was returned instead of the answer: %s. Candidates must be tried "
		+ "LAST first — a model's real reply is the last complete object it emits.") % [got])


func test_a_prose_brace_does_not_defeat_the_scan() -> void:
	var got: Variant = LLMService._extract_json_from_raw('Here is {your} result: ' + ANSWER)
	assert_true(got is Dictionary and (got as Dictionary).has("rules"),
		("a brace in the prose ahead of the object lost the whole reply: %s. first-'{'-to-"
		+ "last-'}' spans the prose brace and parses as neither.") % [got])


func test_a_brace_inside_a_string_is_not_a_nesting_event() -> void:
	## The scan walks braces, so it must know a quoted one is data. A '}' inside a
	## string value would otherwise close the object early and truncate the answer.
	##
	## ⚠️ THE PROSE PREFIX IS LOAD-BEARING, NOT DECORATION. Written without it this arm
	## fed VALID JSON, so step 1 parsed it directly and the span scan never ran — the
	## arm was green with string-awareness deleted from the walk, i.e. it asserted
	## nothing about its own subject. Caught by the mutation, not by reading it.
	var got: Variant = LLMService._extract_json_from_raw(
		'Here is: {"note":"a } brace","rules":[1]}')
	assert_true(got is Dictionary, "a quoted brace broke the walk: %s" % [got])
	assert_true((got as Dictionary).has("rules"),
		"the object was cut at a brace inside a string value: %s" % [got])


func test_the_reply_that_is_only_an_object_still_parses() -> void:
	## The ordinary case, pinned so a scan change cannot trade it for the exotic ones.
	var got: Variant = LLMService._extract_json_from_raw(ANSWER)
	assert_true(got is Dictionary and (got as Dictionary).has("rules"),
		"the plain single-object reply stopped parsing: %s" % [got])


# ── controls: the arms above are zeros about a scan that must be shown to work ──

func test_the_span_scan_finds_more_than_one_object() -> void:
	## FLOOR. Every arm above rests on the scan enumerating candidates; a scan that
	## returns one span (or none) makes them assertions about the old behaviour while
	## reading as though they covered the new.
	var spans: Array = LLMService._balanced_object_spans('{"a":1} junk {"b":2}')
	assert_eq(spans.size(), 2,
		"the span scan found %d complete objects in a two-object reply — it is not "
		% spans.size() + "enumerating candidates, so the arms above cannot be about ordering")


func test_the_span_scan_ignores_an_unclosed_object() -> void:
	## A truncated reply has no COMPLETE span, and must be left to the truncation
	## repair rather than reported as a candidate. Pinned because a scan that invented
	## a span here would shadow step 4 and return a short object as if it were whole.
	var spans: Array = LLMService._balanced_object_spans('{"rules":[{"op":">="')
	assert_eq(spans, [], "an unclosed object was reported as complete: %s" % [spans])


func test_the_truncation_repair_still_runs_behind_the_scan() -> void:
	## The scan sits in front of step 4; if it swallowed the unclosed case, truncated
	## replies would stop being repaired and nothing else in this file would notice.
	var got: Variant = LLMService._extract_json_from_raw('{"rules":[{"op":">="}]')
	assert_true(got is Dictionary and (got as Dictionary).has("rules"),
		"a truncated reply stopped being repaired: %s" % [got])
