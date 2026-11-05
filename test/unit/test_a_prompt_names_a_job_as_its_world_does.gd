extends GutTest

## cowir-story's canon ruling 21964: from World 2 on a job is called by that world's name everywhere a player reads it.
## Model-written text is read: a composed rule's name, a party member's combat line, a boss taunt. src/llm called
## get_job_display_name 0 times, so in W2 a rule could be named "Cleric heals" on a screen that says School Nurse.
## Prompts now show the world's name beside the id (the id stays: the grammar's `member` key is a job id) and say to
## use it; World 1 prompts are unchanged. Names are derived at runtime, never written here.

const DP := preload("res://src/llm/DialoguePrompts.gd")

var _saved_world: int = 1


func before_each() -> void:
	_saved_world = GameState.current_world


func after_each() -> void:
	GameState.current_world = _saved_world


## A starter job whose name in world 2 is not its id; derived so it survives any one rename.
func _renamed_in_w2() -> String:
	GameState.current_world = 2
	for id in ["fighter", "cleric", "mage", "rogue", "bard"]:
		if Combatant.job_display_name_for_id(id).to_lower().replace(" ", "_") != id:
			return id
	return ""


func test_the_composer_names_the_job_this_world_uses() -> void:
	var id: String = _renamed_in_w2()
	assert_ne(id, "", "CONTROL: world 2 renames at least one starter job")
	if id == "":
		return
	var shown: String = Combatant.job_display_name_for_id(id)
	var block: String = DP._format_rule_kit({"resolved": true, "job_id": id, "kit": ["attack"], "max_mp": 10,
		"costs": {"attack": 0}})
	assert_string_contains(block, "THIS CHARACTER is a %s \"%s\"" % [id, shown],
		"THE DEFECT: in world 2 the composer saw only '%s', so a rule could say it where he reads '%s'" % [id, shown])
	assert_string_contains(DP.SHOWN_NAME_RULE, "job", "and the shown-name rule covers jobs")


func test_a_combat_line_and_a_taunt_see_it_too() -> void:
	var id: String = _renamed_in_w2()
	if id == "":
		return
	var shown: String = Combatant.job_display_name_for_id(id)
	var party: Array = [{"name": "Kai", "job_id": id, "hp_pct": 80, "is_alive": true}]
	var line: String = DP.build_party_line("A voice.", [], {"speaker_name": "Kai", "speaker_job_id": id, "party": party})
	assert_string_contains(line, "the party's %s \"%s\"" % [id, shown], "a party member's own line knows what they are called")
	assert_string_contains(line, DP.NAME_IN_QUOTES_RULE, "and is told to say that name")
	var taunt: String = DP.build_boss_intent("Pyrroth", {"persona": "A dragon.", "party": party})
	assert_string_contains(taunt, "Kai (%s \"%s\")" % [id, shown], "a boss sizing up the party sees the same name")
	assert_string_contains(taunt, DP.NAME_IN_QUOTES_RULE, "and the same rule")


func test_world_one_prompts_are_unchanged() -> void:
	GameState.current_world = 1
	var party: Array = [{"name": "Kai", "job_id": "cleric", "hp_pct": 80, "is_alive": true}]
	var line: String = DP.build_party_line("A voice.", [], {"speaker_name": "Kai", "speaker_job_id": "cleric", "party": party})
	assert_string_contains(line, "the party's cleric, in", "world 1 keeps the bare id, as before")
	assert_false(line.contains(DP.NAME_IN_QUOTES_RULE), "and adds no rule where every name agrees")
	assert_string_contains(DP._format_rule_kit({"resolved": true, "job_id": "cleric", "kit": ["attack"], "max_mp": 10,
		"costs": {"attack": 0}}), "THIS CHARACTER is a cleric with", "the composer line is the same in world 1")
