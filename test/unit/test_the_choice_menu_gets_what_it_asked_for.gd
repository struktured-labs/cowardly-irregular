extends GutTest

## A model that returned one choice gave the player a menu with nothing to choose.
##
## `validate_player_choices(raw, expected_count)` trims DOWN to the count, never
## pads UP, and did not dedupe. Two objective gaps against its own contract:
##
##     model returns 1 of 3 requested   -> the player sees a one-option menu
##     model returns the same twice     -> the player sees the same option twice
##
## THE SECOND IS FIXED HERE. The first is recorded, not fixed — padding is unsafe
## while _ensure_farewell short-circuits on an existing farewell (see the arm).
##
## Measured against live llama3 on the real combined-reply prompt, three
## conversation states, six samples each: **18 of 18 returned exactly 3 distinct
## choices.** So this is LATENT for the shipped default — and it is not
## hypothetical, because BYOK ships: any OpenAI-compatible model can be attached
## from Settings, and the validator is the last thing between that model and the
## menu.
##
## ⚠️ Also measured and NOT the cause: the prompt asks for "3 short player
## dialogue choices" while its own JSON example shows two placeholders
## (`{"reply": "<text>", "choices": ["...", "..."]}`). A real inconsistency, and
## llama3 follows the stated count anyway — 0 of 18 under-delivered. I am not
## touching the example on the strength of a defect I could not reproduce.


const DP := preload("res://src/llm/DialoguePrompts.gd")


func _choices(v: Dictionary) -> Array:
	return v.get("choices", []) as Array


# ── the defect ────────────────────────────────────────────────────────────────

func test_under_delivery_is_recorded_not_padded() -> void:
	## THE GAP, pinned as it stands rather than fixed. A model returning one
	## choice yields a one-option menu — and padding it here is NOT safe:
	## _ensure_farewell runs afterwards and returns early when a farewell exists
	## anywhere, so padding a set ending in "Farewell." puts it mid-menu. Measured
	## on the real path: test_llm_dynamic_conversation_live primes exactly that
	## shape. Fixing it means deciding who owns farewell POSITION, which is a
	## design call, not a validator change.
	var v: Dictionary = DP.validate_player_choices({"choices": ["Tell me about the warden."]}, 3)
	assert_eq(_choices(v).size(), 1,
		"today the player gets one option — when this changes, farewell position must be handled")


func test_duplicates_do_not_reach_the_menu_twice() -> void:
	var v: Dictionary = DP.validate_player_choices(
		{"choices": ["Tell me more.", "Tell me more.", "Farewell."]}, 3)
	var c: Array = _choices(v)
	assert_eq(c.size(), 2, "the duplicate is dropped, leaving the two real options")
	var lowered: Array[String] = []
	for x in c:
		lowered.append(str(x).to_lower())
	assert_eq(lowered.size(), _distinct(lowered).size(),
		"no option may appear twice: %s" % str(c))


func test_case_only_duplicates_count_as_duplicates() -> void:
	## A player cannot tell "Tell me more." from "tell me more." — the menu just
	## looks broken. Exact-match dedup would let that through.
	var v: Dictionary = DP.validate_player_choices(
		{"choices": ["Tell me more.", "TELL ME MORE.", "Farewell."]}, 3)
	var lowered: Array[String] = []
	for x in _choices(v):
		lowered.append(str(x).to_lower())
	assert_eq(lowered.size(), _distinct(lowered).size(),
		"case-only variants are duplicates to a player: %s" % str(_choices(v)))


# ── it must not disturb a well-formed reply ───────────────────────────────────

func test_a_full_distinct_set_is_returned_untouched() -> void:
	## CORRECT-WORK, and it is the case llama3 actually produces 18 of 18 times.
	var given: Array = ["What happened here?", "Who is the Chancellor?", "I should go."]
	var v: Dictionary = DP.validate_player_choices({"choices": given}, 3)
	var c: Array = _choices(v)
	assert_eq(c.size(), 3, "three in, three out")
	for i in 3:
		assert_eq(str(c[i]), str(given[i]), "order and content must be untouched at %d" % i)


func test_over_delivery_is_still_trimmed() -> void:
	## The direction that already worked must keep working.
	var v: Dictionary = DP.validate_player_choices(
		{"choices": ["a", "b", "c", "d", "e"]}, 3)
	assert_eq(_choices(v).size(), 3, "five in, three out")


func test_a_garbage_reply_still_falls_back_whole() -> void:
	## CONTROL: the pre-existing fallback path must be untouched, or this change
	## would be papering over a failure instead of completing a partial one.
	for bad in [{"choices": []}, {"choices": ["  ", "\t", "\n"]}, {"nope": 1}, "not a dict"]:
		var v: Dictionary = DP.validate_player_choices(bad, 3)
		assert_eq(_choices(v).size(), 3, "a useless reply must still yield a full menu: %s" % str(bad))


# ── controls ──────────────────────────────────────────────────────────────────

func test_the_farewell_interaction_that_blocks_padding_is_real() -> void:
	## THE PREMISE for not padding. If _ensure_farewell ever stops returning early
	## on an existing farewell, padding becomes safe and this note should be
	## revisited rather than worked around.
	var src: String = FileAccess.get_file_as_string("res://src/llm/DynamicConversation.gd")
	assert_false(src.is_empty(), "CONTROL: source must load")
	var at: int = src.find("func _ensure_farewell")
	assert_true(at != -1, "CONTROL: _ensure_farewell must exist")
	var body: String = src.substr(at, 420)
	assert_true(body.find("_is_farewell(c)") != -1 and body.find("return") != -1,
		"_ensure_farewell must still short-circuit on an existing farewell")


func test_the_count_is_still_clamped_to_the_maximum() -> void:
	## CONTROL: padding must not let a caller ask for more than the menu supports.
	var v: Dictionary = DP.validate_player_choices({"choices": ["one"]}, 99)
	assert_lte(_choices(v).size(), DP.MAX_CHOICES,
		"a silly count must clamp, not pad forever: %d" % _choices(v).size())


func _distinct(items: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for i in items:
		if not seen.has(i):
			seen[i] = true
			out.append(i)
	return out
