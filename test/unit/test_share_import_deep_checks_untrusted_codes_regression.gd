extends GutTest

## The STRONGEST validation ran on the MOST trusted source and not on the least trusted.
##
## _deep_check_rule catches hallucinated ability ids, abilities outside the character's kit, and
## MP-starved rules — all three fizzle-consume a turn at runtime. It is opt-in: it runs only when
## validate_rule is called WITH a character_id. Measured every call site:
##
##   RuleComposer.gd:99          passes character_id   -> LLM output IS deep-checked
##   ScriptShareManager.gd:199   does NOT               -> a stranger's clipboard is NOT
##
## and the share path had the character_id in hand — `apply_character_script(character_id, data)`
## takes it as its first parameter and then validated without it. The comment on the deep check
## reads "stricter = safer for LLM-composed output"; the reasoning was applied to our own composer
## and not to untrusted input from another player.
##
## ADVISORY, NOT REFUSAL, and that is the design point. The deep check tests against the job's
## LEVEL-1 kit. A friend whose Cleric has LEARNED cura writes a perfectly good code that would be
## hard-rejected — which would break sharing between players at different progression, i.e. the
## entire purpose of a share code. So the import applies and the player is told what will fizzle.

const SSM := preload("res://src/autobattle/ScriptShareManager.gd")


func before_each() -> void:
	SSM.last_import_errors = []
	SSM.last_import_advisories = []
	var abs_node := get_node_or_null("/root/AutobattleSystem")
	if abs_node:
		abs_node._test_disable_persistence = true


func after_each() -> void:
	SSM.last_import_errors = []
	SSM.last_import_advisories = []
	var abs_node := get_node_or_null("/root/AutobattleSystem")
	if abs_node:
		abs_node.character_profiles.erase("cleric")


func _code(ability_id: String) -> Dictionary:
	return {
		"type": "autobattle_script",
		"script": {"rules": [
			{"conditions": [{"type": "hp_percent", "op": "<", "value": 50}],
			 "actions": [{"type": "ability", "id": ability_id, "target": "lowest_hp_ally"}],
			 "enabled": true},
		]},
	}


func test_a_code_using_an_ability_outside_the_kit_still_IMPORTS() -> void:
	## The sharing property. Refusing this is what would break cross-progression codes.
	var applied: bool = SSM.apply_character_script("cleric", _code("cura"))
	assert_true(applied,
		"a code referencing an ability outside the level-1 kit must still import — the sender may legitimately have learned it, and refusing breaks the feature")


func test_but_the_player_is_TOLD_it_will_not_fire() -> void:
	SSM.apply_character_script("cleric", _code("cura"))
	var adv: String = SSM.last_import_advisory_text()
	assert_ne(adv, "",
		"an imported rule that cannot fire for THIS character must be reported, or the script silently fizzles a turn every time it matches")
	assert_true(adv.contains("rule 0"), "the advisory must name which rule: %s" % adv)
	assert_true(adv.contains("cura"), "and which ability: %s" % adv)


func test_a_hallucinated_ability_is_caught_on_an_untrusted_code() -> void:
	## The case the deep check exists for, arriving from a clipboard instead of an LLM.
	SSM.apply_character_script("cleric", _code("definitely_not_an_ability"))
	assert_true(SSM.last_import_advisory_text().contains("definitely_not_an_ability"),
		"an unknown ability id in a shared code must be reported: %s" % SSM.last_import_advisory_text())


func test_a_clean_in_kit_code_produces_NO_advisory() -> void:
	## Control. Without this, an advisory system that fires on everything would pass the tests
	## above while telling the player their good codes are broken.
	SSM.apply_character_script("cleric", _code("cure"))
	assert_eq(SSM.last_import_advisory_text(), "",
		"a code using the Cleric's own kit ability must import silently: %s" % SSM.last_import_advisory_text())


func test_advisories_do_not_leak_into_the_next_import() -> void:
	SSM.apply_character_script("cleric", _code("cura"))
	assert_ne(SSM.last_import_advisory_text(), "", "precondition: the first import set an advisory")
	SSM.apply_character_script("cleric", _code("cure"))
	assert_eq(SSM.last_import_advisory_text(), "",
		"a clean import must clear the previous advisory, or the next success is captioned with the last failure")


func test_a_refusal_is_still_a_refusal_not_an_advisory() -> void:
	## The two channels must stay distinct: grammar errors REJECT, kit mismatches ADVISE.
	var applied: bool = SSM.apply_character_script("cleric", {
		"type": "autobattle_script",
		"script": {"rules": [{"conditions": [{"type": "has_status"}],
			"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]},
	})
	assert_false(applied, "a grammar-invalid rule must still be refused outright")
	assert_ne(SSM.last_import_reason(), "", "and report a refusal reason")
	assert_eq(SSM.last_import_advisory_text(), "",
		"a refused import must not also emit advisories — nothing was applied to advise about")


func test_the_MP_GUARD_heuristic_is_NOT_surfaced_on_imports() -> void:
	## The scoping decision, pinned. `hp < 50 -> cure` is an ordinary rule with an in-kit ability
	## and no mp_percent guard, so the deep check's authoring-style arm flags it. Surfacing that on
	## every shared code would make the advisory channel worthless — the ALARM failure direction.
	## Reachability advisories say "this cannot fire for you"; style advisories say "I would have
	## written it differently", and only the first belongs on someone else's code.
	var abs_node := get_node_or_null("/root/AutobattleSystem")
	var rule := {"conditions": [{"type": "hp_percent", "op": "<", "value": 50}],
		"actions": [{"type": "ability", "id": "cure", "target": "lowest_hp_ally"}], "enabled": true}

	var full: Array = abs_node._deep_check_rule(rule, "cleric")
	var reach: Array = abs_node.deep_check_reachability(rule, "cleric")
	assert_gt(full.size(), 0,
		"control: the FULL deep check does flag this rule, or the split below proves nothing")
	assert_true("\n".join(PackedStringArray(full)).contains("mp_percent"),
		"control: and it is the MP-guard arm doing it: %s" % str(full))
	assert_eq(reach.size(), 0,
		"the reachability slice must stay silent on a rule that CAN fire: %s" % str(reach))
