extends GutTest

## The boss prompt never said the party were its ENEMIES, and the model believed it.
##
## build_boss_intent labelled the two sides "Your state:" and "Party state:".
## Nothing said which side the model commanded, so it read the party as its own
## roster. Measured against the live llama3, same scenario, 5 samples each:
##
##                          before          after
##   inverted reasoning      3/5             0/5
##   intent spread           turtle x5       aggress x4, exploit_pattern x1
##   taunts                  generic         name the player's script
##
## Inverted reasoning meant lines like "Protect Rilla and buy time for Bram to
## recover" — Rilla and Bram are the PLAYER's party, and Mordaine was planning to
## heal them. The model was never confused about the rules or the schema; every
## sample returned a valid intent_id from the allowlist both before and after. It
## was confused about WHOSE SIDE IT WAS ON, which no schema check can see.
##
## The intent spread is the part that reaches the player: against a 22%-HP cleric
## running a scripted heal rule, turtle five times out of five is the wrong read
## of the board. And the taunts went from "You may have the numbers, but I've got
## the strategy" to "You think you can heal your way out of this?" — which is the
## meta-aware pillar working, since the prompt asks for a taunt that names what
## the player automated.
##
## ⚠️ n=5 each, one model, one scenario. The effect is large and one-directional,
## but re-measure with tools/llm_prompt_preview.sh intent --ask before treating
## the numbers as a benchmark rather than a demonstration.

const DP := preload("res://src/llm/DialoguePrompts.gd")


func _prompt() -> String:
	return DP.build_boss_intent("Chancellor Mordaine", {
		"persona": "The usurper.",
		"phase": 2,
		"boss_hp_pct": 48.0, "boss_mp_pct": 70.0, "boss_ap": 2,
		"party": [{"name": "Rilla", "job_id": "cleric", "hp_pct": 22.0, "is_alive": true}],
		"available_intents": ["aggress", "turtle", "exploit_pattern"],
	})


func test_the_prompt_states_the_party_are_the_bosss_enemies() -> void:
	var p: String = _prompt()
	assert_true(p.find("YOUR ENEMIES") != -1,
		"the prompt must say whose side the model is on — without it 3 of 5 samples had the boss protecting the player's party")


func test_the_prompt_forbids_commanding_or_healing_them() -> void:
	var p: String = _prompt()
	for verb in ["command", "protect", "heal"]:
		assert_true(p.find(verb) != -1,
			"the inverted samples proposed protecting and healing the party, so the refusal must name '%s'" % verb)
	assert_true(p.find("THEM") != -1 or p.find("them") != -1,
		"and the refusal must be SCOPED to the party — an unscoped ban on protective verbs reads as a ban on defending itself, which collapsed every board to aggress")


func test_the_party_block_is_labelled_as_the_enemy_side() -> void:
	var p: String = _prompt()
	assert_true(p.find("Enemy party state:") != -1,
		"'Party state:' alone reads as the boss's own roster next to 'Your state:'")
	assert_eq(p.find("\nParty state:"), -1,
		"the ambiguous label must be gone, not merely supplemented")


func test_the_bosss_own_state_is_still_distinct() -> void:
	## CONTROL: the fix must not blur the two sides in the other direction.
	var p: String = _prompt()
	assert_true(p.find("Your state:") != -1,
		"the boss's own state must still be labelled as its own")


func test_the_party_rows_still_render() -> void:
	## CONTROL: relabelling must not break the block it labels.
	var p: String = _prompt()
	assert_true(p.find("Rilla (cleric)") != -1,
		"the party rows must still be present under the new heading")
	assert_true(p.find("22%") != -1, "and still carry the HP the boss reasons about")


func test_the_intent_allowlist_is_still_stated_verbatim() -> void:
	## CONTROL: schema-side behaviour was already correct — 5/5 valid intent_ids
	## before AND after — so the fix must not disturb it. This is what a schema
	## check CAN see, and it is why the defect survived: it was already green.
	var p: String = _prompt()
	for intent in ["aggress", "turtle", "exploit_pattern"]:
		assert_true(p.find(intent) != -1, "'%s' must still be offered verbatim" % intent)
	assert_true(p.find("MUST be one of the listed values") != -1,
		"the verbatim-only rule must survive")
