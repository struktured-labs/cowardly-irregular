extends GutTest

## The composer's prompt never knew which character it was composing for.
##
## compose_async has character_id; build_rule_composition never received it. So
## the grammar said "Ability ids must belong to THIS character's level-1 kit"
## without naming the character or listing the kit, and demanded an mp_percent
## guard "covering the SUMMED MP cost" while stating neither ability costs nor the
## MP pool. Both rules were unfollowable in principle. Then _deep_check_rule
## validated against exactly that kit, and ONE bad rule discards the WHOLE ruleset
## — the player gets the canned fallback.
##
## Measured through the shipping path against local llama3, n=10 per arm, same
## intent and job within each pair:
##
##     cleric, healing intent      BEFORE 0/10    AFTER 8/10
##     fighter, fighter intent     BEFORE 0/10    AFTER 5/10
##
## Baseline losses were guessed ability ids (`cure` on a fighter ×10, an `esuna`
## no job has at level 1, a `heal` that exists nowhere) and missing MP guards
## (20 of 29 rejected rules). Note this was invisible until 2026-09-10: the JSON
## contract bugs meant nothing reached the deep check at all, so the prompt's
## blindness cost nothing measurable. Repairing the pipeline is what exposed it.
##
## Two changes, both sourced from the validator's own kit view so prompt and
## validator cannot drift:
##   1. get_deep_check_kit() feeds the prompt the real ids, costs and pool.
##   2. the mp_percent guard is DERIVED and supplied — it is arithmetic, not a
##      judgement, and the model omitted it even when handed the numbers.

const DP := preload("res://src/llm/DialoguePrompts.gd")

var _rc = null


func before_each() -> void:
	_rc = get_tree().root.get_node_or_null("RuleComposer")
	assert_not_null(_rc, "CONTROL: RuleComposer autoload must be present")


func _kit(character_id: String) -> Dictionary:
	return AutobattleSystem.get_deep_check_kit(character_id)


func _cure_rule_without_a_guard() -> Dictionary:
	return {"conditions": [{"type": "ally_hp_percent", "op": "<", "value": 40}],
			"actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}],
			"enabled": true}


# ── the kit resolver is the validator's own view ──────────────────────────────

func test_the_kit_resolver_returns_the_real_level_one_kit() -> void:
	var kit: Dictionary = _kit("cleric")
	assert_true(bool(kit["resolved"]), "a real job must resolve")
	assert_eq(str(kit["job_id"]), "cleric", "character id must resolve to its job")
	assert_true((kit["kit"] as Array).has("cure"), "the cleric's kit must contain cure")
	assert_gt(int(kit["max_mp"]), 0, "the MP pool must be a real number, not a default")
	assert_gt(int((kit["costs"] as Dictionary).get("cure", 0)), 0,
		"costs must be populated — the prompt cannot compute a guard without them")


func test_an_unresolvable_character_reports_unresolved_rather_than_guessing() -> void:
	var kit: Dictionary = _kit("__nobody__")
	assert_false(bool(kit["resolved"]),
		"an unknown character must report unresolved, not an empty kit that reads as 'no abilities'")


func test_the_deep_check_still_rejects_what_it_always_did() -> void:
	## CONTROL for the refactor: _deep_check_rule now reads get_deep_check_kit
	## instead of deriving the kit inline. Behaviour must be identical.
	var errs: Array = AutobattleSystem.validate_rule(
		{"conditions": [{"type": "always"}],
		 "actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}],
		 "enabled": true}, "fighter")
	assert_gt(errs.size(), 0, "cure on a fighter must still be rejected")
	assert_true(", ".join(errs).find("not in fighter's level-1 kit") != -1,
		"and for the same reason as before the refactor")


# ── the prompt carries the real numbers ───────────────────────────────────────

func test_the_prompt_names_the_job_and_lists_the_kit() -> void:
	var p: String = DP.build_rule_composition("autobattle", "heal people", [], _kit("cleric"))
	assert_true(p.find("THIS CHARACTER is a cleric") != -1, "the prompt must name the job")
	assert_true(p.find("cure") != -1, "and list the abilities it may actually use")


func test_the_prompts_worked_example_matches_what_the_validator_demands() -> void:
	## THE CRUX. The prompt's example threshold and the validator's required
	## threshold are computed in two places; if they ever disagree, the prompt
	## teaches a number that gets the whole ruleset discarded. This derives the
	## validator's demand from its own error text rather than restating it.
	var kit: Dictionary = _kit("cleric")
	var errs: Array = AutobattleSystem.validate_rule(_cure_rule_without_a_guard(), "cleric")
	var demanded: String = ", ".join(errs)
	assert_true(demanded.find("mp_percent >=") != -1,
		"CONTROL: an unguarded cure must be rejected, or this test proves nothing")
	var need: String = demanded.substr(demanded.find("mp_percent >=") + 13).strip_edges()
	need = need.split(" ")[0].split(",")[0]
	var p: String = DP.build_rule_composition("autobattle", "heal people", [], kit)
	assert_true(p.find('"value":%s}' % need) != -1,
		"the prompt's worked example must state the SAME threshold the validator requires (%s)" % need)


