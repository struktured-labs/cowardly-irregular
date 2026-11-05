extends GutTest

## The boss-intent and party-line prompts listed the recent exchange as "Mira used cure", so the model, which writes the
## taunt and the line the player reads, saw only the id and could say it back where the menu says Sanatio. Each recent
## action now shows the menu name beside its id, and the prompt says to use it. Names derive from the data at runtime.

const DP := preload("res://src/llm/DialoguePrompts.gd")

var _saved_world: int = 1


func before_each() -> void:
	_saved_world = GameState.current_world
	GameState.current_world = 1


func after_each() -> void:
	GameState.current_world = _saved_world


func _find(renamed: bool) -> String:
	for aid in JobSystem.abilities:
		var shown: String = str(JobSystem.get_ability(str(aid)).get("name", ""))
		if shown != "" and (shown.to_lower().replace(" ", "_") != str(aid)) == renamed:
			return str(aid)
	return ""


func _recent(aid: String) -> Array:
	return [{"kind": "party", "actor": "Mira", "ability_id": aid, "target": "Pyrroth", "damage": 12}]


func test_a_boss_sees_the_ability_by_its_menu_name() -> void:
	var aid: String = _find(true)
	assert_ne(aid, "", "CONTROL: an ability whose menu name its id does not spell exists")
	if aid == "":
		return
	var p: String = DP.build_boss_intent("Pyrroth", {"persona": "A dragon.", "recent_actions": _recent(aid)})
	assert_string_contains(p, "Mira used %s \"%s\"" % [aid, JobSystem.get_ability(aid).get("name", "")],
		"THE DEFECT: the boss saw only '%s'" % aid)
	assert_string_contains(p, DP.NAME_IN_QUOTES_RULE, "and is told to say the name")


func test_a_party_line_sees_it_too() -> void:
	var aid: String = _find(true)
	if aid == "":
		return
	var p: String = DP.build_party_line("A voice.", [], {"speaker_name": "Kai", "speaker_job_id": "fighter", "recent_actions": _recent(aid)})
	assert_string_contains(p, "Mira used %s \"%s\"" % [aid, JobSystem.get_ability(aid).get("name", "")], "the party line sees the name")
	assert_string_contains(p, DP.NAME_IN_QUOTES_RULE, "and the rule")


func test_an_ability_named_as_its_id_adds_nothing() -> void:
	var aid: String = _find(false)
	assert_ne(aid, "", "CONTROL: an ability whose menu name is its id exists")
	if aid == "":
		return
	var p: String = DP.build_party_line("A voice.", [], {"speaker_name": "Kai", "speaker_job_id": "fighter", "recent_actions": _recent(aid)})
	assert_string_contains(p, "Mira used %s (12 dmg)" % aid, "a name that only spells its id is not repeated")
	assert_false(p.contains(DP.NAME_IN_QUOTES_RULE), "and no rule is added in world 1 when every name agrees")
