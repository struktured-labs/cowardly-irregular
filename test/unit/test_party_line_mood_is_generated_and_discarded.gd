extends GutTest

## The model produces a MOOD for every party combat line, and the game throws it away.
##
## SCHEMA_PARTY_LINE requires {"line": String, "mood": String}, so every party-line
## generation is constrained to emit a mood. validate_party_line checks it against
## the five authored values. Then BattleManager._run_party_line_async reads
## `validated.get("line", "")` and nothing reads `mood`.
##
## Measured 2026-09-10: `mood` has ZERO consumers in src/ outside DialoguePrompts.
## The only other occurrences are RoamingMonster's own unrelated Mood enum and two
## audio comments. `git log -S` finds no commit that ever read it — dead since it
## was introduced on 2026-06-17, not a regression, and not documented as a seam
## the way the voice_<job>_<trigger> handles are.
##
## ⛔ NOT WIRED HERE, and not removed either. What a mood should DO — tint the quip
## bubble, pick a voice, change its dwell time — is a design call with a taste axis,
## and struktured has pushed back on battle presentation before. Removing it would
## save tokens on every party line but destroy five deliberately authored values for
## a saving I have not measured. So: pinned as a KNOWN GAP, with the validation a
## future consumer would depend on actually tested, so wiring it is a small change
## rather than an investigation.

const DP := preload("res://src/llm/DialoguePrompts.gd")


# ── the validation a future consumer would rely on ────────────────────────────

func test_the_schema_requires_a_mood_so_the_model_always_pays_for_one() -> void:
	assert_true(DP.SCHEMA_PARTY_LINE.has("mood"),
		"the cost side of this gap: every party line is generated with a mood field")
	assert_gt(DP.PARTY_LINE_MOODS.size(), 0,
		"CONTROL: there must be authored moods, or none of this means anything")


func test_a_valid_mood_survives_validation() -> void:
	for m in DP.PARTY_LINE_MOODS:
		var out: Dictionary = DP.validate_party_line({"line": "We hold.", "mood": m})
		assert_eq(str(out.get("mood", "")), str(m),
			"'%s' is authored and must survive validation intact" % m)


func test_an_invented_mood_falls_back_rather_than_passing_through() -> void:
	## The property that makes wiring this SAFE later: a consumer can match on the
	## five values without a default arm for model-invented ones.
	var out: Dictionary = DP.validate_party_line({"line": "We hold.", "mood": "apoplectic"})
	assert_true(str(out.get("mood", "")) in DP.PARTY_LINE_MOODS,
		"a mood outside the authored set must be replaced, not forwarded")
	assert_eq(str(out.get("mood", "")), "neutral",
		"and the replacement must be neutral, so an unexpected mood reads as 'no strong feeling'")


func test_mood_is_case_and_whitespace_tolerant() -> void:
	var out: Dictionary = DP.validate_party_line({"line": "We hold.", "mood": "  PANICKED "})
	assert_eq(str(out.get("mood", "")), "panicked",
		"models capitalise and pad; the validator must normalise rather than reject to neutral")


func test_a_missing_mood_is_neutral_not_empty() -> void:
	var out: Dictionary = DP.validate_party_line({"line": "We hold."})
	assert_eq(str(out.get("mood", "")), "neutral",
		"an absent mood must land on a real value — an empty string would break a match arm")


func test_the_fallback_envelope_carries_a_valid_mood_too() -> void:
	## The fallback is what a consumer sees when the model fails, which is exactly
	## when nobody is looking. It must satisfy the same contract.
	var out: Dictionary = DP.validate_party_line("not a dictionary at all")
	assert_true(str(out.get("mood", "")) in DP.PARTY_LINE_MOODS,
		"the fallback envelope's mood must be one of the authored values")


# ── the gap itself, pinned so it cannot quietly become "fine" ─────────────────

func test_known_gap_no_consumer_reads_the_mood() -> void:
	## INVERTED. This asserts the CURRENT, WRONG state: the mood is generated,
	## validated, and dropped. When someone wires it, this reds — and the correct
	## response is to DELETE this test, not to re-baseline it.
	##
	## Scoped to the battle consumer that actually receives the validated dict,
	## rather than grepping src/ for the word "mood" — RoamingMonster has its own
	## unrelated Mood enum and would make a repo-wide scan report a false consumer.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_false(src.is_empty(), "CONTROL: BattleManager source must load")
	var anchor: int = src.find("validate_party_line(")
	assert_gt(anchor, -1,
		"CONTROL: the party-line validation call must exist, or this test is pinned to nothing")
	# Read from the call to the end of its enclosing function.
	var next_fn: int = src.find("\nfunc ", anchor)
	var body: String = src.substr(anchor, (next_fn - anchor) if next_fn > anchor else 400)
	assert_true(body.find("\"line\"") != -1,
		"CONTROL: the consumer must read the line, proving this window covers the right code")
	assert_eq(body.find("\"mood\""), -1,
		"the mood now has a consumer — good. Delete this test rather than re-baselining it, and check that the five authored values are all handled.")
