extends GutTest

## The model used target names as condition types, and lost the ruleset.
##
## The grammar lists two vocabularies of snake_case identifiers — condition types
## and target names — and the model mixed them, writing things like
## `{"type":"lowest_hp_ally","op":">=","value":0}` as a CONDITION. There is no
## such condition type, so the rule is rejected, and because one rejected rule
## discards the whole composition the player gets a canned fallback instead.
##
## It was the single largest remaining cause of a lost composition: 5 of the 12
## rejected rules across a cleric and a fighter run. Measured through the shipping
## path, same job and same intent, 12 samples each:
##
##     fighter compositions surviving   BEFORE 4/12    AFTER 9/12
##     extracted a JSON object          BEFORE 10/12   AFTER 12/12
##     target-name-as-condition errors  BEFORE 5       AFTER 0
##
## The fix is a disambiguation in the grammar naming the trap and showing the
## correct shape, the same form that took cleric compositions from 0/10 to 8/10
## when the prompt learned the character's kit.
##
## ⚠️ One model, one scenario per arm. The mechanism is what these asserts pin;
## the rates are a demonstration.

const DP := preload("res://src/llm/DialoguePrompts.gd")


func _prompt() -> String:
	return DP.build_rule_composition("autobattle", "hit the weakest enemy", [])


# ── the disambiguation is present and specific ────────────────────────────────

func test_the_grammar_says_a_target_is_not_a_condition_type() -> void:
	assert_true(_prompt().find("NEVER a\ncondition type") != -1,
		"the prompt must state the rule that was being broken")


func test_it_shows_the_correct_shape_rather_than_only_forbidding() -> void:
	## Naming a trap without showing the alternative leaves the model guessing,
	## which is how the weakest_enemy line under-performed.
	var p: String = _prompt()
	assert_true(p.find('"actions":[{"type":"attack","target":"lowest_hp_enemy"}]') != -1,
		"the prompt must show a target used correctly, in an action")
	assert_true(p.find("ally_hp_percent") != -1,
		"and name the condition type to use instead when asking about an ally")


func test_it_names_the_consequence() -> void:
	assert_true(_prompt().find("DISCARDS THE") != -1,
		"the model must be told the cost is the whole rule set, not one rule")


# ── the vocabularies it disambiguates must both still be present ──────────────

func test_the_target_list_is_still_shown() -> void:
	## CONTROL: a disambiguation that displaced the list it disambiguates would
	## trade one failure for another.
	var p: String = _prompt()
	for t in ["lowest_hp_enemy", "highest_hp_enemy", "weakest_to_ability", "self"]:
		assert_true(p.find(t) != -1, "target '%s' must still be offered" % t)


func test_the_condition_list_is_still_shown() -> void:
	var p: String = _prompt()
	for c in ["hp_percent", "ally_hp_percent", "enemy_hp_percent", "always"]:
		assert_true(p.find(c) != -1, "condition '%s' must still be offered" % c)


# ── the two vocabularies really are disjoint ──────────────────────────────────

func test_no_target_name_is_also_a_condition_type() -> void:
	## The premise. If the engine ever adds a condition type named like a target,
	## the advice above becomes false and this file must be re-read — the same
	## reason the shadowing ratchet asserts its own premise rather than assuming it.
	for t in AutobattleSystem.TARGET_TYPES.keys():
		assert_false(AutobattleSystem.CONDITION_TYPES.has(t),
			("'%s' is BOTH a target and a condition type. The grammar now tells the model a " +
			"target name is never a condition type, which would be a lie — re-read the header.") % t)


func test_the_engine_really_rejects_the_shape_the_prompt_warns_about() -> void:
	## CONTROL, against the live validator: the warning must describe a real
	## rejection, not a hazard that no longer exists.
	var errs: Array = AutobattleSystem.validate_rule(
		{"conditions": [{"type": "lowest_hp_ally", "op": ">=", "value": 0}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}, "")
	assert_gt(errs.size(), 0, "a target name used as a condition type must still be rejected")
	assert_true(", ".join(errs).find("unknown condition type") != -1,
		"and rejected for exactly the reason the prompt names")


func test_the_shape_the_prompt_recommends_is_accepted() -> void:
	## The other half: the advice must lead somewhere valid, or it trades a
	## rejection the model understands for one it does not.
	assert_eq(AutobattleSystem.validate_rule(
		{"conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}, "").size(), 0,
		"the recommended rule must validate — the prompt shows it as the correct form")
