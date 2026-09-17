extends GutTest

## `_format_events` assigned each entry to a typed `Dictionary`. A non-Dictionary there is a
## SCRIPT ERROR that ABORTS the enclosing function — so one malformed event silently cost the
## prompt its ENTIRE context block, including entries already processed and valid.
##
## MEASURED before the fix, three arrays through the real build_npc_opening:
##
##     [good, good2]           both present        the control
##     ["a string", good2]     good2 GONE          the abort ate the later valid entry
##     [good, "a string"]      good  GONE          and the EARLIER one, already appended
##
## The third row is the one that decides it: a skip would have kept `good`, so the loss is an
## abort rather than a filter. Silent — no error surfaces to the player or the log.
##
## ⚠️ LATENT, NOT LIVE, and stated as such. The only caller is DynamicConversation, which
## passes `EventLog.recent_varied()` — declared `Array[Dictionary]`, so safe by construction.
## The one producer of string-shaped events is `LLMContext._build_events`, whose own docstring
## promises `recent_events: [ last ~8 EventLog summaries ]` — and LLMContext has ZERO
## consumers in `src/` today. So this is the shape that arrives the day somebody wires the
## context builder these prompts were written for.

const DP := preload("res://src/llm/DialoguePrompts.gd")


func _events(entries: Array) -> String:
	return DP.build_npc_opening("Theron", "an elder", "Harmonia", entries)


func _good() -> Dictionary:
	return {"type": "battle", "summary": "The Rat King fell"}


func _good2() -> Dictionary:
	return {"type": "quest", "summary": "Milo asked for data"}


# ── the control: both survive when nothing is malformed ───────────────────────

func test_a_clean_event_array_renders_every_entry() -> void:
	## CONTROL. Without this, every arm below passes on a builder that renders nothing.
	var p: String = _events([_good(), _good2()])
	assert_true(p.find("The Rat King fell") != -1, "the first event must render")
	assert_true(p.find("Milo asked for data") != -1, "and the second")


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_bad_entry_does_not_take_the_ones_after_it() -> void:
	var p: String = _events(["a bare string", _good2()])
	assert_true(p.find("Milo asked for data") != -1,
		"a later valid event must survive a malformed one before it")


func test_a_bad_entry_does_not_take_the_ones_before_it() -> void:
	## THE ARM THAT NAMES THE MECHANISM. A filter would already keep this one; only an ABORT
	## loses an entry that was appended before the bad one was reached.
	var p: String = _events([_good(), "a bare string"])
	assert_true(p.find("The Rat King fell") != -1,
		"an earlier valid event must survive a malformed one after it")


func test_an_array_of_only_bad_entries_renders_no_events_and_does_not_crash() -> void:
	var p: String = _events(["one", "two", 42, null])
	assert_true(p.find("The Rat King fell") == -1, "there is nothing valid to render")
	assert_gt(p.length(), 200, "and the rest of the prompt must still be built")


func test_every_shape_that_is_not_a_dictionary_is_skipped() -> void:
	## The producer this defends against emits Strings; the others are cheap to cover and
	## a typed-array assignment aborts identically for all of them.
	for bad in ["str", 42, 3.5, null, [], true]:
		var p: String = _events([_good(), bad, _good2()])
		assert_true(p.find("The Rat King fell") != -1 and p.find("Milo asked for data") != -1,
			"both valid events must survive a %s" % type_string(typeof(bad)))