func test_no_kit_context_leaves_the_block_out() -> void:
	## CONTROL: the autogrind path and any unresolved character must not render a
	## half-empty block claiming the character has no abilities.
	var bare: String = DP.build_rule_composition("autobattle", "do things", [])
	assert_eq(bare.find("THIS CHARACTER is"), -1, "no kit context must render no block")
	var unresolved: String = DP.build_rule_composition("autobattle", "do things", [], _kit("__nobody__"))
	assert_eq(unresolved.find("THIS CHARACTER is"), -1, "an unresolved character must render no block")


func test_the_autogrind_prompt_never_gets_a_character_kit() -> void:
	## Autogrind is party-level and has no PC, so a kit block there would be a lie.
	var p: String = DP.build_rule_composition("autogrind", "grind efficiently", [], _kit("cleric"))
	assert_eq(p.find("THIS CHARACTER is"), -1, "the autogrind domain must not claim a character")


func test_the_grammar_still_ships_with_the_kit_block() -> void:
	## CONTROL: adding a block must not displace the grammar it supplements.
	var p: String = DP.build_rule_composition("autobattle", "heal people", [], _kit("cleric"))
	assert_true(p.find("first match wins") != -1, "the grammar must still be present")
	assert_true(p.find("Player intent:") != -1, "and so must the player's request")


# ── the derived guard ─────────────────────────────────────────────────────────

func test_a_supplied_guard_makes_the_validator_accept_the_rule() -> void:
	## The whole point, stated against the REAL validator rather than a restated
	## threshold: a rule it rejected must pass once the guard is supplied.
	var rules: Array = [_cure_rule_without_a_guard()]
	assert_gt(AutobattleSystem.validate_rule(rules[0], "cleric").size(), 0,
		"CONTROL: unguarded, this rule must be rejected")
	_rc._supply_missing_mp_guards(rules, _kit("cleric"))
	assert_eq(AutobattleSystem.validate_rule(rules[0], "cleric").size(), 0,
		"after supplying the derived guard the validator must accept it")


func test_the_guard_never_loosens_one_the_model_did_emit() -> void:
	var rules: Array = [_cure_rule_without_a_guard()]
	(rules[0]["conditions"] as Array).append({"type": "mp_percent", "op": ">=", "value": 90})
	_rc._supply_missing_mp_guards(rules, _kit("cleric"))
	var found: int = -1
	for c in rules[0]["conditions"]:
		if str(c.get("type", "")) == "mp_percent":
			found = int(c["value"])
	assert_eq(found, 90, "a stricter guard the model chose must be left alone, not lowered")


func test_a_guard_that_is_too_weak_is_raised() -> void:
	var rules: Array = [_cure_rule_without_a_guard()]
	(rules[0]["conditions"] as Array).append({"type": "mp_percent", "op": ">=", "value": 1})
	_rc._supply_missing_mp_guards(rules, _kit("cleric"))
	assert_eq(AutobattleSystem.validate_rule(rules[0], "cleric").size(), 0,
		"an insufficient guard must be raised to what the validator requires, not duplicated")
	var count: int = 0
	for c in rules[0]["conditions"]:
		if str(c.get("type", "")) == "mp_percent":
			count += 1
	assert_eq(count, 1, "and must not leave two mp_percent conditions fighting each other")


func test_a_free_action_rule_gets_no_guard() -> void:
	## CONTROL: 0-cost abilities need no guard, and adding one would stop the rule
	## firing at low MP for no reason.
	var rules: Array = [{"conditions": [{"type": "always"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]
	_rc._supply_missing_mp_guards(rules, _kit("cleric"))
	assert_eq((rules[0]["conditions"] as Array).size(), 1,
		"a rule with no MP cost must be left exactly as authored")


func test_an_out_of_kit_rule_is_left_for_the_validator_to_reject() -> void:
	## The repair must not paper over a hallucinated ability by attaching a
	## plausible guard to it — that would turn a visible rejection into a rule
	## that looks authored and still cannot run.
	var rules: Array = [_cure_rule_without_a_guard()]
	_rc._supply_missing_mp_guards(rules, _kit("fighter"))
	assert_eq((rules[0]["conditions"] as Array).size(), 1,
		"cure on a fighter must be untouched — that is the model's error, not arithmetic")
	assert_gt(AutobattleSystem.validate_rule(rules[0], "fighter").size(), 0,
		"and it must still be rejected")


func test_an_unresolved_kit_repairs_nothing() -> void:
	var rules: Array = [_cure_rule_without_a_guard()]
	_rc._supply_missing_mp_guards(rules, _kit("__nobody__"))
	assert_eq((rules[0]["conditions"] as Array).size(), 1,
		"with no pool to divide by, the repair must do nothing rather than invent a threshold")


func test_the_repair_survives_malformed_rules() -> void:
	## LLM output reaches this before the grammar pass, so it can be any shape.
	var rules: Array = ["not a rule", {"conditions": "not an array", "actions": []}, {}]
	_rc._supply_missing_mp_guards(rules, _kit("cleric"))
	assert_eq(rules.size(), 3, "malformed entries must not crash the repair or be dropped here")
