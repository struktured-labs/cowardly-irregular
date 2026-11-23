extends GutTest

## autogrind 95c14b349: member_hp / member_mp now read only LIVING members. The grind composer's grammar must say so,
## or the model writes "member_hp < 1 -> stop_grinding" as a death stop and it never fires.
## Each arm reads the evaluator and the prompt together, so the two cannot drift apart silently.

const DP := preload("res://src/llm/DialoguePrompts.gd")

var _system
var _party: Array[Combatant] = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	_party.clear()
	for job in ["cleric", "fighter"]:
		var c := Combatant.new()
		c.initialize({"name": job.capitalize(), "max_hp": 100, "max_mp": 40, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
		c.job = {"id": job}
		add_child_autofree(c)
		_party.append(c)


func test_the_prompt_says_what_the_evaluator_does_with_the_dead() -> void:
	var g: String = DP.AUTOGRIND_GRAMMAR_DESCRIPTION
	_party[0].current_hp = 0
	_party[0].current_mp = 0
	_party[0].is_alive = false
	assert_true(_system._evaluate_party_condition(_party, {"type": "member_dead"}), "CONTROL: the cleric is dead")
	var hp_low: bool = _system._evaluate_party_condition(_party, {"type": "member_hp", "op": "<", "value": 30})
	var mp_low: bool = _system._evaluate_party_condition(_party, {"type": "member_mp", "op": "<", "value": 30})
	assert_false(hp_low or mp_low, "CONTROL: the evaluator does not read a corpse as low HP or MP")
	assert_string_contains(g, "member_hp and member_mp read only LIVING members",
		"the composer is told low HP/MP skips the fallen, matching the evaluator")
	assert_string_contains(g, "a fallen member is member_dead",
		"and is pointed at member_dead for a death")
