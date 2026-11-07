extends GutTest

## Same class as the summon line (.773): Permakill's species line built the name from the TYPE id, so unwriting the
## Lost Cartographer read "The Cartographer Wraith species", and a The-name would double its article. Named from data now.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _saved_unwritten: Array = []


func before_each() -> void:
	_saved_unwritten = GameState.permakilled_monster_types.duplicate()


func after_each() -> void:
	GameState.permakilled_monster_types.clear()
	for t in _saved_unwritten:
		GameState.permakilled_monster_types.append(t)


func _unwrite(monster_type: String) -> String:
	var bm = BattleManagerScript.new()
	add_child_autofree(bm)
	var caster := Combatant.new()
	caster.combatant_name = "Necromancer"
	add_child_autofree(caster)
	var target := Combatant.new()
	target.combatant_name = "Victim"
	target.max_hp = 10
	add_child_autofree(target)
	target.current_hp = 10
	target.is_alive = true
	target.set_meta("monster_type", monster_type)
	GameState.permakilled_monster_types.erase(monster_type)
	var messages: Array = []
	bm.battle_log_message.connect(func(msg): messages.append(str(msg)))
	bm._execute_meta_ability(caster, {"meta_effect": "permanent_death"}, [target])
	var species: Array = messages.filter(func(m): return "UNWRITTEN" in m)
	assert_eq(species.size(), 1, "CONTROL: the permakill branch unwrote %s exactly once (%s)" % [monster_type, str(messages)])
	return species[0] if species.size() == 1 else ""


func test_a_species_is_named_as_its_panel_names_it() -> void:
	var data: Dictionary = EncounterSystem.monster_database.get("snake", {})
	assert_eq(str(data.get("name", "")), "Swamp Viper", "CONTROL: the snake's data name is not its id in words")
	var line := _unwrite("snake")
	assert_string_contains(line, "The Swamp Viper species has been UNWRITTEN", "the species line names the foe from its data")
	assert_false("Snake species" in line, "never the id in words")


func test_a_the_name_takes_no_second_article() -> void:
	var name := str(EncounterSystem.monster_database.get("cartographer_wraith", {}).get("name", ""))
	assert_true(name.begins_with("The "), "CONTROL: a monster whose name starts with The (%s)" % name)
	var line := _unwrite("cartographer_wraith")
	assert_string_contains(line, "]%s species has been UNWRITTEN" % name, "the The-name opens the line on its own")
	assert_false("The The" in line, "never 'The The …'")
