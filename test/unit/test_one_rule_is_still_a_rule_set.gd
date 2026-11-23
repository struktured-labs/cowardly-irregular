extends GutTest

## On the engine path (llama3, .813 and .814's tip, 2 of 2 each) the Rule Composer's model answered with ONE rule as a
## bare object, {"conditions": [...], "actions": [...]}, where a list of rules was expected. The validator read only a
## list or an encoded list, so the player's request came back as "the reply could not be read".

const DP := preload("res://src/llm/DialoguePrompts.gd")
const ONE_RULE := {"conditions": [{"type": "ally_hp_percent", "op": "<=", "value": 50}], "actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}], "enabled": true}


func _read(rules_json: Variant) -> Dictionary:
	return DP.validate_rule_composition({"name": "n", "description": "d", "rules_json": rules_json}, "autobattle")


func test_one_rule_as_a_bare_object_is_a_rule_set_of_one() -> void:
	var v: Dictionary = _read(ONE_RULE)
	assert_true(bool(v["parse_ok"]), "the shape the model sent must be readable")
	assert_eq((v["rules"] as Array).size(), 1, "as one rule")
	var rule: Dictionary = (v["rules"] as Array)[0] if not (v["rules"] as Array).is_empty() else {}
	assert_eq(str((rule.get("actions", [{}]) as Array)[0].get("id", "")), "cure", "and it is the rule that was written, not an empty one")


func test_the_same_rule_as_an_encoded_object_reads_too() -> void:
	var v: Dictionary = _read(JSON.stringify(ONE_RULE))
	assert_true(bool(v["parse_ok"]), "an encoded single rule is the same answer in the other spelling")
	assert_eq((v["rules"] as Array).size(), 1)


func test_control_an_object_that_is_not_a_rule_is_still_unreadable() -> void:
	for not_a_rule in [{"note": "I could not decide"}, {}, {"actions": "attack"}, {"conditions": []}, "nonsense", 7, null]:
		var v: Dictionary = _read(not_a_rule)
		assert_false(bool(v["parse_ok"]), "CONTROL: %s is not a rule set" % str(not_a_rule))
		assert_eq((v["rules"] as Array).size(), 0)


func test_control_a_list_of_rules_reads_as_before() -> void:
	var two: Array = [ONE_RULE, ONE_RULE]
	assert_eq((_read(two)["rules"] as Array).size(), 2, "CONTROL: the list shape")
	assert_eq((_read(JSON.stringify(two))["rules"] as Array).size(), 2, "CONTROL: the encoded list shape")
	assert_true(bool(_read([])["parse_ok"]), "CONTROL: an empty list is a readable reply with no rules")
