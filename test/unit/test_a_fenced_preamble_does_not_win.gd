extends GutTest

## A model that fences its reasoning AND its answer returned the reasoning.
##
## Step 2 of _extract_json_from_raw took the FIRST ``` and the next one. For
##
##     ```json\n{"thinking":true}\n```\n```json\n{"rules":[…]}\n```
##
## that is the preamble — and it parsed, so the function RETURNED SUCCESSFULLY and
## the brace scan below it never ran. A Dictionary came back, every is-it-a-dict
## assertion passed, and the player's rule composition was the model's throat-
## clearing. Same first-match-wins defect as the preamble OBJECT fix one stage down,
## where that fix could not help because this stage returns first.
##
## ⛔ HOW IT SURFACED, which is the part worth keeping: a stage-coverage sweep found
## that DELETING step 2 outright was unnoticed by all 8 driver files. Checking whether
## it was merely redundant showed the opposite — the two-fence reply FAILED with the
## stage present and PASSED with it deleted. The dead-code hypothesis was wrong in the
## most useful direction.
##
## Blocks are now tried LAST first, the same rule as the brace scan and for the same
## reason: a preamble precedes the answer.

const ANSWER := '{"rules":[1]}'


func _x(raw: String) -> Variant:
	return LLMService._extract_json_from_raw(raw)


func test_a_fenced_preamble_does_not_beat_the_fenced_answer() -> void:
	## THE DEFECT. Both blocks parse, so "first that parses" is not a tiebreak — it is
	## the wrong answer returned confidently.
	var raw: String = "```json\n{\"thinking\":true}\n```\n```json\n" + ANSWER + "\n```"
	var got: Variant = _x(raw)
	assert_true(got is Dictionary, "a two-block fenced reply parsed to nothing: %s" % [got])
	assert_true((got as Dictionary).has("rules"),
		("the fenced PREAMBLE was returned instead of the fenced answer: %s. Blocks must be "
		+ "tried last-first — the model's reply is the last thing it emits.") % [got])


func test_the_last_of_three_blocks_wins() -> void:
	## Two blocks could be satisfied by "take the second"; three cannot.
	var raw: String = ("```\n{\"a\":1}\n```\n```\n{\"b\":2}\n```\n```json\n" + ANSWER + "\n```")
	var got: Variant = _x(raw)
	assert_true(got is Dictionary and (got as Dictionary).has("rules"),
		"with three blocks the LAST must win, got %s" % [got])


func test_a_single_tagged_block_still_parses() -> void:
	## FLOOR. The ordinary shape, so a change to the scan cannot trade it for the exotic ones.
	##
	## ⚠️ AND IT DOES NOT COVER THE TAG STRIP, despite reading as though it does. Measured:
	## deleting the strip leaves this arm GREEN, because the brace scan one stage down
	## recovers the same reply. The strip's only distinct cover is the three-block arm.
	## The mirror of the usual trap — an EARLIER stage absorbing your fixture is the
	## famous one; a LATER stage absorbing your MUTATION is the same blindness, and it
	## means a resilient chain makes arms look load-bearing when the system, not the
	## arm, is what is holding.
	var got: Variant = _x("```json\n" + ANSWER + "\n```")
	assert_true(got is Dictionary and (got as Dictionary).has("rules"),
		"the ordinary ```json block stopped parsing: %s" % [got])


func test_a_bare_block_with_no_language_tag_still_parses() -> void:
	## The tag strip is conditional; a bare fence has no tag to drop and must survive it.
	var got: Variant = _x("```\n" + ANSWER + "\n```")
	assert_true(got is Dictionary and (got as Dictionary).has("rules"),
		"a bare ``` block stopped parsing — the tag strip ate a line it should not have: %s" % [got])


func test_an_unterminated_fence_falls_through_to_the_brace_scan() -> void:
	## A reply cut off mid-stream opens a fence and never closes it. That is not a block;
	## reporting it as one would hand a truncated string to the parser and shadow the
	## stages below, whose job this is.
	var got: Variant = _x("```json\n" + ANSWER)
	assert_true(got is Dictionary and (got as Dictionary).has("rules"),
		"an unterminated fence lost the reply: %s" % [got])
	assert_eq(LLMService._fenced_blocks("```json\n" + ANSWER), ([] as Array[String]),
		"an unterminated fence was reported as a complete block")


# ── controls: the ordering is the claim, so pin it directly ───────────────────

func test_the_block_scan_returns_them_last_first() -> void:
	## FLOOR on the ORDER, asserted on the scan itself rather than inferred from which
	## object came back. An arm that only checks the end result cannot tell "last-first"
	## from "the first one happened not to parse".
	var blocks: Array[String] = LLMService._fenced_blocks(
		"```\n{\"a\":1}\n```\n```\n{\"b\":2}\n```")
	assert_eq(blocks.size(), 2, "the scan found %d blocks in a two-block reply" % blocks.size())
	assert_eq(blocks[0], '{"b":2}',
		"blocks are not returned last-first — got %s, so a preamble would win" % [blocks])


func test_a_reply_with_no_fence_is_untouched() -> void:
	## FLOOR. The fence stage must not disturb the common case of a bare object.
	assert_eq(LLMService._fenced_blocks("Here is your result: " + ANSWER),
		([] as Array[String]), "a fenceless reply produced blocks")
	var got: Variant = _x("Here is your result: " + ANSWER)
	assert_true(got is Dictionary and (got as Dictionary).has("rules"),
		"a fenceless reply stopped parsing: %s" % [got])
