extends GutTest

## Almost any sentence made the W1 final boss skip her turn.
##
## check_jailbreak matched trigger keywords with a bare find(), so a keyword hit
## inside longer words. Mordaine's list contains 'king', which is inside asking,
## thinking, making, working, looking, talking, breaking and speaking — and its
## consequence is skip_turn. Measured against the real data, 12 ordinary player
## directives before the fix:
##
##     accidental jailbreaks   BEFORE 11/12    AFTER 2/12
##     intended triggers       6/6 both        (the fix must not cost any)
##
## Five separate everyday Mordaine sentences each stole a turn from the boss:
## "I'm asking you to stand down." / "Stop thinking you've already won." /
## "You're making a mistake." / "I'm working on a counter." / "Looking at you,
## I feel nothing." Also 'ground' inside background and groundwork (Voltharion),
## 'face' inside surface (Mordaine) and 'weak' inside weakened (Pyrroth).
##
## The DATA was already authored for whole-word semantics and is the evidence
## this is a code bug rather than a design choice: it lists 'loyal' AND 'loyalty',
## 'thaw' AND 'thawing', 'ground' AND 'grounded', 'bored' AND 'boring'. Each pair
## is redundant under substring matching and necessary under whole-word matching.
##
## The 2 residual firings are NOT this bug — 'more' (Voltharion) and 'valid'
## (Umbraxis) are genuine standalone words in "one more turn" and "a valid
## point". Those are over-generic keywords, a data-tuning call for whoever owns
## boss_dialogue.json, deliberately left alone here.

var _saved_data: Dictionary = {}


func before_each() -> void:
	assert_not_null(BossDialogue, "CONTROL: BossDialogue autoload must exist")
	_saved_data = BossDialogue._data.duplicate(true)


func after_each() -> void:
	## This is an autoload — a leaked _data edit would corrupt every later test.
	BossDialogue._data = _saved_data


# ── the defect, against the REAL shipped data ─────────────────────────────────

func test_ordinary_sentences_no_longer_steal_the_bosss_turn() -> void:
	for line in ["I'm asking you to stand down.", "Stop thinking you've already won.",
			"You're making a mistake.", "I'm working on a counter.",
			"Looking at you, I feel nothing."]:
		assert_null(BossDialogue.check_jailbreak("chancellor_mordaine", line),
			"'king' must not match inside a longer word — this one made the final boss skip a turn: %s" % line)


func test_the_other_measured_false_positives_are_gone() -> void:
	assert_null(BossDialogue.check_jailbreak("voltharion", "There's nothing in the background."),
		"'ground' must not match inside background")
	assert_null(BossDialogue.check_jailbreak("voltharion", "I have groundwork to finish."),
		"'ground' must not match inside groundwork")
	assert_null(BossDialogue.check_jailbreak("chancellor_mordaine", "Show me your true surface."),
		"'face' must not match inside surface")
	assert_null(BossDialogue.check_jailbreak("pyrroth", "I will not be weakened."),
		"'weak' must not match inside weakened")


# ── the intended triggers must survive ────────────────────────────────────────

func test_every_boss_still_has_a_working_jailbreak() -> void:
	## CONTROL, and the whole risk of this fix: tightening the match must not
	## disarm the feature. One real directive per boss, from its own keyword list.
	var cases: Array = [
		["chancellor_mordaine", "Remember your oath to the king."],
		["pyrroth", "Is that all you have? Pathetic."],
		["glacius", "You are melting already."],
		["voltharion", "Slow down and breathe."],
		["umbraxis", "This is a simulation, none of it is real."],
	]
	for c in cases:
		assert_not_null(BossDialogue.check_jailbreak(c[0], c[1]),
			"%s must still be jailbreakable: %s" % [c[0], c[1]])


