extends GutTest

## NPC prompts listed the party with no pronouns, so llama3 guessed; 4 of 23 replies about a hurt Rogue said "she", and the Rogue is never gendered.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]
const PRONOUNS := ["he/him", "she/her", "(he)", "(she)"]


## name -> job, so a character can hold a job that is not the one they started in.
func _party(held: Dictionary) -> Dictionary:
	var members: Array = []
	for n in held:
		members.append({"name": n, "job": held[n], "condition": "badly hurt (20% health)"})
	return {"members": members}


func _rows(block: String) -> Array:
	var out: Array = []
	for line in block.split("\n"):
		if line.begins_with("  - "):
			out.append(line)
	return out


func test_a_listed_party_carries_the_rule() -> void:
	var block: String = DP._format_party_state(_party({"Rogue": "rogue", "Cleric": "cleric"}))
	assert_eq(_rows(block).size(), 2, "CONTROL: both members must be listed")
	assert_true(block.contains("never call a party member he or she"),
		"the model must be told not to gender the party, or it guesses. Block: %s" % block)


func test_the_rule_does_not_depend_on_who_holds_which_job() -> void:
	## The review case: a pronoun keyed on the current job would call the Rogue "she" in the Bard job.
	var block: String = DP._format_party_state(_party({"Rogue": "bard", "Cleric": "fighter", "Bard": "rogue"}))
	assert_eq(_rows(block).size(), 3, "CONTROL: all three reassigned members must be listed")
	var gendered: Array = []
	for row in _rows(block):
		for p in PRONOUNS:
			if str(row).contains(p):
				gendered.append(row)
	assert_eq(gendered, [], "a row must never assign a pronoun, since a job says nothing about who holds it: %s" % [gendered])
	assert_true(block.contains("never call a party member he or she"), "the rule must hold after a job change too")


func test_no_row_ever_carries_a_pronoun() -> void:
	var held: Dictionary = {}
	for j in STARTERS + ["guardian", "ninja"]:
		held[str(j).capitalize()] = j
	var rows: Array = _rows(DP._format_party_state(_party(held)))
	assert_eq(rows.size(), held.size(), "CONTROL: every member must be listed")
	for row in rows:
		for p in PRONOUNS:
			assert_false(str(row).contains(p), "row carries a pronoun: %s" % row)


func test_no_party_means_no_rule() -> void:
	assert_eq(DP._format_party_state({}), "", "no state means no block, and so no rule")


func test_both_npc_paths_carry_it() -> void:
	var st: Dictionary = _party({"Rogue": "rogue"})
	var opening: String = DP.build_npc_opening("Boris", "blacksmith", "Harmonia", [], [], "", st)
	var reply: String = DP.build_combined_reply("Boris", "blacksmith", "Harmonia", [], "prior", "Is the Rogue all right?", 4, [], st)
	assert_true(opening.contains("never call a party member he or she"), "the opening prompt must carry the rule")
	assert_true(reply.contains("never call a party member he or she"), "the reply prompt, where the misgendering was measured, must carry it")
