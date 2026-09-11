extends GutTest

## The boss was offered three postures as bare jargon and always picked one.
##
## build_boss_intent rendered `  - aggress` / `  - turtle` / `  - exploit_pattern`
## with no meanings. Only the first reads as plain English, and the deterministic
## ladder still owns ability choice — so the intent IS this feature's entire
## strategic contribution, and it was effectively a constant.
##
## MEASURED against local llama3, through the real builder:
##
##   bare list, 4 scenarios          40 of 44 chose aggress
##   with descriptions, 3 scenarios  30 of 30 chose aggress   <- NO CHANGE
##   turtle listed FIRST             7 aggress / 3 turtle     <- position bias
##   aggressive framing removed      10 of 10 aggress         <- not the cause
##
## So these descriptions are shipped because the prompt was offering jargon with
## no meaning, NOT because they fixed selection. The measured cause is position
## bias, and the residual skew is a property of this model. Exploiting the bias by
## rotating the list was deliberately not done: it would make the boss's posture
## track the phase counter rather than the board, which looks like strategy and is
## not — the appearance of a decision is worse than an honest constant.
##
## What this file actually defends is narrower and durable: the prompt must
## describe only postures the engine can deliver.

const DP := preload("res://src/llm/DialoguePrompts.gd")


func _prompt(intents: Array) -> String:
	return DP.build_boss_intent("Chancellor Mordaine", {
		"persona": "The usurper.", "phase": 2,
		"boss_hp_pct": 40.0, "boss_mp_pct": 20.0, "boss_ap": 0,
		"party": [{"name": "Rilla", "job_id": "cleric", "hp_pct": 90.0, "is_alive": true}],
		"available_intents": intents,
	})


# ── the offered list carries meanings ─────────────────────────────────────────

func test_each_offered_intent_is_explained() -> void:
	var p: String = _prompt(["aggress", "turtle", "exploit_pattern"])
	assert_true(p.find("aggress: press the attack") != -1, "aggress must be explained")
	assert_true(p.find("turtle: defend and outlast") != -1,
		"turtle is jargon and was never once chosen while unexplained")
	assert_true(p.find("exploit_pattern: counter what they keep repeating") != -1,
		"exploit_pattern must be explained")


func test_the_description_says_WHEN_not_only_what() -> void:
	## A definition the model cannot act on is decoration. Each line names the
	## board state it suits, which is the part that could discriminate.
	var p: String = _prompt(["turtle"])
	assert_true(p.find("Best when YOU are hurt") != -1,
		"turtle must name the situation it fits, not merely define the word")


# ── the guard that matters: never advertise a posture the engine won't adopt ───

func test_every_described_intent_reaches_a_bias_arm() -> void:
	## Weaker than the check this replaces, and honestly so. The previous version
	## searched BattleManager for `"<id>":` and called that "has a real bias arm".
	## That is not what it tested: the six counter tags SHARE one match arm written
	## `"fire_resist", "ice_resist", ...:`, which the pattern cannot see. It got the
	## right answer for five of them BY COINCIDENCE OF PUNCTUATION and the wrong
	## answer for rotate_aggro, which sits in that same arm and DOES fire.
	##
	## This asserts what source can actually establish: the id appears in
	## _bias_by_intent's match, in either arm form.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_false(src.is_empty(), "CONTROL: BattleManager must be readable")
	var at: int = src.find("func _bias_by_intent")
	assert_gt(at, -1, "CONTROL: _bias_by_intent must exist, or this measures nothing")
	# Extract by BOUNDARY, not by a byte count. A fixed window is a coincidental
	# magnitude: this first used substr(at, 1800) and cut the function off before
	# exploit_pattern and the shared arm, failing two intents that were present.
	var next_func: int = src.find("\nfunc ", at + 1)
	var body: String = src.substr(at, (next_func if next_func != -1 else src.length()) - at)
	assert_true(body.find("exploit_pattern") != -1,
		"CONTROL: the extracted body must reach the LAST arm, or the scan is measuring a truncation")
	# Match-ARM lines only. The body quotes intent names in its comments too —
	# `aggress` appears quoted twice, once on an arm and once in prose — so a bare
	# find() would pass for an intent that is merely DISCUSSED and has no arm.
	var arm_lines: PackedStringArray = PackedStringArray()
	for line in body.split("\n"):
		var t: String = line.strip_edges()
		if t.ends_with(":") and t.begins_with("\""):
			arm_lines.append(t)
	assert_gt(arm_lines.size(), 0,
		"CONTROL: no match arms extracted — the scan found nothing to check against")
	for id in DP.INTENT_DESCRIPTIONS.keys():
		var on_arm: bool = false
		for t in arm_lines:
			if t.find('"%s"' % str(id)) != -1:
				on_arm = true
		assert_true(on_arm,
			("'%s' is described to the model but sits on no match arm in _bias_by_intent " +
			"(a mention in a comment does not count)") % str(id))


func test_the_inert_intents_are_excluded_by_EVIDENCE_not_by_punctuation() -> void:
	## THE CORRECTION. Nothing structural separates the inert five from
	## rotate_aggro — they share a match arm and all six return a non-empty bias.
	## The separation is measured downstream behaviour (_get_counter_action builds
	## nothing for five of them: 0.000 over 400 rolls each, against rotate_aggro's
	## 0.600), so the exclusion is an authored list carrying that evidence.
	##
	## Fails if anyone describes one of the five, and equally if the list is
	## quietly emptied to make the test above pass.
	assert_eq(DP.BOSS_INTENT_INERT.size(), 5,
		"five intents are measured inert; changing that count needs a new measurement, not an edit")
	for id in DP.BOSS_INTENT_INERT:
		assert_false(DP.INTENT_DESCRIPTIONS.has(str(id)),
			"'%s' produces no action — it must not be described as a working posture" % str(id))


func test_rotate_aggro_is_described_because_it_actually_fires() -> void:
	## The member the old criterion got WRONG. It shares the inert five's match arm,
	## so a punctuation-based rule withheld it; it fires 0.600 of the time, so
	## withholding it was never justified.
	assert_true(DP.INTENT_DESCRIPTIONS.has("rotate_aggro"),
		"rotate_aggro fires and must be explained like any other working posture")
	assert_false(DP.BOSS_INTENT_INERT.has("rotate_aggro"),
		"and must not be listed among the inert, which is the error being corrected")


func test_an_undescribed_intent_is_still_offered() -> void:
	## It must render bare rather than vanish: withholding an intent the boss's
	## data authored would silently narrow the allowlist the validator enforces.
	var p: String = _prompt(["aggress", "fire_resist"])
	assert_true(p.find("- fire_resist") != -1,
		"an undescribed intent must still appear in the list")
	assert_eq(p.find("fire_resist:"), -1, "but without an invented explanation")


# ── the surrounding contract must survive ─────────────────────────────────────

func test_the_verbatim_rule_still_applies() -> void:
	## CONTROL: adding prose after each id must not disturb the instruction that
	## the id be returned exactly.
	var p: String = _prompt(["aggress", "turtle"])
	assert_true(p.find("MUST be one of the listed values") != -1,
		"the verbatim rule must survive")


func test_an_empty_intent_list_still_says_so() -> void:
	## CONTROL: the no-intents branch must not be broken by the description path.
	var p: String = _prompt([])
	assert_true(p.find("no scripted intents available") != -1,
		"a boss with no intents must still get the empty-list instruction")
