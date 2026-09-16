extends GutTest

## The composer asked for its rule list as a quoted STRING inside a JSON object, which
## makes the model nest JSON inside JSON. That is where whole compositions died: the
## reply opens `"rules_json": "[{"` and breaks on the inner quotes, so the player gets
## the canned draft instead of the strategy they asked for — the most expensive failure
## in this path, because it costs the whole set rather than one rule.
##
## `validate_rule_composition` has ALWAYS accepted both shapes ("the encoded string the
## prompt asks for, and the nested array models actually produce"), so asking for the
## array costs nothing and removes the nesting.
##
## Measured on live llama3, 3 jobs x 30 samples x 3 rounds per arm, SEQUENTIALLY —
## concurrency changes the malformed rate, so it was held fixed:
##
##   as shipped (string)   264/270 usable      6 whole compositions lost
##   array requested       270/270             0
##   Fisher exact two-tailed p = 0.030, same direction in all three rounds
##
## The tolerance is the safety half: a model that still emits a string must keep working,
## because the change is a request, not a contract.

const DP := preload("res://src/llm/DialoguePrompts.gd")


func _kit() -> Dictionary:
	return {"resolved": true, "job_id": "mage", "kit": ["fire"], "full_kit": ["fire"],
			"max_mp": 70, "costs": {"fire": 8}}


func test_the_prompt_asks_for_an_array() -> void:
	var p: String = DP.build_rule_composition("autobattle", "burn things", [], _kit())
	assert_true(p.find("as a JSON ARRAY (not a quoted string)") != -1,
		"the rule list must be requested as an array — nesting JSON in a string is where compositions are lost")
	assert_eq(p.find("the FULL rule list, as a JSON string"), -1,
		"and the old string request must be gone, not merely supplemented")


func test_both_domains_ask_the_same_way() -> void:
	## One line serves autobattle and autogrind. The autogrind path has no per-rule
	## rescue at all, so a lost composition there costs the player everything.
	var ag: String = DP.build_rule_composition("autogrind", "stop when hurt", [], {})
	assert_true(ag.find("as a JSON ARRAY (not a quoted string)") != -1,
		"the autogrind prompt must ask the same way")


func test_a_model_that_still_sends_a_string_is_accepted() -> void:
	## The safety half, and the reason this change is free. A request is not a contract.
	var as_string: Dictionary = DP.validate_rule_composition({
		"name": "n", "description": "d",
		"rules_json": "[{\"conditions\":[{\"type\":\"always\"}],\"actions\":[{\"type\":\"attack\"}],\"enabled\":true}]",
	}, "autobattle")
	assert_true(bool(as_string.get("parse_ok", false)), "an encoded string must still parse")
	assert_eq((as_string.get("rules", []) as Array).size(), 1, "and still yield its rule")


func test_an_array_is_consumed_AS_an_array() -> void:
	## MEASURED WEAK FIRST: a plain array also survives being stringified and re-parsed,
	## because Godot's str() of it happens to be valid JSON — so the obvious version of
	## this arm stayed green with the validator's array branch deleted. The rule below
	## carries an INT KEY, whose stringified form is not valid JSON, so it can only pass
	## if the array is taken directly.
	var as_array: Dictionary = DP.validate_rule_composition({
		"name": "n", "description": "d",
		"rules_json": [
			{"conditions": [{"type": "always"}], "actions": [{"type": "attack"}], "enabled": true},
			{7: "an int key — str() of this is not valid JSON"},
		],
	}, "autobattle")
	assert_true(bool(as_array.get("parse_ok", false)),
		"a real array must be used as one, not stringified and re-parsed")
	assert_eq((as_array.get("rules", []) as Array).size(), 2, "and yield what it carried")


func test_the_shape_that_was_being_lost_is_still_a_failure() -> void:
	## Anti-vacuity: the broken nesting must still be refused. If the validator had been
	## loosened to swallow it, the measurement above would be meaningless and the player
	## would get half a ruleset instead of an honest fallback.
	var broken: Dictionary = DP.validate_rule_composition({
		"name": "n", "description": "d", "rules_json": "[{",
	}, "autobattle")
	assert_false(bool(broken.get("parse_ok", true)),
		"a truncated nested string must still fail — the fix is to stop asking for it, not to accept rubble")


func test_the_rest_of_the_output_spec_is_intact() -> void:
	var p: String = DP.build_rule_composition("autobattle", "burn things", [], _kit())
	for required in ["name: short (3-6 words)", "description: 1 sentence",
			"conditions and actions must use only the verbs listed above",
			"There is no 'weakest_enemy'"]:
		assert_true(p.find(required) != -1, "the output spec must still carry: %s" % required)
