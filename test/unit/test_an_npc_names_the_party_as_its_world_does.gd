extends GutTest

## The NPC's party block listed each member as "Mira the cleric", the bare job id, while every other prompt in this lane
## shows the world's name beside the id (cowir-story's canon ruling 21964). In World 2 a townsperson could call the party's
## School Nurse "the cleric". The row now names the job as the world does and the block carries the rule; World 1 is unchanged.

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


func _state(job_id: String) -> Dictionary:
	return {"members": [{"name": "Mira", "job": job_id, "condition": "unhurt"}]}


func test_an_npc_sees_the_job_by_its_worlds_name() -> void:
	var id: String = _renamed_in_w2()
	assert_ne(id, "", "CONTROL: world 2 renames at least one starter job")
	if id == "":
		return
	var shown: String = Combatant.job_display_name_for_id(id)
	var block: String = DP._format_party_state(_state(id))
	assert_string_contains(block, "Mira the %s \"%s\"" % [id, shown],
		"THE DEFECT: in world 2 the NPC saw only '%s', so it could say it where he reads '%s'" % [id, shown])
	assert_string_contains(block, DP.NAME_IN_QUOTES_RULE, "and is told to say that name")


func test_the_opening_prompt_carries_it() -> void:
	var id: String = _renamed_in_w2()
	if id == "":
		return
	var p: String = DP._context_blocks([], [], "", _state(id), [])
	assert_string_contains(p, "Mira the %s \"%s\"" % [id, Combatant.job_display_name_for_id(id)],
		"the shared context block every NPC builder uses carries the name")


func test_world_one_rows_are_unchanged() -> void:
	GameState.current_world = 1
	var block: String = DP._format_party_state(_state("cleric"))
	assert_string_contains(block, "Mira the cleric, unhurt", "world 1 keeps the bare id, as before")
	assert_false(block.contains(DP.NAME_IN_QUOTES_RULE), "and adds no rule where every name agrees")
	assert_string_contains(DP._format_party_state(_state("adventurer")), "Mira the adventurer, unhurt",
		"the no-job fallback is not dressed up as a name")
