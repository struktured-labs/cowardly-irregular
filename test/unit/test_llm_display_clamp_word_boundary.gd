extends GutTest

## Player-visible LLM text must not be cut off mid-word.
##
## FOUND LIVE (cowir-ai, 2026-07-29): every player-facing string from the LLM
## was trimmed with a bare `.left(n)`. A boss taunt one word over budget shipped
## to the combat log as "...until something finally dies " — stopped dead inside
## whatever word straddled the limit, no ellipsis, nothing to signal it was cut.
##
## THE TRUNCATED CASE IS THE EXPECTED CASE, NOT THE EDGE CASE. The prompt states
## a budget and the clamp exists because models overshoot it; a clamp nothing
## ever hit would not have been written. So this is the normal rendering path
## for a long generation, and it was the ugliest possible one.
##
## SCOPE — six player-visible sites converted. Two bare `.left()` calls remain
## and are deliberate: `reason` (MAX_BOSS_REASON_CHARS) is the LLM's private
## justification for its intent pick and is logged, never rendered; and
## LLMService's MAX_TEXT_CHARS guards raw transport, upstream of any speaker.
## Cosmetic ellipsis on text no player reads would be noise.

const DP := preload("res://src/llm/DialoguePrompts.gd")

## Long enough to overshoot every budget in the file.
const LONG: String = ("You throw fire at fire. Bold. Or is that a script that has run out of ideas " +
	"and is now simply repeating itself until something finally dies of boredom, which " +
	"would at least be a novel cause of death in this particular cave.")


# ── The helper's contract ────────────────────────────────────────────────────

func test_short_text_is_returned_unchanged() -> void:
	assert_eq(DP.clamp_display("Short line.", 140), "Short line.",
		"text within budget must be untouched — no ellipsis, no trim")


func test_text_exactly_at_budget_is_unchanged() -> void:
	var s: String = "x".repeat(40)
	assert_eq(DP.clamp_display(s, 40), s, "exactly at the budget is not over it")


func test_result_never_exceeds_the_budget() -> void:
	# Every caller's contract is a hard cap; adding an ellipsis must not break it.
	for cap in [20, 40, 80, 140, 200]:
		var out: String = DP.clamp_display(LONG, cap)
		assert_lte(out.length(), cap,
			"clamp_display(%d) returned %d chars — the ellipsis must fit INSIDE the budget" % [cap, out.length()])


func test_long_text_is_not_cut_mid_word() -> void:
	# THE DEFECT. The old `.left(140)` ended inside a word; the replacement must
	# end at a word boundary and say that it was cut.
	#
	# SWEPT ACROSS BUDGETS, NOT PINNED TO ONE. A single cap tests a single offset
	# into a single string, and whether THAT offset lands mid-word is a
	# coincidence of the sentence. Verified: a mutant that hard-cuts at the
	# budget and appends the ellipsis anyway passes at cap 140 — trailing-space
	# stripping happens to leave a clean boundary there — and fails across the
	# sweep. The property is "never mid-word", so every budget must hold it.
	for cap in range(30, 200, 7):
		var out: String = DP.clamp_display(LONG, cap)
		assert_true(out.ends_with("…"),
			"[cap %d] a truncated line must signal that it was truncated: %s" % [cap, out])
		var body: String = out.trim_suffix("…").strip_edges()
		assert_true(LONG.begins_with(body),
			"[cap %d] the kept text must be a genuine prefix of the original, not a reflow: %s" % [cap, body])
		var next_char: String = LONG.substr(body.length(), 1)
		assert_eq(next_char, " ",
			("[cap %d] truncation landed mid-word — kept text ends '%s' and the original continues '%s'. " +
			"That is the bare .left() behaviour this replaced.")
			% [cap, body.right(12), LONG.substr(body.length(), 12)])


func test_single_overlong_word_still_fits_the_budget() -> void:
	# No space to cut at. A hard cut is correct here; silently returning the
	# whole word would blow the caller's budget.
	var out: String = DP.clamp_display("W".repeat(300), 40)
	assert_lte(out.length(), 40, "an unbroken word must still be clamped")
	assert_true(out.ends_with("…"), "and must still signal truncation")


# ── The call sites actually use it ───────────────────────────────────────────

func test_boss_taunt_is_clamped_at_a_word_boundary() -> void:
	var out: Dictionary = DP.validate_boss_intent(
		{"intent_id": "aggress", "reason": "r", "taunt": LONG}, ["aggress"])
	var taunt: String = str(out.get("taunt", ""))
	assert_lte(taunt.length(), DP.MAX_BOSS_TAUNT_CHARS, "taunt must respect its budget")
	assert_true(taunt.ends_with("…"),
		"an over-budget boss taunt goes to the combat log — it must not stop mid-word: %s" % taunt)


func test_npc_opening_is_clamped_at_a_word_boundary() -> void:
	var out: Dictionary = DP.validate_npc_opening({"line": LONG})
	var line: String = str(out.get("line", ""))
	assert_lte(line.length(), DP.MAX_LINE_CHARS, "npc opening must respect its budget")
	assert_true(line.ends_with("…"), "an over-budget NPC opening must not stop mid-word: %s" % line)


func test_npc_reply_is_clamped_at_a_word_boundary() -> void:
	var out: Dictionary = DP.validate_npc_reply({"line": LONG})
	var line: String = str(out.get("line", ""))
	assert_true(line.ends_with("…"), "an over-budget NPC reply must not stop mid-word: %s" % line)


func test_party_line_is_clamped_at_a_word_boundary() -> void:
	var out: Dictionary = DP.validate_party_line({"line": LONG, "mood": "cocky"})
	var line: String = str(out.get("line", ""))
	assert_lte(line.length(), DP.MAX_PARTY_LINE_CHARS, "party line must respect its budget")
	assert_true(line.ends_with("…"),
		"party lines render in a speech bubble anchored to the speaker — mid-word is worse there than in a log: %s" % line)


func test_no_player_visible_site_still_uses_a_bare_left() -> void:
	# Derived, so a NEW player-visible clamp added later is caught rather than
	# quietly reintroducing the defect. The two survivors are named and justified
	# in this file's header; anything else is a regression.
	const ALLOWED: Array[String] = ["MAX_BOSS_REASON_CHARS", "MAX_TEXT_CHARS"]
	var src: String = FileAccess.get_file_as_string("res://src/llm/DialoguePrompts.gd")
	assert_false(src.is_empty(), "DialoguePrompts must be readable")
	var re := RegEx.new()
	re.compile("\\.left\\((MAX_[A-Z_]+)\\)")
	var found: int = 0
	for m in re.search_all(src):
		found += 1
		assert_true(ALLOWED.has(m.get_string(1)),
			("a player-visible string is trimmed with a bare .left(%s), which cuts mid-word. " +
			"Use clamp_display(text, %s) instead, or add it to this test's ALLOWED list with a " +
			"reason it is never rendered.") % [m.get_string(1), m.get_string(1)])
	assert_gt(found, 0,
		"the .left(MAX_*) scan matched nothing — the pattern has broken, so this guard proves nothing")
