extends GutTest

## A model that returned one choice gave the player a menu with nothing to choose.
##
## `validate_player_choices(raw, expected_count)` trims DOWN to the count, never
## pads UP, and did not dedupe. Two objective gaps against its own contract:
##
##     model returns 1 of 3 requested   -> the player sees a one-option menu
##     model returns the same twice     -> the player sees the same option twice
##
## THE SECOND IS FIXED HERE. The first is still recorded, not fixed — but the
## reason changed: padding was unsafe while _ensure_farewell short-circuited on an
## existing farewell. That short-circuit was the exit-position bug and is gone, so
## padding is now merely undone, not blocked (see the arm).
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
	## THE GAP, pinned as it stands rather than fixed. A model returning one choice
	## yields a one-option menu. Padding here used to be unsafe because
	## _ensure_farewell returned early when a farewell existed anywhere, stranding
	## it mid-menu; that short-circuit is gone and the exit is now always last, so
	## nothing blocks padding any more. It is simply not done: llama3 returns the
	## full count 18 of 18, so the gap is latent and belongs to its own change.
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

func test_the_blocker_that_justified_not_padding_is_gone() -> void:
	## THE PREMISE, INVERTED. This used to assert that _ensure_farewell short-circuits
	## on an existing farewell — the reason padding was unsafe. That short-circuit
	## was the position bug, and it is fixed: the exit is moved to last, so a padded
	## set can no longer strand a goodbye mid-menu.
	##
	## Padding is still NOT done, but it is now a free decision rather than a blocked
	## one. Kept as a source check so this file stops citing a mechanism that is gone.
	## Scoped to the function, not to a character count. A fixed window over raw
	## source is measured in prose as much as code, so an explanatory line added
	## inside the function would red this arm on a correct change. Comments are
	## stripped first so a "func " inside one cannot end the span early.
	var src: String = _code_only(
		FileAccess.get_file_as_string("res://src/llm/DynamicConversation.gd"))
	assert_false(src.is_empty(), "CONTROL: source must load")
	var at: int = src.find("func _ensure_farewell")
	assert_true(at != -1, "CONTROL: _ensure_farewell must exist")
	var ends_at: int = src.find("\nfunc ", at + 1)
	if ends_at == -1:
		ends_at = src.length()
	var body: String = src.substr(at, ends_at - at)
	assert_gt(body.length(), 80, "CONTROL: the function body must not be empty")
	assert_true(body.find("choices.append(exit_line)") != -1,
		("_ensure_farewell no longer ends by appending the exit. If it went back to "
		+ "short-circuiting on an existing farewell, the exit can sit on the "
		+ "pre-selected row again and padding becomes unsafe a second time."))


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


func _code_only(src: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		var hash_at: int = line.find("#")
		out.append(line if hash_at == -1 else line.substr(0, hash_at))
	return "\n".join(out)
