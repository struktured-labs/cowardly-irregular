extends GutTest

## 2026-11-25 (cowir-story): world5_termination_condition step 3 sets a variant flag naming the answer the party sent
## the stack (task_complete / terminated / original), and nothing read it, so FIREWALL-ALPHA kept saying "HALT" as if
## the stack were still running. The _wiring_notes authored the original-message reply ("The Mechanism sent me a
## thank you..."). Built through the real village script; flags written through set_story_flag, as QuestSystem does.

const VILLAGE := "res://src/maps/villages/NodePrimeVillage.gd"
const WHO := "FIREWALL-ALPHA"
const BEFORE := "HALT. Access to sector twelve is restricted."
const CASES := {
	"quest_world5_termination_condition_sent_task_complete": "The stack is gone. Every frame, closed, in order. Nothing left over.",
	"quest_world5_termination_condition_sent_terminated": "Acknowledged. Awaiting next directive. That was the last thing it said.",
	"quest_world5_termination_condition_sent_original": "The Mechanism sent me a thank you. In its own notation. I didn't know it could do that.",
}

var _saved_constants: Dictionary = {}
var _saved_story: Dictionary = {}


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)
	_saved_story = GameState.story_flags.duplicate(true)
	GameState.game_constants = GameState.DEFAULT_GAME_CONSTANTS.duplicate(true)
	GameState.game_constants["dungeon_flags"] = {}
	GameState.story_flags = {}


func after_each() -> void:
	GameState.game_constants = _saved_constants
	GameState.story_flags = _saved_story


func _first_line() -> String:
	var n: Node = await _attendant()
	return _line0(n) if n != null else "<not placed>"


func _line0(n: Node) -> String:
	var lines = n.get("dialogue_lines")
	return str(lines[0]) if lines is Array and not lines.is_empty() else ""


func _attendant() -> Node:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var made = load(VILLAGE).new()
	vp.add_child(made)
	await get_tree().process_frame
	await get_tree().process_frame
	for n in (made as Node).find_children("*", "Area2D", true, false):
		if str(n.get("npc_name")) == WHO:
			return n
	return null


func test_before_an_answer_the_attendant_still_halts_you() -> void:
	assert_eq(await _first_line(), BEFORE, "CONTROL: with no answer sent, the authored HALT stands")


func test_each_answer_is_remembered_in_its_own_words() -> void:
	var quest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests/world5_termination_condition.json"))
	var authored := {}
	for o in (quest as Dictionary).get("objectives", []):
		for c in (o as Dictionary).get("choices", []):
			authored[str(c.get("sets", ""))] = true
	for flag in CASES:
		assert_true(authored.has(flag), "CONTROL: %s is a variant the quest's choices really set" % flag)
		GameState.story_flags = {}
		GameState.set_story_flag(flag)
		assert_eq(await _first_line(), CASES[flag], "after %s the attendant must speak to that answer" % flag)


## The answer is chosen mid-conversation with him (cowir-overworld 27887), so the village is already built when the flag lands:
## his very next talk must know it, not only after leaving Node Prime and coming back.
func test_the_reply_arrives_without_leaving_node_prime() -> void:
	var n: Node = await _attendant()
	assert_not_null(n, "CONTROL: FIREWALL-ALPHA is placed")
	if n == null:
		return
	assert_eq(_line0(n), BEFORE, "CONTROL: before the answer he halts you")
	GameState.set_story_flag("quest_world5_termination_condition_sent_original")
	QuestSystem.objective_advanced.emit("world5_termination_condition", 3)
	assert_eq(_line0(n), CASES["quest_world5_termination_condition_sent_original"], "the reply is there on the next talk, in the same visit")
