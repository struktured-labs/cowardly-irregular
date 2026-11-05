extends GutTest

## A pasted share code whose rule uses an ability the character has not learned flashed "Applied, but rule 0: ability
## 'cure' not in cleric's level-1 kit — the rule is SKIPPED until learned, so a level-1 character never reaches it (a
## dead rule, NOT a fizzle)": raw ability and job ids, a rule counted from 0, and the Rule Composer's lint wording.
## The menu says Sanatio, and in W2 School Nurse. The share layer now renders that finding for the player; the lint
## text is left as written (it is the composer's MODEL-facing repair hint, cowir-ai 22004).

const SSM := preload("res://src/autobattle/ScriptShareManager.gd")
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

var _saved_world := 1
var _saved_persist := false
var _ab_profiles_entry: Dictionary = {}


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(get_tree().root.get_node_or_null("AutobattleSystem"))


func after_all() -> void:
	ABProfiles.restore(get_tree().root.get_node_or_null("AutobattleSystem"), _ab_profiles_entry)


func before_each() -> void:
	_saved_world = GameState.current_world
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	SSM.last_import_errors = []
	SSM.last_import_advisories = []


func after_each() -> void:
	GameState.current_world = _saved_world
	AutobattleSystem._test_disable_persistence = _saved_persist
	SSM.last_import_errors = []
	SSM.last_import_advisories = []


func _code(ability_id: String) -> Dictionary:
	return {"type": "autobattle_script", "script": {"rules": [
		{"conditions": [{"type": "hp_percent", "op": "<", "value": 50}],
		 "actions": [{"type": "ability", "id": ability_id, "target": "lowest_hp_ally"}], "enabled": true},
	]}}


## A cleric ability she can learn later (in the full kit, not the level-1 kit) whose menu name is not its id in words.
func _unlearned_renamed() -> String:
	var ctx: Dictionary = AutobattleSystem.get_deep_check_kit("cleric")
	assert_true(bool(ctx.get("resolved", false)), "PRECONDITION: the cleric's kit must resolve")
	for aid in ctx["full_kit"]:
		var id := str(aid)
		if id in ctx["kit"]:
			continue
		if AbilityIcons.name_of(id).to_lower() != id.capitalize().to_lower():
			return id
	assert_true(false, "PRECONDITION: the cleric must have a renamed ability learned after level 1")
	return ""


func test_an_unlearned_ability_is_named_as_the_menu_and_the_world_name_them() -> void:
	var aid := _unlearned_renamed()
	GameState.current_world = 2
	var job_w2 := Combatant.job_display_name_for_id("cleric")
	assert_ne(job_w2.to_lower(), "cleric", "CONTROL: in W2 the cleric is named differently, or this arm proves nothing")
	assert_true(SSM.apply_character_script("cleric", _code(aid)), "PRECONDITION: the code imports (an unlearned ability is advice, not a refusal)")
	var adv: String = SSM.last_import_advisory_text()
	assert_string_contains(adv, "Rule 1", "rules are counted as a player counts them")
	assert_string_contains(adv, AbilityIcons.name_of(aid), "the ability reads as the menu names it")
	assert_string_contains(adv, job_w2, "and the job as THIS world names it")
	assert_false(adv.contains("'%s'" % aid), "never the quoted id: %s" % adv)
	assert_false(adv.contains("level-1 kit") or adv.contains("fizzle"), "and none of the lint's vocabulary: %s" % adv)


## The lint itself is the composer's model-facing hint and must keep its wording (its tests pin the substring).
func test_the_composer_lint_keeps_its_wording() -> void:
	var aid := _unlearned_renamed()
	var errs: Array = AutobattleSystem.deep_check_reachability(_code(aid)["script"]["rules"][0], "cleric")
	assert_true(", ".join(errs).contains("not in cleric's level-1 kit"), "the lint text is unchanged: %s" % [errs])


## A finding the share layer does not recognise passes through, numbered, rather than being dropped.
func test_an_unknown_ability_still_reports_its_id() -> void:
	assert_true(SSM.apply_character_script("cleric", _code("definitely_not_an_ability")), "PRECONDITION: it imports")
	var adv: String = SSM.last_import_advisory_text()
	assert_string_contains(adv, "Rule 1", "numbered as a player counts")
	assert_string_contains(adv, "definitely_not_an_ability", "an id nothing names is all there is to show")