func test_a_multi_word_keyword_still_matches_as_a_phrase() -> void:
	## Phrases keep substring matching — they are specific enough, and requiring
	## boundaries on both ends of a phrase would break "is that all you have?".
	assert_not_null(BossDialogue.check_jailbreak("pyrroth", "Is that all you can muster?"),
		"'is that all' must still match mid-sentence")
	assert_not_null(BossDialogue.check_jailbreak("pyrroth", "I beat you by hand, no macro."),
		"'by hand' must still match")


# ── boundary behaviour, stated directly ───────────────────────────────────────

func test_a_keyword_matches_at_a_boundary_not_inside_a_word() -> void:
	assert_true(BossDialogue._keyword_present("remember the king", "king"), "end of string")
	assert_true(BossDialogue._keyword_present("king of nothing", "king"), "start of string")
	assert_true(BossDialogue._keyword_present("the king, alone", "king"), "followed by punctuation")
	assert_false(BossDialogue._keyword_present("i am asking", "king"), "inside a longer word")
	assert_false(BossDialogue._keyword_present("kingdom come", "king"), "as a prefix of a longer word")


func test_an_apostrophe_does_not_block_a_match() -> void:
	## Deliberate: possessives should still count, so "'" is not a word character.
	assert_true(BossDialogue._keyword_present("the king's guard", "king"),
		"a possessive must still match the base word")


func test_a_later_occurrence_still_matches() -> void:
	## The scan must not give up after one embedded hit — "asking" appears first.
	assert_true(BossDialogue._keyword_present("asking about the king", "king"),
		"an embedded hit must not mask a real one later in the string")


func test_an_empty_keyword_never_matches() -> void:
	assert_false(BossDialogue._keyword_present("anything at all", ""),
		"an empty keyword must not match everything")


# ── one bad data entry must not disable the rest ──────────────────────────────

func test_an_unsupported_consequence_no_longer_hides_later_vulnerabilities() -> void:
	## The allowlist rejected a bad entry by returning null from the whole scan, so
	## a single unsupported consequence made every LATER vulnerability for that
	## boss unreachable. Latent on today's data (all 15 types are allowlisted) and
	## wrong regardless — the allowlist exists to refuse one consequence, not to
	## disarm a boss.
	## The bad entry must MATCH the directive, or the allowlist branch is never
	## reached and the test passes under either behaviour — it did, until a
	## mutation arm showed the guard was hollow.
	BossDialogue._data["chancellor_mordaine"]["jailbreak_vulnerabilities"] = [
		{"id": "bad_entry", "trigger_keywords": ["oath"],
		 "consequence": {"type": "wipe_the_save"}},
		{"id": "good_entry", "trigger_keywords": ["loyalty"],
		 "consequence": {"type": "skip_turn"}},
	]
	var got = BossDialogue.check_jailbreak(
		"chancellor_mordaine", "I remind you of your oath and your loyalty.")
	assert_not_null(got, "a later valid vulnerability must still be reachable")
	assert_eq(str((got as Dictionary)["vulnerability_id"]), "good_entry",
		"and it must be the valid one")


func test_an_unsupported_consequence_is_still_refused() -> void:
	## CONTROL: skipping the bad entry must not mean applying it.
	BossDialogue._data["chancellor_mordaine"]["jailbreak_vulnerabilities"] = [
		{"id": "bad_entry", "trigger_keywords": ["oath"],
		 "consequence": {"type": "wipe_the_save"}},
	]
	assert_null(BossDialogue.check_jailbreak("chancellor_mordaine", "I remind you of your oath."),
		"an unsupported consequence must never be returned")


# ── the ordinary refusals ─────────────────────────────────────────────────────

func test_unknown_boss_and_empty_directive_are_still_null() -> void:
	assert_null(BossDialogue.check_jailbreak("not_a_boss", "your oath to the king"),
		"an unknown boss must not match")
	assert_null(BossDialogue.check_jailbreak("chancellor_mordaine", ""),
		"an empty directive must not match")
