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

func test_intent_descriptions_only_describe_what_the_engine_does() -> void:
	## THE LOAD-BEARING ONE. Five of the six widened counter tags reach no bias arm
	## that produces an action — pinned inverted in BattleManager, awaiting
	## struktured's call on whether to wake them. Describing one as though it works
	## would make the prompt lie about the boss's behaviour. This fails if anyone
	## adds a description for an intent outside the working set.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_false(src.is_empty(), "CONTROL: BattleManager must be readable")
	for id in DP.INTENT_DESCRIPTIONS.keys():
		assert_true(src.find('"%s":' % str(id)) != -1,
			("'%s' is described to the model but has no dedicated arm in _bias_by_intent. " +
			"Either it does nothing, or the description is guessing at what it does.") % str(id))


func test_the_inert_counter_tags_are_left_undescribed() -> void:
	## The other half, stated so a later "let's document them all" edit has to
	## confront the reason. These render bare and keep their entry in the widened
	## vocabulary; they are simply not explained as working postures.
	for id in ["fire_resist", "ice_resist", "lightning_resist", "focus_healer", "defense_boost"]:
		assert_false(DP.INTENT_DESCRIPTIONS.has(id),
			"'%s' reaches no action-producing arm — it must not be described as a working posture" % id)


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
