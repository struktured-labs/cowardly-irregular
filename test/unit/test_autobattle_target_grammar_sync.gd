extends GutTest

## Guard 2026-07-04: the LLM Rule Composer is told the valid target values via a
## hardcoded list in DialoguePrompts.AUTOBATTLE_GRAMMAR_DESCRIPTION. That list
## must stay in sync with AutobattleSystem.TARGET_TYPES — otherwise a target the
## engine supports (like the new 'weakest_to_ability' / Exploit Weakness) is
## invisible to the LLM, or a target the LLM emits gets fizzle-rejected. This
## test pins the sync so the next person who adds a target updates both places.

const PROMPTS := preload("res://src/llm/DialoguePrompts.gd")


func test_every_engine_target_is_documented_to_the_llm() -> void:
	var grammar: String = PROMPTS.AUTOBATTLE_GRAMMAR_DESCRIPTION
	for key in AutobattleSystem.TARGET_TYPES.keys():
		assert_string_contains(grammar, str(key),
			"target '%s' is a valid engine target but the LLM grammar never mentions it" % key)


func test_every_engine_condition_is_documented_to_the_llm() -> void:
	# Same drift guard as targets, for condition types: a condition the engine
	# evaluates (like the new enemy_has_status) must appear in the LLM grammar or
	# the Rule Composer can never emit it.
	var grammar: String = PROMPTS.AUTOBATTLE_GRAMMAR_DESCRIPTION
	for key in AutobattleSystem.CONDITION_TYPES.keys():
		assert_string_contains(grammar, str(key),
			"condition '%s' is a valid engine condition but the LLM grammar never mentions it" % key)


func test_exploit_weakness_is_registered_and_documented() -> void:
	assert_true(AutobattleSystem.TARGET_TYPES.has("weakest_to_ability"),
		"engine must register the Exploit Weakness target")
	assert_string_contains(PROMPTS.AUTOBATTLE_GRAMMAR_DESCRIPTION, "weakest_to_ability",
		"the LLM must be told Exploit Weakness exists so it can compose weakness-exploiting rules")


func test_validator_accepts_the_new_target() -> void:
	# A plain attack aimed at weakest_to_ability must not trip the unknown-target
	# check (attack has no MP cost, so no fizzle guard is needed either).
	var rule := {
		"conditions": [{"type": "always"}],
		"actions": [{"type": "attack", "target": "weakest_to_ability"}],
		"enabled": true,
	}
	var errors: Array = AutobattleSystem.validate_rule(rule)
	var target_error := ""
	for e in errors:
		if "target" in str(e).to_lower():
			target_error = str(e)
	assert_eq(target_error, "",
		"validator wrongly flagged the registered weakest_to_ability target: %s" % target_error)
