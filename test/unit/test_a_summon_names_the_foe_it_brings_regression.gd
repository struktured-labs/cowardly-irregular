extends GutTest

## 2026-11-05, the name-from-data class (ai 21928 → story 21953): the summon line built its name from the TYPE id,
## so a summoned `snake` would be announced as "a Snake" while its own panel read "Swamp Viper" (44 monsters have a
## data name that isn't their id in words). Today's summons happen to match; this keeps the next one honest.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")


func _summon_message(monster_type: String) -> String:
	var bm = BattleManagerScript.new()
	add_child_autofree(bm)
	var caster = Combatant.new()
	caster.combatant_name = "Goblin"
	autofree(caster)
	var messages: Array = []
	bm.battle_log_message.connect(func(msg): messages.append(msg))
	bm._execute_summon(caster, monster_type)
	return "".join(messages)


func test_a_summoned_foe_is_named_as_its_panel_names_it() -> void:
	var data: Dictionary = EncounterSystem.monster_database.get("snake", {})
	assert_eq(str(data.get("name", "")), "Swamp Viper", "CONTROL: the snake's data name is not its id in words")
	var msg := _summon_message("snake")
	assert_string_contains(msg, "summons a Swamp Viper!", "the summon names the foe from its data")
	assert_false("Snake!" in msg, "never the id in words")


func test_a_the_name_takes_no_article() -> void:
	var name := str(EncounterSystem.monster_database.get("cartographer_wraith", {}).get("name", ""))
	assert_true(name.begins_with("The "), "CONTROL: a monster whose name starts with The (%s)" % name)
	var msg := _summon_message("cartographer_wraith")
	assert_string_contains(msg, "summons %s!" % name, "no article in front of a The-name")
	assert_false(("a " + name) in msg, "never 'a The …'")


func test_a_type_with_no_data_still_reads() -> void:
	assert_string_contains(_summon_message("zz_no_such_beast"), "summons a Zz No Such Beast!", "the id in words, only when there's no data")
