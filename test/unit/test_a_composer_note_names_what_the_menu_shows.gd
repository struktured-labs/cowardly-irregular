extends GutTest

## The Rule Composer's repair notes reach the player under "what it changed", and they named abilities, items and
## job-id members by their IDS: "Aimed 'cure' at …", "Read item 'HIPOTION' as 'hi_potion'", "Dropped 'fire' for cleric"
## while the menus say Sanatio / Potio Maior / this world's job (cowir-ai 22000, after cowir-autogrind 21998).
## Every name here is derived from the data at runtime, so a rename or the per-world table moves with it.

const RC := preload("res://src/llm/RuleComposer.gd")

var _saved_world: int = 1


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_saved_world = GameState.current_world


func after_each() -> void:
	GameState.current_world = _saved_world


func _rc():
	var c = RC.new()
	add_child_autofree(c)
	return c


func _renamed(aid: String) -> bool:
	return AbilityIcons.name_of(aid).to_lower().replace(" ", "_") != aid


## A renamed ability matching `want`, from the live ability table.
func _find_ability(want: Callable) -> String:
	for aid in JobSystem.abilities:
		if _renamed(str(aid)) and want.call(str(aid)):
			return str(aid)
	return ""


func test_an_aimed_heal_is_named_as_the_menu_does() -> void:
	var aid: String = _find_ability(func(a): return str(JobSystem.get_ability(a).get("target_type", "")) == "single_ally")
	assert_ne(aid, "", "CONTROL: a renamed single-ally ability exists")
	if aid == "":
		return
	var rules: Array = [{"conditions": [{"type": "always"}], "actions": [{"type": "ability", "id": aid}], "enabled": true}]
	var notes: Array = _rc()._aim_untargeted_abilities(rules)
	assert_eq(notes.size(), 1, "FIXTURE: the untargeted heal was aimed")
	assert_string_contains("|".join(notes), "Aimed '%s'" % AbilityIcons.name_of(aid), "THE DEFECT: the note named the id")
	assert_false("|".join(notes).contains("'%s'" % aid), "and never the bare id")


func test_an_mp_guard_note_names_the_rule_by_its_ability() -> void:
	var aid: String = _find_ability(func(a): return int(JobSystem.get_ability(a).get("mp_cost", 0)) > 0)
	assert_ne(aid, "", "CONTROL: a renamed ability with an MP cost exists")
	if aid == "":
		return
	var rules: Array = [{"conditions": [{"type": "always"}], "actions": [{"type": "ability", "id": aid}], "enabled": true}]
	var notes: Array = _rc()._supply_missing_mp_guards(rules, {"kit": [aid], "costs": {aid: 10}, "max_mp": 40})
	assert_eq(notes.size(), 1, "FIXTURE: a guard was added")
	assert_string_contains("|".join(notes), "('%s')" % AbilityIcons.name_of(aid), "the rule is named as the menu names it")


func test_a_respelled_item_is_named_as_the_menu_does() -> void:
	var iid: String = ""
	for id in ItemSystem.items:
		var shown: String = ItemNameResolver.resolve(str(id))
		if shown.to_lower().replace(" ", "_").replace("-", "_") != str(id):
			iid = str(id)
			break
	assert_ne(iid, "", "CONTROL: an item whose menu name its id does not spell exists")
	if iid == "":
		return
	var raw: String = iid.to_upper().replace("_", " ")
	var rules: Array = [{"conditions": [{"type": "always"}], "actions": [{"type": "item", "id": raw}], "enabled": true}]
	var notes: Array = _rc()._normalise_item_ids(rules, [iid])
	assert_eq(notes, ["Read item '%s' as %s." % [raw, ItemNameResolver.resolve(iid)]],
		"the model's spelling stays quoted, and what it became is the menu's name")


func test_a_dropped_member_ability_names_the_ability_and_the_job_this_world_uses() -> void:
	GameState.current_world = 2
	var grind: Node = get_tree().root.get_node("AutogrindSystem")
	var aid: String = _find_ability(func(a): return not grind.ability_works_between_battles(a))
	assert_ne(aid, "", "CONTROL: a renamed battle-only ability exists")
	var job: String = ""
	for j in ["fighter", "cleric", "mage", "rogue", "bard"]:
		if Combatant.job_display_name_for_id(j).to_lower().replace(" ", "_") != j:
			job = j
			break
	assert_ne(job, "", "CONTROL: world 2 renames a starter job")
	if aid == "" or job == "":
		return
	var rules: Array = [{"conditions": [{"type": "always"}],
		"actions": [{"type": "member_ability", "member": job, "ability": aid}, {"type": "heal_party"}], "enabled": true}]
	var notes: Array = _rc()._drop_unrunnable_member_abilities(rules, grind)
	var blob: String = "|".join(notes)
	assert_string_contains(blob, "Dropped '%s' for %s" % [AbilityIcons.name_of(aid), Combatant.job_display_name_for_id(job)],
		"the note names the ability and the member as the player's screens do")
